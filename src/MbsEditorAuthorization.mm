#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <math.h>
#include <string.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dlfcn.h>
#import "MbsEditorAuthorization.h"
#import "MbsEditorLicenseKey.h"

static unsigned MbsLegacyKeychainDenialCount(void) {
    auto count = (unsigned (*)())dlsym(RTLD_DEFAULT,"MbsLegacyKeychainDeniedCount");
    return count ? count() : 0;
}
static int64_t MbsGrantExpiry;
static unsigned MbsStartupRouteCount(void) {
    auto count = (unsigned (*)())dlsym(RTLD_DEFAULT,"MbsLegacyStartupPromptCount");
    return count ? count() : 0;
}
static double MbsGetGrantExpiry(void) { return __atomic_load_n(&MbsGrantExpiry,__ATOMIC_ACQUIRE); }
static void MbsSetGrantExpiry(double value) { __atomic_store_n(&MbsGrantExpiry,(int64_t)value,__ATOMIC_RELEASE); }
static NSString *MbsGrantHash(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *result = [NSMutableString string];
    for (unsigned char byte : digest) [result appendFormat:@"%02x",byte];
    return result;
}
static BOOL MbsGrantString(id value) { return [value isKindOfClass:NSString.class]; }
static BOOL MbsGrantNumber(id value) {
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID();
}
NSDictionary *MbsVerifyEditorGrant(NSData *response, NSData *publicKey,
    NSString *nonce, NSString *email, NSString *device, NSString *sessionHash, NSTimeInterval now) {
    if (!response.length || response.length > 16384 || publicKey.length != 65) return nil;
    id envelope = [NSJSONSerialization JSONObjectWithData:response options:0 error:nil];
    if (![envelope isKindOfClass:NSDictionary.class] || !MbsGrantString(envelope[@"payload"]) ||
        !MbsGrantString(envelope[@"signature"])) return nil;
    NSString *keyId = [@"mbs-editor-p256-" stringByAppendingString:[MbsGrantHash(publicKey) substringToIndex:16]];
    if (![envelope[@"keyId"] isEqual:keyId]) return nil;
    NSData *payload = [[NSData alloc] initWithBase64EncodedString:envelope[@"payload"] options:0];
    NSData *signature = [[NSData alloc] initWithBase64EncodedString:envelope[@"signature"] options:0];
    if (!payload.length || payload.length > 4096 || !signature.length || signature.length > 80) return nil;
    NSDictionary *attributes = @{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeyClass:(__bridge id)kSecAttrKeyClassPublic,(__bridge id)kSecAttrKeySizeInBits:@256};
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)publicKey,(__bridge CFDictionaryRef)attributes,NULL);
    if (!key) return nil;
    BOOL verified = SecKeyVerifySignature(key,kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)payload,(__bridge CFDataRef)signature,NULL);
    CFRelease(key);
    if (!verified) return nil;
    id claims = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
    if (![claims isKindOfClass:NSDictionary.class] || !MbsGrantNumber(claims[@"version"]) ||
        [claims[@"version"] integerValue] != 1 ||
        ![claims[@"issuer"] isEqual:@"https://ttys.ddxmu.com"] ||
        ![claims[@"audience"] isEqual:@"mbs.office.editor.custom"] ||
        ![claims[@"authority"] isEqual:@"mbs-custom"] ||
        ![claims[@"nonce"] isEqual:nonce] || ![claims[@"email"] isEqual:email] ||
        ![claims[@"deviceId"] isEqual:device] || ![claims[@"sessionHash"] isEqual:sessionHash] ||
        !MbsGrantNumber(claims[@"userId"]) || [claims[@"userId"] longLongValue] <= 0 ||
        !MbsGrantNumber(claims[@"issuedAt"]) || !MbsGrantNumber(claims[@"expiresAt"]) ||
        !MbsGrantString(claims[@"jti"]) || [claims[@"jti"] length] < 24) return nil;
    double issued = [claims[@"issuedAt"] doubleValue], expires = [claims[@"expiresAt"] doubleValue];
    if (!isfinite(issued) || !isfinite(expires) || issued > now+300 || expires <= now ||
        expires <= issued || expires-issued > 30*24*60*60) return nil;
    id activation = claims[@"activation"];
    NSString *activationState = claims[@"activationState"];
    if (activationState && (![@[@"active",@"expired",@"revoked",@"device_limit"] containsObject:activationState] ||
        ([activationState isEqual:@"active"] != (activation != nil)))) return nil;
    if (activation && (![activation isKindOfClass:NSDictionary.class] ||
        !MbsGrantNumber(activation[@"id"]) || [activation[@"id"] longLongValue] <= 0 ||
        ![@[@"standard",@"vip"] containsObject:activation[@"plan"] ?: @""] ||
        ![activation[@"deviceId"] isEqual:device] ||
        !MbsGrantNumber(activation[@"expiresAt"]) || !isfinite([activation[@"expiresAt"] doubleValue]) ||
        [activation[@"expiresAt"] doubleValue] < expires ||
        !MbsGrantNumber(activation[@"maxDevices"]) || [activation[@"maxDevices"] intValue] < 1 ||
        [activation[@"maxDevices"] intValue] > 10)) return nil;
    return claims;
}

bool MbsEditorGrantAllowsEditing(NSDictionary *claims) {
    // A signed account/status response is not itself an active editor license.
    // Older redeem responses include activation metadata without activationState.
    return [claims[@"activation"] isKindOfClass:NSDictionary.class] &&
        (!claims[@"activationState"] || [claims[@"activationState"] isEqual:@"active"]);
}

// The grant is bound to this private installation ID and current Mbs session.
static int MbsGrantDirectory(void) {
#ifdef MBS_EDITOR_AUTH_TESTS
    const char *testHome = getenv("MBS_TEST_HOME");
    if (!testHome) return -1;
    NSString *home = [NSString stringWithUTF8String:testHome];
#else
    NSString *home = NSHomeDirectory();
#endif
    NSString *path = [home stringByAppendingPathComponent:@"Library/Application Support/Mbs Office/Account"];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700} error:nil]) return -1;
    int fd = open(path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    struct stat info;
    if (fd < 0) return -1;
    if (fstat(fd,&info) || info.st_uid != getuid() || fchmod(fd,0700)) { close(fd); return -1; }
    return fd;
}
static NSData *MbsReadGrantFile(const char *name) {
    int dir = MbsGrantDirectory();
    if (dir < 0) return nil;
    int fd = openat(dir,name,O_RDONLY|O_NOFOLLOW|O_NONBLOCK); close(dir);
    if (fd < 0) return nil;
    struct stat info; char bytes[16384]; ssize_t count = -1;
    if (!fstat(fd,&info) && S_ISREG(info.st_mode) && info.st_uid == getuid() &&
        !(info.st_mode & 0077) && info.st_size > 0 && info.st_size < sizeof(bytes)) count = read(fd,bytes,sizeof(bytes));
    close(fd);
    return count > 0 ? [NSData dataWithBytes:bytes length:count] : nil;
}
static BOOL MbsWriteGrantFile(const char *name, NSData *data) {
    int dir = MbsGrantDirectory(); if (dir < 0) return NO;
    NSString *temporary = [@"grant-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int fd = openat(dir,temporary.UTF8String,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    BOOL ok = fd >= 0 && write(fd,data.bytes,data.length) == (ssize_t)data.length && !fsync(fd);
    if (fd >= 0) close(fd);
    if (ok) ok = !renameat(dir,temporary.UTF8String,dir,name);
    unlinkat(dir,temporary.UTF8String,0); close(dir); return ok;
}
static NSString *MbsGrantDevice(void) {
    NSData *saved = MbsReadGrantFile("device.id");
    NSString *device = saved ? [[NSString alloc] initWithData:saved encoding:NSUTF8StringEncoding] : nil;
    if (device) return [[NSUUID alloc] initWithUUIDString:device] ? device : nil;
    device = NSUUID.UUID.UUIDString;
    return MbsWriteGrantFile("device.id",[device dataUsingEncoding:NSUTF8StringEncoding]) ? device : nil;
}
static NSData *MbsPinnedGrantKey(void) {
    return [[NSData alloc] initWithBase64EncodedString:@MBS_EDITOR_LICENSE_PUBLIC_KEY options:0];
}

static NSArray *MbsNativeAuthorizationStates(void) {
    NSString *executable = NSBundle.mainBundle.executablePath;
    if (![executable.lastPathComponent isEqualToString:@"wpsoffice"] || !NSThread.isMainThread) return @[];
    const char *names[] = {"_ZN23KUnityCommonAuthHandler13commonManagerEv",
        "_ZN23KUnityCommonAuthHandler17enterpriseManagerEv", "_ZN23KUnityCommonAuthHandler15domesticManagerEv"};
    uintptr_t tables[] = {0xf32b0,0xf34e8,0xf33d0}, entries[] = {0x24210,0x4bfc0,0x24210};
    NSString *library = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents/Frameworks/office6/libauth.dylib"];
    void *handle = dlopen(library.fileSystemRepresentation,RTLD_LAZY|RTLD_NOLOAD);
    if (!handle) return @[@{@"available":@NO,@"reason":@"native_not_loaded"}];
    NSMutableArray *states = [NSMutableArray array];
    for (NSUInteger index=0;index<3;++index) {
        void *symbol = dlsym(handle,names[index]); Dl_info image;
        if (!symbol || !dladdr(symbol,&image)) { dlclose(handle); return @[@{@"available":@NO,@"reason":@"native_symbol_missing"}]; }
        NSString *path = [NSString stringWithUTF8String:image.dli_fname];
        if (![path hasPrefix:[NSBundle.mainBundle.bundlePath stringByAppendingString:@"/"]] ||
            ![path hasSuffix:@"/Frameworks/office6/libauth.dylib"]) { dlclose(handle); return @[@{@"available":@NO,@"reason":@"native_image_mismatch",@"image":path ?: @""}]; }
        uintptr_t base = (uintptr_t)image.dli_fbase;
        void *manager = ((void *(*)())symbol)();
        if (!manager || (uintptr_t)*(void **)manager != base+tables[index]) {
            uintptr_t table = manager ? (uintptr_t)*(void **)manager-base : 0;
            dlclose(handle); return @[@{@"available":@NO,@"reason":@"native_table_mismatch",@"managerIndex":@(index),@"tableRVA":@(table)}];
        }
        void *method = (*(void ***)manager)[25];
        if ((uintptr_t)method != base+entries[index]) { dlclose(handle); return @[@{@"available":@NO,@"reason":@"native_method_mismatch",@"methodRVA":@((uintptr_t)method-base)}]; }
        int level = -1;
        BOOL accepted = ((bool (*)(void *,int *))method)(manager,&level);
        [states addObject:@{@"manager":@[@"common",@"enterprise",@"domestic"][index],@"accepted":@(accepted),@"level":@(level)}];
    }
    dlclose(handle);
    return states;
}

@interface MbsEditorAuthorization : NSObject <NSURLSessionTaskDelegate>
@property NSString *token, *email, *device, *status, *activationState;
@property NSDictionary *activation;
@property NSURLSession *session;
@property NSURLSessionDataTask *task;
@property NSTimer *timer;
@property NSTimer *expiryTimer;
@property NSUInteger generation;
+ (instancetype)shared;
- (void)request;
- (void)requestWithActivationCode:(NSString *)code;
- (void)acceptVerifiedGrant:(NSDictionary *)claims response:(NSData *)data;
@end
@implementation MbsEditorAuthorization
+ (instancetype)shared {
    static MbsEditorAuthorization *value; static dispatch_once_t once;
    dispatch_once(&once,^{ value = [MbsEditorAuthorization new]; value.status = @"未连接"; });
    return value;
}
- (void)notify {
    BOOL verified = MbsHasVerifiedEditorLicense();
    [self.expiryTimer invalidate]; self.expiryTimer = nil;
    if (!verified && [self.activationState isEqual:@"active"]) {
        self.activationState = @"expired";
        self.status = @"授权已到期，请重新激活";
    }
    if (verified) self.expiryTimer = [NSTimer scheduledTimerWithTimeInterval:
        MAX(0.01,MbsGetGrantExpiry()-NSDate.date.timeIntervalSince1970) repeats:NO
        block:^(NSTimer *timer) { [self notify]; }];
    NSArray *native = verified ? MbsNativeAuthorizationStates() : @[];
    BOOL accepted = native.count == 3;
    auto quietKinds=(unsigned (*)())dlsym(RTLD_DEFAULT,"MbsLegacyQuietStartupKinds");
    unsigned quiet=quietKinds ? quietKinds() : 0;
    for (NSDictionary *state in native) accepted = accepted && [state[@"accepted"] boolValue] && [state[@"level"] intValue] >= 2;
    NSDictionary *receipt = @{@"verified":@(verified),@"nativeAccepted":@(accepted),@"nativeManagers":native,
        @"activation":verified && self.activation ? self.activation : (id)NSNull.null,
        @"activationState":self.activationState ?: @"unknown",
        @"legacyKeychainReadsDeclined":@(MbsLegacyKeychainDenialCount()),
        @"busy":@(self.task != nil),@"startupRoutes":@(MbsStartupRouteCount()),
        @"quietedLegacyLogin":@((quiet&1)!=0),@"quietedLegacyCloudNotice":@((quiet&2)!=0),
        @"status":self.status ?: @"未连接",@"authority":@"mbs-custom",@"originalVendorLicense":@NO,
        @"pid":@(getpid()),@"executable":NSBundle.mainBundle.executablePath ?: @"",
        @"expiresAt":@(MbsGetGrantExpiry()),@"recordedAt":@(NSDate.date.timeIntervalSince1970)};
    MbsWriteGrantFile("authorization-status.json",[NSJSONSerialization dataWithJSONObject:receipt options:0 error:nil]);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MbsEditorAuthorizationDidChange" object:nil userInfo:receipt];
}
- (void)request {
    [self requestWithActivationCode:nil];
}
- (void)acceptVerifiedGrant:(NSDictionary *)claims response:(NSData *)data {
    // Only call after signature and account/device/session binding verification.
    // A verified revocation must take effect even when persistence fails.
    BOOL saved = MbsWriteGrantFile("editor-license.json",data);
    MbsSetGrantExpiry(saved && MbsEditorGrantAllowsEditing(claims) ? [claims[@"expiresAt"] doubleValue] : 0);
    self.activation = claims[@"activation"];
    self.activationState = claims[@"activationState"] ?: (self.activation ? @"active" : @"unknown");
    self.status = self.activation ? @"授权码已激活" : @"账号已验证，尚无有效编辑授权";
    if ([self.activationState isEqual:@"expired"]) self.status = @"授权已到期，请重新激活";
    if ([self.activationState isEqual:@"revoked"]) self.status = @"授权已撤销，请使用新授权码";
    if ([self.activationState isEqual:@"device_limit"]) self.status = @"授权设备已达上限，请联系管理员";
    if (!saved) {
        int dir = MbsGrantDirectory(); if (dir >= 0) { unlinkat(dir,"editor-license.json",0); close(dir); }
        if (MbsEditorGrantAllowsEditing(claims)) {
            self.activation = nil; self.activationState = nil;
            self.status = @"授权未保存，请检查本机存储后重试";
        }
    }
}
- (void)requestWithActivationCode:(NSString *)activationCode {
    if (self.task || !self.token.length || !self.device.length) return;
    unsigned char bytes[32];
    if (SecRandomCopyBytes(kSecRandomDefault,sizeof(bytes),bytes) != errSecSuccess) return;
    NSString *nonce = [[[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0]
        stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    nonce = [[nonce stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"=" withString:@""];
    NSString *email = self.email, *device = self.device;
    NSString *sessionHash = MbsGrantHash([self.token dataUsingEncoding:NSUTF8StringEncoding]);
    NSUInteger generation = self.generation;
    self.status = activationCode ? @"正在兑换授权码…" : @"正在验证 Mbs 授权…"; [self notify];
    NSString *route = activationCode ? @"activation/redeem" : @"activation/auto";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:
        [@"https://ttys.ddxmu.com/api/mbs/" stringByAppendingString:route]]];
    request.HTTPMethod = @"POST";
    NSMutableDictionary *fields = [@{@"deviceId":device,@"nonce":nonce} mutableCopy];
    if (activationCode) fields[@"code"] = activationCode;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:fields options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[@"Bearer " stringByAppendingString:self.token] forHTTPHeaderField:@"Authorization"];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 30;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    self.task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (generation != self.generation) return;
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        BOOL correctURL = [response.URL.absoluteString isEqual:request.URL.absoluteString];
        NSDictionary *claims = !error && code == 200 && correctURL ? MbsVerifyEditorGrant(data,MbsPinnedGrantKey(),nonce,email,device,sessionHash,NSDate.date.timeIntervalSince1970) : nil;
        if (claims) {
            [self acceptVerifiedGrant:claims response:data];
        } else if (code == 401) {
            MbsSetGrantExpiry(0);
            self.activation = nil;
            self.activationState = nil;
            int dir = MbsGrantDirectory(); if (dir >= 0) { unlinkat(dir,"editor-license.json",0); close(dir); }
            self.status = @"登录已失效";
        } else if (activationCode) {
            id failure = data.length <= 16384 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *message = [failure isKindOfClass:NSDictionary.class] && MbsGrantString(failure[@"error"]) ? failure[@"error"] : nil;
            self.status = message.length && message.length < 160 ? message : @"兑换失败，请检查网络后重试";
        } else self.status = MbsHasVerifiedEditorLicense() ? @"授权有效，暂时无法续期" : @"Mbs 授权未通过，请检查网络";
        self.task = nil; [self.session finishTasksAndInvalidate]; self.session = nil; [self notify];
        if (claims) dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            if (generation == self.generation && MbsHasVerifiedEditorLicense()) [self notify];
        });
    }];
    [self notify];
    [self.task resume];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler { completionHandler(nil); }
@end

bool MbsHasVerifiedEditorLicense(void) { return MbsGetGrantExpiry() > CFAbsoluteTimeGetCurrent()+kCFAbsoluteTimeIntervalSince1970; }
bool MbsCanRestoreAccountSession(const char *token, const char *email) {
    MbsEditorAuthorization *value = MbsEditorAuthorization.shared;
    return token && email && MbsHasVerifiedEditorLicense() &&
        [value.token isEqualToString:[NSString stringWithUTF8String:token]] &&
        [value.email isEqualToString:[NSString stringWithUTF8String:email]];
}
void MbsRequestEditorLicense(const char *token, const char *email) {
    NSString *copiedToken = token ? [NSString stringWithUTF8String:token] : nil;
    NSString *copiedEmail = email ? [NSString stringWithUTF8String:email] : nil;
    void (^start)(void) = ^{
        MbsEditorAuthorization *value = MbsEditorAuthorization.shared;
        if (![value.token isEqual:copiedToken] || ![value.email isEqual:copiedEmail]) {
            value.generation++; [value.task cancel]; [value.session invalidateAndCancel]; value.task = nil;
            MbsSetGrantExpiry(0);
            value.activation = nil;
            value.activationState = nil;
        }
        value.token = copiedToken; value.email = copiedEmail; value.device = MbsGrantDevice();
        [value.timer invalidate];
        if (!value.token.length || !value.email.length || !value.device.length) { value.status = @"未连接"; [value notify]; return; }
        [value request];
        value.timer = [NSTimer scheduledTimerWithTimeInterval:300 repeats:YES block:^(NSTimer *timer) { [value request]; }];
    };
    if (NSThread.isMainThread) start(); else dispatch_async(dispatch_get_main_queue(),start);
}
void MbsRedeemActivationCode(const char *code) {
    NSString *copied = code ? [NSString stringWithUTF8String:code] : nil;
    copied = [[copied stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    dispatch_async(dispatch_get_main_queue(),^{
        MbsEditorAuthorization *value = MbsEditorAuthorization.shared;
        if (!value.token.length || !value.email.length) return;
        if (!copied.length || copied.length > 64) {
            value.status = @"请输入有效授权码"; [value notify]; return;
        }
        value.generation++; [value.task cancel]; [value.session invalidateAndCancel];
        value.task = nil; value.session = nil;
        [value requestWithActivationCode:copied];
    });
}
void MbsResetEditorLicense(void) {
    MbsSetGrantExpiry(0);
    void (^reset)(void) = ^{
        MbsEditorAuthorization *value = MbsEditorAuthorization.shared;
        value.generation++; [value.task cancel]; [value.session invalidateAndCancel]; [value.timer invalidate];
        value.timer = nil; value.task = nil; value.session = nil; value.token = nil; value.email = nil;
        MbsSetGrantExpiry(0); value.activation = nil; value.activationState = nil; value.status = @"未连接";
        int dir = MbsGrantDirectory(); if (dir >= 0) { unlinkat(dir,"editor-license.json",0); close(dir); }
        [value notify];
    };
    if (NSThread.isMainThread) reset(); else dispatch_async(dispatch_get_main_queue(),reset);
}
char *MbsCopyEditorAuthorizationState(void) {
    __block NSData *data;
    void (^read)(void) = ^{
        data = [NSJSONSerialization dataWithJSONObject:@{@"authority":@"mbs-custom",@"verified":@(MbsHasVerifiedEditorLicense()),
            @"expiresAt":@(MbsGetGrantExpiry()),@"status":MbsEditorAuthorization.shared.status ?: @"未连接",
            @"activation":MbsHasVerifiedEditorLicense() && MbsEditorAuthorization.shared.activation ? MbsEditorAuthorization.shared.activation : (id)NSNull.null,
            @"activationState":MbsEditorAuthorization.shared.activationState ?: @"unknown",
            @"busy":@(MbsEditorAuthorization.shared.task != nil),
            @"originalVendorLicense":@NO} options:0 error:nil];
    };
    if (NSThread.isMainThread) read(); else dispatch_sync(dispatch_get_main_queue(),read);
    return data ? strndup((const char *)data.bytes,data.length) : NULL;
}
__attribute__((constructor)) static void MbsRestoreEditorGrant(void) { @autoreleasepool {
    NSData *sessionData = MbsReadGrantFile("session.json"), *grantData = MbsReadGrantFile("editor-license.json");
    if (!sessionData || !grantData) return;
    id session = [NSJSONSerialization JSONObjectWithData:sessionData options:0 error:nil];
    id envelope = [NSJSONSerialization JSONObjectWithData:grantData options:0 error:nil];
    if (![session isKindOfClass:NSDictionary.class] || !MbsGrantString(session[@"token"]) || !MbsGrantString(session[@"email"]) ||
        ![envelope isKindOfClass:NSDictionary.class] || !MbsGrantString(envelope[@"payload"])) return;
    NSData *payload = [[NSData alloc] initWithBase64EncodedString:envelope[@"payload"] options:0];
    id untrusted = payload ? [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil] : nil;
    NSString *nonce = [untrusted isKindOfClass:NSDictionary.class] && MbsGrantString(untrusted[@"nonce"]) ? untrusted[@"nonce"] : nil;
    if (!nonce) return;
    NSDictionary *claims = MbsVerifyEditorGrant(grantData,MbsPinnedGrantKey(),nonce,session[@"email"],MbsGrantDevice(),
        MbsGrantHash([session[@"token"] dataUsingEncoding:NSUTF8StringEncoding]),NSDate.date.timeIntervalSince1970);
    if (claims) {
        MbsSetGrantExpiry(MbsEditorGrantAllowsEditing(claims) ? [claims[@"expiresAt"] doubleValue] : 0);
        MbsEditorAuthorization *value = MbsEditorAuthorization.shared;
        value.token = session[@"token"]; value.email = session[@"email"]; value.device = claims[@"deviceId"];
        value.activation = claims[@"activation"];
        value.activationState = claims[@"activationState"] ?: (value.activation ? @"active" : @"unknown");
        value.status = MbsEditorGrantAllowsEditing(claims) ? @"Mbs 授权已验证" : @"账号已验证，尚无有效编辑授权";
        if ([value.activationState isEqual:@"expired"]) value.status = @"授权已到期，请重新激活";
        if ([value.activationState isEqual:@"revoked"]) value.status = @"授权已撤销，请使用新授权码";
        if ([value.activationState isEqual:@"device_limit"]) value.status = @"授权设备已达上限，请联系管理员";
    }
} }
