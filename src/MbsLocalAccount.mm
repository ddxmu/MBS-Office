#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import "MbsLocalAccount.h"

static const uint32_t MbsPasswordRounds = 210000;
static NSString *NormalizedEmail(NSString *email) {
    return [[email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
}
static BOOL ValidEmail(NSString *email) {
    if (!email.length || email.length > 254) return NO;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^[A-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [pattern numberOfMatchesInString:email options:0 range:NSMakeRange(0, email.length)] == 1;
}
static BOOL ValidPassword(NSString *password) {
    __block NSUInteger count = 0;
    [password enumerateSubstringsInRange:NSMakeRange(0, password.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if (++count >= 8) *stop = YES;
    }];
    return count >= 8;
}
static NSData *PasswordHash(NSString *password, NSData *salt, uint32_t rounds) {
    NSData *encoded = [password dataUsingEncoding:NSUTF8StringEncoding];
    if (!encoded) return nil;
    unsigned char hash[32];
    int status = CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)encoded.bytes, encoded.length,
                                     (const unsigned char *)salt.bytes, salt.length,
                                     kCCPRFHmacAlgSHA256, rounds, hash, sizeof(hash));
    if (status != 0) return nil;
    NSData *result = [NSData dataWithBytes:hash length:sizeof(hash)];
    volatile unsigned char *wipe = hash;
    for (NSUInteger i = 0; i < sizeof(hash); ++i) wipe[i] = 0;
    return result;
}
static BOOL SameHash(NSData *left, NSData *right) {
    if (left.length != 32 || right.length != 32) return NO;
    const unsigned char *a = (const unsigned char *)left.bytes, *b = (const unsigned char *)right.bytes;
    volatile unsigned char difference = 0;
    for (NSUInteger i = 0; i < 32; ++i) difference |= a[i] ^ b[i];
    return difference == 0;
}

// A private injectable file URL keeps verification helpers away from real accounts.
@interface MbsLocalAccountStore : NSObject
@property(nonatomic, strong) NSURL *url;
- (instancetype)initWithURL:(NSURL *)url;
- (NSString *)registerEmail:(NSString *)email password:(NSString *)password;
- (NSString *)loginEmail:(NSString *)email password:(NSString *)password;
@end

@implementation MbsLocalAccountStore
- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) _url = url;
    return self;
}
- (NSMutableDictionary *)accounts:(NSString **)error {
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:self.url.path];
    if (!exists) return [NSMutableDictionary dictionary];
    NSData *data = [NSData dataWithContentsOfURL:self.url];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![object isKindOfClass:NSDictionary.class] || ![object[@"version"] isEqual:@1] ||
        ![object[@"local_only"] isEqual:@YES] || ![object[@"accounts"] isKindOfClass:NSDictionary.class]) {
        if (error) *error = @"本机账号文件无法读取，未修改原文件。请检查文件权限或恢复备份。";
        return nil;
    }
    NSDictionary *records = object[@"accounts"];
    for (id email in records) {
        id record = records[email];
        id saltString = [record isKindOfClass:NSDictionary.class] ? record[@"salt"] : nil;
        id hashString = [record isKindOfClass:NSDictionary.class] ? record[@"hash"] : nil;
        id rounds = [record isKindOfClass:NSDictionary.class] ? record[@"rounds"] : nil;
        NSData *salt = [saltString isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:saltString options:0] : nil;
        NSData *hash = [hashString isKindOfClass:NSString.class] ? [[NSData alloc] initWithBase64EncodedString:hashString options:0] : nil;
        if (![email isKindOfClass:NSString.class] || !ValidEmail(email) || ![record isKindOfClass:NSDictionary.class] ||
            ![record[@"algorithm"] isEqual:@"PBKDF2-HMAC-SHA256"] || salt.length < 16 || hash.length != 32 ||
            ![rounds isKindOfClass:NSNumber.class] || [rounds unsignedIntegerValue] < MbsPasswordRounds || [rounds unsignedIntegerValue] > 1000000) {
            if (error) *error = @"本机账号文件格式不正确，未修改原文件。";
            return nil;
        }
    }
    return [records mutableCopy];
}
- (NSString *)registerEmail:(NSString *)email password:(NSString *)password {
    email = NormalizedEmail(email);
    if (!ValidEmail(email)) return @"请输入有效的邮箱地址。";
    if (!ValidPassword(password)) return @"密码至少需要 8 个字符。";
    NSString *error = nil;
    NSMutableDictionary *accounts = [self accounts:&error];
    if (!accounts) return error;
    if (accounts[email]) return @"此邮箱已在本机注册，请切换到登录。";
    unsigned char bytes[16];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) return @"无法生成安全随机数，请稍后重试。";
    NSData *salt = [NSData dataWithBytes:bytes length:sizeof(bytes)];
    NSData *hash = PasswordHash(password, salt, MbsPasswordRounds);
    if (!hash) return @"密码处理失败，请稍后重试。";
    accounts[email] = @{@"algorithm":@"PBKDF2-HMAC-SHA256", @"rounds":@(MbsPasswordRounds),
                        @"salt":[salt base64EncodedStringWithOptions:0], @"hash":[hash base64EncodedStringWithOptions:0]};
    NSURL *directory = [self.url URLByDeletingLastPathComponent];
    NSError *fileError = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&fileError]) return @"无法创建本机账号目录，请检查文件权限。";
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version":@1, @"local_only":@YES, @"accounts":accounts} options:NSJSONWritingPrettyPrinted error:&fileError];
    if (!data || ![data writeToURL:self.url options:NSDataWritingAtomic error:&fileError]) return @"账号保存失败，请检查本机文件权限。";
    if (![[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self.url.path error:&fileError]) return @"账号已保存，但无法设置私有文件权限，请检查账号文件权限后登录。";
    return nil;
}
- (NSString *)loginEmail:(NSString *)email password:(NSString *)password {
    email = NormalizedEmail(email);
    if (!ValidEmail(email)) return @"请输入有效的邮箱地址。";
    NSString *error = nil;
    NSDictionary *accounts = [self accounts:&error];
    if (!accounts) return error;
    NSDictionary *record = accounts[email];
    NSData *salt = record ? [[NSData alloc] initWithBase64EncodedString:record[@"salt"] options:0] : [NSMutableData dataWithLength:16];
    uint32_t rounds = record ? [record[@"rounds"] unsignedIntValue] : MbsPasswordRounds;
    NSData *candidate = PasswordHash(password, salt, rounds);
    NSData *expected = record ? [[NSData alloc] initWithBase64EncodedString:record[@"hash"] options:0] : [NSMutableData dataWithLength:32];
    BOOL equal = SameHash(candidate, expected);
    return record && equal ? nil : @"邮箱或密码不正确。";
}
@end

@interface MbsLocalAccountController : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSSegmentedControl *mode;
@property(nonatomic, strong) NSTextField *email, *status, *confirmLabel;
@property(nonatomic, strong) NSSecureTextField *password, *confirm;
@property(nonatomic, strong) NSButton *submit, *logout;
@property(nonatomic, strong) MbsLocalAccountStore *store;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, copy) NSString *sessionEmail;
+ (instancetype)shared;
- (void)show;
@end

static NSTextField *AccountLabel(NSView *view, NSString *text, NSRect frame) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.frame = frame;
    [view addSubview:label];
    return label;
}

@implementation MbsLocalAccountController
+ (instancetype)shared {
    static MbsLocalAccountController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        controller = [MbsLocalAccountController new];
        NSURL *root = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        NSURL *url = [[root URLByAppendingPathComponent:@"Mbs Office" isDirectory:YES] URLByAppendingPathComponent:@"local-accounts.json"];
        controller.store = [[MbsLocalAccountStore alloc] initWithURL:url];
        controller.queue = dispatch_queue_create("com.mbs.office.local-account", DISPATCH_QUEUE_SERIAL);
    });
    return controller;
}
- (void)show {
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 570, 440) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
        self.window.title = @"本机账号（仅本机有效）";
        self.window.releasedWhenClosed = NO;
        [self.window center];
        NSView *view = self.window.contentView;
        AccountLabel(view, @"仅本机有效，尚未连接账号服务器。", NSMakeRect(24, 396, 522, 24));
        AccountLabel(view, @"自研功能无需账号即可免费使用；本机登录不改变 WPS 付费功能授权。", NSMakeRect(24, 350, 522, 42));
        self.mode = [NSSegmentedControl segmentedControlWithLabels:@[@"登录", @"注册"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeMode:)];
        self.mode.frame = NSMakeRect(24, 309, 522, 30);
        self.mode.selectedSegment = 0;
        [view addSubview:self.mode];
        AccountLabel(view, @"邮箱", NSMakeRect(24, 269, 90, 24));
        self.email = [[NSTextField alloc] initWithFrame:NSMakeRect(121, 265, 425, 28)];
        self.email.placeholderString = @"name@example.com";
        [view addSubview:self.email];
        AccountLabel(view, @"密码", NSMakeRect(24, 226, 90, 24));
        self.password = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(121, 222, 425, 28)];
        self.password.placeholderString = @"至少 8 个字符";
        [view addSubview:self.password];
        self.confirmLabel = AccountLabel(view, @"确认密码", NSMakeRect(24, 183, 90, 24));
        self.confirm = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(121, 179, 425, 28)];
        [view addSubview:self.confirm];
        self.status = AccountLabel(view, @"未登录。账号仅用于本机，退出应用后需要重新登录。", NSMakeRect(24, 75, 522, 87));
        self.submit = [NSButton buttonWithTitle:@"登录" target:self action:@selector(submit:)];
        self.submit.frame = NSMakeRect(422, 24, 124, 32);
        self.submit.bezelStyle = NSBezelStyleRounded;
        [view addSubview:self.submit];
        self.logout = [NSButton buttonWithTitle:@"退出登录" target:self action:@selector(logout:)];
        self.logout.frame = NSMakeRect(24, 24, 124, 32);
        self.logout.bezelStyle = NSBezelStyleRounded;
        self.logout.enabled = NO;
        [view addSubview:self.logout];
        [self changeMode:nil];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}
- (void)changeMode:(id)sender {
    BOOL registering = self.mode.selectedSegment == 1;
    self.confirm.hidden = !registering;
    self.confirmLabel.hidden = !registering;
    self.confirm.stringValue = @"";
    self.submit.title = registering ? @"注册并登录" : @"登录";
}
- (void)setBusy:(BOOL)busy {
    self.submit.enabled = !busy;
    self.mode.enabled = !busy;
    self.email.enabled = !busy;
    self.password.enabled = !busy;
    self.confirm.enabled = !busy;
    self.logout.enabled = !busy && self.sessionEmail.length > 0;
}
- (void)submit:(id)sender {
    BOOL registering = self.mode.selectedSegment == 1;
    NSString *email = NormalizedEmail(self.email.stringValue), *password = self.password.stringValue;
    if (!ValidEmail(email)) { self.status.stringValue = @"请输入有效的邮箱地址。"; return; }
    if (registering && !ValidPassword(password)) { self.status.stringValue = @"密码至少需要 8 个字符。"; return; }
    if (registering && ![password isEqualToString:self.confirm.stringValue]) { self.status.stringValue = @"两次密码不一致，请重新输入。"; return; }
    self.password.stringValue = @"";
    self.confirm.stringValue = @"";
    [self setBusy:YES];
    self.status.stringValue = registering ? @"正在安全保存本机账号…" : @"正在验证本机账号…";
    dispatch_async(self.queue, ^{
        NSString *error = registering ? [self.store registerEmail:email password:password] : [self.store loginEmail:email password:password];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) self.status.stringValue = error;
            else {
                self.sessionEmail = email;
                self.status.stringValue = [NSString stringWithFormat:@"已登录：%@\n仅本机有效，未连接服务器。退出应用后会结束本次登录。", email];
            }
            [self setBusy:NO];
        });
    });
}
- (void)logout:(id)sender {
    self.sessionEmail = nil;
    self.password.stringValue = @"";
    self.confirm.stringValue = @"";
    self.logout.enabled = NO;
    self.status.stringValue = @"已退出本机登录。自研功能仍可免费使用。";
}
@end

void MbsShowLocalAccount(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsLocalAccountController shared] show]; });
}
const char *MbsLocalAccountCapabilities(void) {
    return "{\"version\":1,\"localOnly\":true,\"session\":\"local_only_memory\",\"serverConnected\":false,\"accountRequired\":false,\"freeFeatures\":[\"custom_ai\",\"local_account\"],\"freeFeaturesScope\":\"Mbs self-developed features only\",\"changesWpsPaidEntitlements\":false}";
}
