#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#include <unistd.h>
#include "MbsUpdates.h"

static NSString *MbsVersion(id value, BOOL allowTagPrefix)
{
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *version = value;
    if (allowTagPrefix && [version hasPrefix:@"v"]) version = [version substringFromIndex:1];
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"^(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})$"
        options:0 error:nil];
    NSRange range = NSMakeRange(0,version.length);
    NSTextCheckingResult *match = [pattern firstMatchInString:version options:0 range:range];
    return match && NSEqualRanges(match.range,range) ? version : nil;
}

static NSComparisonResult MbsCompareVersions(NSString *left, NSString *right)
{
    NSArray<NSString *> *a = [left componentsSeparatedByString:@"."];
    NSArray<NSString *> *b = [right componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < 3; ++i) {
        if (a[i].longLongValue < b[i].longLongValue) return NSOrderedAscending;
        if (a[i].longLongValue > b[i].longLongValue) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

static BOOL MbsUpdateURLAllowed(NSURL *url)
{
    if (![url.scheme.lowercaseString isEqualToString:@"https"] ||
        url.user.length || url.password.length || (url.port && url.port.integerValue != 443)) return NO;
    return [@[@"github.com", @"api.github.com", @"objects.githubusercontent.com",
              @"release-assets.githubusercontent.com", @"github-releases.githubusercontent.com"]
            containsObject:url.host.lowercaseString];
}

static NSURL *MbsAssetURL(id value, NSString *name)
{
    if (![value isKindOfClass:NSString.class]) return nil;
    NSURL *url = [NSURL URLWithString:value];
    if (!MbsUpdateURLAllowed(url) || ![url.host.lowercaseString isEqualToString:@"github.com"] ||
        ![url.path hasPrefix:@"/ddxmu/MBS-Office/releases/download/"] ||
        ![url.lastPathComponent isEqualToString:name]) return nil;
    return url;
}

static NSString *MbsSha256Digest(id digest)
{
    if (![digest isKindOfClass:NSString.class]) return nil;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"^sha256:([a-fA-F0-9]{64})$" options:0 error:nil];
    NSTextCheckingResult *match = [pattern firstMatchInString:digest options:0
        range:NSMakeRange(0,[(NSString *)digest length])];
    return match && NSEqualRanges(match.range,NSMakeRange(0,[(NSString *)digest length])) ?
        [[digest substringWithRange:[match rangeAtIndex:1]] lowercaseString] : nil;
}

static NSString *MbsHexDigest(const unsigned char *bytes)
{
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; ++i) [hex appendFormat:@"%02x",bytes[i]];
    return hex;
}

static NSString *MbsDataSha256(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    return MbsHexDigest(digest);
}

static NSString *MbsFileSha256(NSURL *url)
{
    NSInputStream *stream = [NSInputStream inputStreamWithURL:url];
    [stream open];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[65536];
    NSInteger size;
    while ((size = [stream read:buffer maxLength:sizeof(buffer)]) > 0)
        CC_SHA256_Update(&context,buffer,(CC_LONG)size);
    [stream close];
    if (size < 0) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest,&context);
    return MbsHexDigest(digest);
}

static NSString *MbsChecksumForAsset(NSData *data, NSString *name)
{
    if (data.length > 1024*1024) return nil;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return nil;
    NSString *escaped = [NSRegularExpression escapedPatternForString:name];
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        [NSString stringWithFormat:@"^([a-fA-F0-9]{64})[ \\t]+\\*?%@$",escaped]
        options:0 error:nil];
    NSString *result = nil;
    for (NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSTextCheckingResult *match = [pattern firstMatchInString:line options:0
            range:NSMakeRange(0,line.length)];
        if (!match) continue;
        NSString *digest = [[line substringWithRange:[match rangeAtIndex:1]] lowercaseString];
        if (result && ![result isEqualToString:digest]) return nil;
        result = digest;
    }
    return result;
}

static BOOL MbsSignatureDataValid(NSData *data)
{
    if (!data.length || data.length > 4096) return NO;
    NSString *encoded = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    encoded = [encoded stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSData *signature = encoded.length ? [[NSData alloc] initWithBase64EncodedString:encoded options:0] : nil;
    return signature.length == 64;
}

static NSDictionary *MbsUpdateCandidate(NSDictionary *release, NSString *current)
{
    NSString *version = MbsVersion(release[@"tag_name"],YES);
    if (!version || !MbsVersion(current,NO) || ![release[@"draft"] isKindOfClass:NSNumber.class] ||
        ![release[@"prerelease"] isKindOfClass:NSNumber.class] || [release[@"draft"] boolValue] ||
        [release[@"prerelease"] boolValue] || MbsCompareVersions(version,current) != NSOrderedDescending)
        return nil;
    NSArray *assets = release[@"assets"];
    if (![assets isKindOfClass:NSArray.class]) return nil;
    NSString *legacyName = [NSString stringWithFormat:@"MbsOffice-modules-%@.zip",version];
    NSString *compatibleName = [NSString stringWithFormat:@"MbsOffice-modules-%@-from-%@.zip",version,current];
    NSArray<NSString *> *candidateNames = @[compatibleName,legacyName];
    NSMutableDictionary<NSString *,NSDictionary *> *assetsByName = [NSMutableDictionary dictionary];
    NSDictionary *checksums = nil;
    for (id item in assets) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *assetName = item[@"name"];
        if (![assetName isKindOfClass:NSString.class]) continue;
        if ([candidateNames containsObject:assetName] ||
            [candidateNames containsObject:[assetName stringByDeletingPathExtension]]) {
            if (assetsByName[assetName]) return nil;
            assetsByName[assetName] = item;
        }
        if ([assetName isEqual:@"checksums.sha256"]) {
            if (checksums) return nil;
            checksums = item;
        }
    }
    NSString *name = nil;
    NSDictionary *module = nil, *signature = nil;
    for (NSString *candidateName in candidateNames) {
        NSDictionary *candidateModule = assetsByName[candidateName];
        NSDictionary *candidateSignature = assetsByName[[candidateName stringByAppendingString:@".sig"]];
        if (candidateModule && candidateSignature) {
            name = candidateName;
            module = candidateModule;
            signature = candidateSignature;
            break;
        }
    }
    if (!module || ![module[@"size"] isKindOfClass:NSNumber.class] ||
        [module[@"size"] longLongValue] <= 0 || [module[@"size"] longLongValue] > 512LL*1024*1024) return nil;
    NSURL *url = MbsAssetURL(module[@"browser_download_url"],name);
    if (!url) return nil;
    NSString *signatureName = [name stringByAppendingString:@".sig"];
    NSURL *signatureURL = MbsAssetURL(signature[@"browser_download_url"],signatureName);
    if (!signatureURL || ![signature[@"size"] isKindOfClass:NSNumber.class] ||
        [signature[@"size"] longLongValue] <= 0 || [signature[@"size"] longLongValue] > 4096) return nil;
    id rawDigest = module[@"digest"];
    NSString *digest = MbsSha256Digest(rawDigest);
    if (rawDigest && rawDigest != NSNull.null && !digest) return nil;
    id rawSignatureDigest = signature[@"digest"];
    NSString *signatureDigest = MbsSha256Digest(rawSignatureDigest);
    if (rawSignatureDigest && rawSignatureDigest != NSNull.null && !signatureDigest) return nil;
    NSURL *checksumURL = nil;
    NSString *checksumDigest = nil;
    if (!digest) {
        checksumURL = MbsAssetURL(checksums[@"browser_download_url"],@"checksums.sha256");
        if (!checksumURL || ![checksums[@"size"] isKindOfClass:NSNumber.class] ||
            [checksums[@"size"] longLongValue] <= 0 || [checksums[@"size"] longLongValue] > 1024*1024) return nil;
        id raw = checksums[@"digest"];
        checksumDigest = MbsSha256Digest(raw);
        if (raw && raw != NSNull.null && !checksumDigest) return nil;
    }
    return @{@"version":version,@"name":name,@"url":url,@"size":module[@"size"],
             @"digest":digest ?: @"",@"checksumURL":checksumURL ?: NSNull.null,
             @"checksumDigest":checksumDigest ?: @"",@"signatureURL":signatureURL,
             @"signatureName":signatureName,@"signatureDigest":signatureDigest ?: @""};
}

static NSBundle *MbsOuterBundle(void)
{
    NSURL *url = NSBundle.mainBundle.bundleURL;
    while (url.path.length > 1) {
        if ([url.pathExtension.lowercaseString isEqualToString:@"app"]) {
            NSBundle *bundle = [NSBundle bundleWithURL:url];
            if ([bundle.bundleIdentifier isEqualToString:@"com.mbs.office.launcher"]) return bundle;
        }
        url = url.URLByDeletingLastPathComponent;
    }
    return nil;
}

static NSURL *MbsInstallerURL(NSBundle *outer)
{
    if (!outer) return nil;
    NSArray<NSString *> *paths = @[
        @"Contents/Resources/MbsModuleInstaller",
        @"Contents/Resources/MbsEngine.app/Contents/Resources/MbsModuleInstaller"
    ];
    for (NSString *path in paths) {
        NSURL *candidate = [outer.bundleURL URLByAppendingPathComponent:path];
        if ([NSFileManager.defaultManager isExecutableFileAtPath:candidate.path]) return candidate;
    }
    return nil;
}

static NSString *MbsInstallerFailure(NSData *data, NSString *fromVersion, NSString *toVersion)
{
    if (!data.length || data.length > 16384) return nil;
    id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![result isKindOfClass:NSDictionary.class] ||
        ![result[@"format"] isEqual:@"mbs-update-result-v1"] ||
        ![result[@"fromVersion"] isEqual:fromVersion] ||
        (toVersion && ![result[@"toVersion"] isEqual:toVersion]) ||
        ![result[@"state"] isEqual:@"failed"]) return nil;
    NSString *message = result[@"message"];
    return [message isKindOfClass:NSString.class] && message.length && message.length <= 1000 ? message : nil;
}

static BOOL MbsInstallerReady(NSData *data, NSString *fromVersion, NSString *toVersion)
{
    if (!data.length || data.length > 16384) return NO;
    id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [result isKindOfClass:NSDictionary.class] &&
        [result[@"format"] isEqual:@"mbs-update-result-v1"] &&
        [result[@"fromVersion"] isEqual:fromVersion] &&
        [result[@"toVersion"] isEqual:toVersion] && [result[@"state"] isEqual:@"waiting"];
}

static NSData *MbsInstallerReceipt(void)
{
    NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *file = [base URLByAppendingPathComponent:@"Mbs Office/Updates/status.json"];
    NSNumber *size = nil;
    [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    return size.unsignedLongLongValue <= 16384 ? [NSData dataWithContentsOfURL:file] : nil;
}

@interface MbsUpdatesController : NSObject <NSURLSessionDownloadDelegate>
@property NSWindow *window;
@property NSTextField *currentLabel, *latestLabel, *statusLabel;
@property NSProgressIndicator *progress;
@property NSButton *upgradeButton, *checkButton, *revealButton;
@property NSURLSession *session;
@property NSURLSessionDownloadTask *downloadTask;
@property NSTimer *timer, *installerTimer;
@property NSString *currentVersion, *notifiedVersion, *expectedDigest;
@property NSDictionary *candidate;
@property NSURL *downloadedURL, *downloadedSignatureURL;
@property NSTask *installerTask;
@property BOOL checking, downloading, installing, started, downloadHandled, installerExitRequested;
@end

@implementation MbsUpdatesController
- (instancetype)init
{
    if ((self = [super init])) {
        _currentVersion = MbsVersion([MbsOuterBundle() objectForInfoDictionaryKey:@"CFBundleShortVersionString"],NO);
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest = 30;
        configuration.timeoutIntervalForResource = 1800;
        configuration.HTTPAdditionalHeaders = @{@"User-Agent":@"MbsOffice-ModulesUpdater"};
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
    }
    return self;
}
- (NSTextField *)label:(NSString *)text frame:(NSRect)frame
{
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.frame = frame;
    [self.window.contentView addSubview:label];
    return label;
}
- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame
{
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.frame = frame;
    button.bezelStyle = NSBezelStyleRounded;
    [self.window.contentView addSubview:button];
    return button;
}
- (void)ensureWindow
{
    if (self.window) return;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,580,340)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Mbs Office 版本升级";
    self.window.releasedWhenClosed = NO;
    [self.window center];
    [self label:@"Mbs Office 软件更新" frame:NSMakeRect(24,290,532,26)].font = [NSFont boldSystemFontOfSize:19];
    self.currentLabel = [self label:[NSString stringWithFormat:@"当前版本：%@",self.currentVersion ?: @"无法读取"]
        frame:NSMakeRect(24,252,260,22)];
    self.latestLabel = [self label:@"最新版本：尚未检查" frame:NSMakeRect(294,252,262,22)];
    self.statusLabel = [self label:@"尚未检查更新。" frame:NSMakeRect(24,174,532,64)];
    [self label:@"下载完成后，请按提示保存文档并退出。程序将自动完成安装并重新启动。"
        frame:NSMakeRect(24,71,532,40)].textColor = NSColor.secondaryLabelColor;
    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(24,134,532,16)];
    self.progress.style = NSProgressIndicatorStyleBar;
    self.progress.minValue = 0;
    self.progress.maxValue = 100;
    self.progress.hidden = YES;
    [self.window.contentView addSubview:self.progress];
    self.checkButton = [self button:@"检查更新" action:@selector(checkAgain:) frame:NSMakeRect(24,23,110,32)];
    self.revealButton = [self button:@"查看下载" action:@selector(reveal:) frame:NSMakeRect(144,23,110,32)];
    self.revealButton.hidden = YES;
    self.upgradeButton = [self button:@"版本升级" action:@selector(upgrade:) frame:NSMakeRect(440,23,116,32)];
    self.upgradeButton.enabled = NO;
}
- (void)refreshButtons
{
    self.checkButton.enabled = !self.checking && !self.downloading && !self.installing;
    self.upgradeButton.enabled = self.candidate && !self.checking && !self.downloading && !self.installing;
    self.revealButton.hidden = !self.downloadedURL;
}
- (void)show
{
    [self ensureWindow];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}
- (void)start
{
    if (self.started) return;
    self.started = YES;
    self.timer = [NSTimer scheduledTimerWithTimeInterval:6*60*60 repeats:YES block:^(NSTimer *) {
        [self check:NO];
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ [self check:NO]; });
}
- (void)fetch:(NSURL *)url completion:(void (^)(NSData *, NSInteger, NSError *))completion
{
    if (!MbsUpdateURLAllowed(url)) {
        completion(nil,0,[NSError errorWithDomain:@"MbsUpdates" code:1 userInfo:nil]);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:[url.host isEqualToString:@"api.github.com"] ? @"application/vnd.github+json" : @"application/octet-stream"
        forHTTPHeaderField:@"Accept"];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (response && !MbsUpdateURLAllowed(response.URL)) error = [NSError errorWithDomain:@"MbsUpdates" code:1 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(data,status,error); });
    }] resume];
}
- (void)check:(BOOL)manual
{
    if (self.checking || self.downloading) return;
    [self ensureWindow];
    if (!self.currentVersion) {
        self.statusLabel.stringValue = @"无法读取 Mbs Office 当前版本，暂时不能检查更新。";
        return;
    }
    self.checking = YES;
    self.statusLabel.stringValue = @"正在检查可用更新…";
    [self refreshButtons];
    [self fetch:[NSURL URLWithString:@"https://api.github.com/repos/ddxmu/MBS-Office/releases/latest"]
        completion:^(NSData *data, NSInteger status, NSError *error) {
        self.checking = NO;
        if (error || (status != 200 && status != 404)) {
            self.statusLabel.stringValue = (status == 403 || status == 429) ?
                @"GitHub 暂时限制请求，请稍后重试。" : @"暂时无法检查更新，请稍后重试。";
            [self refreshButtons];
            return;
        }
        self.candidate = nil;
        if (status == 404) {
            self.latestLabel.stringValue = @"最新版本：暂无发布版本";
            self.statusLabel.stringValue = @"当前无可用更新。";
        } else {
            id release = data.length && data.length <= 2*1024*1024 ?
                [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (![release isKindOfClass:NSDictionary.class]) {
                self.statusLabel.stringValue = @"更新信息无法读取，请稍后重试。";
                [self refreshButtons];
                return;
            }
            NSString *version = MbsVersion(release[@"tag_name"],YES);
            BOOL older=version && MbsCompareVersions(version,self.currentVersion)==NSOrderedAscending;
            self.latestLabel.stringValue = [NSString stringWithFormat:@"%@：%@",older ? @"公开版本" : @"最新版本",version ?: @"暂无适配版本"];
            self.candidate = MbsUpdateCandidate(release,self.currentVersion);
            self.statusLabel.stringValue = self.candidate ?
                [NSString stringWithFormat:@"发现新版本 %@。点击“版本升级”下载安装。",self.candidate[@"version"]] :
                (older ? @"当前版本高于公开版本，无需降级。" :
                 (version && MbsCompareVersions(version,self.currentVersion)==NSOrderedSame ? @"当前已是最新版本。" : @"当前没有适用于本版本的更新，请稍后重试。"));
        }
        self.progress.hidden = YES;
        self.upgradeButton.title = @"版本升级";
        [self refreshButtons];
        if (self.candidate && ![self.notifiedVersion isEqual:self.candidate[@"version"]]) {
            self.notifiedVersion = self.candidate[@"version"];
            if (!manual) [self show];
        }
    }];
}
- (void)checkAgain:(id)sender { (void)sender; [self check:YES]; }
- (void)reveal:(id)sender
{
    (void)sender;
    if (self.downloadedURL) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[self.downloadedURL]];
}
- (void)downloadFailed:(NSString *)message
{
    self.downloading = NO;
    self.installing = NO;
    self.installerExitRequested = NO;
    [self.installerTimer invalidate];
    self.installerTimer = nil;
    self.downloadTask = nil;
    self.statusLabel.stringValue = message;
    [self.progress stopAnimation:nil];
    self.progress.hidden = YES;
    self.upgradeButton.title = @"版本升级";
    [self refreshButtons];
}
- (void)startInstaller
{
    NSBundle *outer = MbsOuterBundle();
    NSURL *installer = MbsInstallerURL(outer);
    if (!outer || !self.downloadedURL || !self.downloadedSignatureURL ||
        ![NSFileManager.defaultManager isExecutableFileAtPath:installer.path]) {
        [self downloadFailed:@"安装器不可用，更新文件已保留但未安装。请重新安装最新版 Mbs Office。"];
        return;
    }
    NSTask *task = [NSTask new];
    task.executableURL = installer;
    task.arguments = @[@"--package", self.downloadedURL.path,
                       @"--signature", self.downloadedSignatureURL.path,
                       @"--app", outer.bundleURL.path,
                       @"--wait-pid", [NSString stringWithFormat:@"%d", getpid()]];
    // The installer must survive this application's normal exit. Its durable
    // status is in Updates/status.json, not in a pipe owned by this process.
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    __weak MbsUpdatesController *weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            MbsUpdatesController *controller = weakSelf;
            if (!controller || controller.installerTask != finished || !controller.installing) return;
            NSString *message = MbsInstallerFailure(MbsInstallerReceipt(),controller.currentVersion,
                controller.candidate[@"version"]);
            controller.installerTask = nil;
            [controller downloadFailed:message ?: @"安装器已退出但更新尚未完成，请保存文档后重新升级。原有备份已保留。"];
        });
    };
    @try {
        [task launch];
    } @catch (NSException *exception) {
        [self downloadFailed:@"安装器启动失败，更新文件已保留但未安装。"];
        return;
    }
    self.installerTask = task;
    self.installing = YES;
    self.installerExitRequested = NO;
    self.statusLabel.stringValue = @"正在准备并校验安装文件，文稿仍可使用。准备完成后才会退出并自动安装重启。";
    self.progress.indeterminate = YES;
    [self.progress startAnimation:nil];
    [self refreshButtons];
    self.upgradeButton.title = @"准备更新";
    self.upgradeButton.enabled = NO;
    [self.installerTimer invalidate];
    self.installerTimer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        MbsUpdatesController *controller = weakSelf;
        if (!controller || controller.installerTask != task || !controller.installing) { [timer invalidate]; return; }
        if (controller.installerExitRequested || !MbsInstallerReady(MbsInstallerReceipt(),
            controller.currentVersion,controller.candidate[@"version"])) return;
        controller.installerExitRequested = YES;
        controller.statusLabel.stringValue = @"安装文件已准备好，正在退出；如有未保存文稿请按提示保存，随后自动安装并重启。";
        [controller.progress stopAnimation:nil];
        controller.upgradeButton.title = @"等待退出";
        [NSApp terminate:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(), ^{
            if (!controller.installing || controller.installerTask != task || !task.running) return;
            controller.statusLabel.stringValue = @"安装已准备好。如取消过退出，请先保存文稿，再点击“继续退出”；不会强制关闭文稿。";
            controller.upgradeButton.title = @"继续退出";
            controller.upgradeButton.enabled = YES;
        });
    }];
    [NSRunLoop.mainRunLoop addTimer:self.installerTimer forMode:NSRunLoopCommonModes];
}
- (void)beginDownload:(NSString *)digest
{
    self.expectedDigest = digest;
    self.downloadHandled = NO;
    self.progress.indeterminate = NO;
    self.progress.doubleValue = 0;
    self.statusLabel.stringValue = @"正在下载模块：0%";
    self.downloadTask = [self.session downloadTaskWithURL:self.candidate[@"url"]];
    [self.downloadTask resume];
}
- (void)upgrade:(id)sender
{
    (void)sender;
    if (self.installing) { if (self.installerExitRequested) [NSApp terminate:nil]; return; }
    if (!self.candidate || self.checking || self.downloading || self.installing) return;
    self.downloading = YES;
    self.downloadedURL = nil;
    self.downloadedSignatureURL = nil;
    self.progress.hidden = NO;
    [self refreshButtons];
    NSString *digest = self.candidate[@"digest"];
    if (digest.length) { [self beginDownload:digest]; return; }
    self.statusLabel.stringValue = @"正在获取模块校验信息…";
    self.progress.indeterminate = YES;
    [self.progress startAnimation:nil];
    [self fetch:self.candidate[@"checksumURL"] completion:^(NSData *data, NSInteger status, NSError *error) {
        NSString *checksumDigest = self.candidate[@"checksumDigest"];
        NSString *expected = (!error && status == 200 && data.length && data.length <= 1024*1024 &&
            (!checksumDigest.length || [MbsDataSha256(data) isEqualToString:checksumDigest])) ?
            MbsChecksumForAsset(data,self.candidate[@"name"]) : nil;
        [self.progress stopAnimation:nil];
        if (!expected) { [self downloadFailed:@"模块校验信息不可用，下载未开始。请稍后重试。"] ; return; }
        [self beginDownload:expected];
    }];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler
{
    (void)session; (void)task; (void)response;
    completionHandler(MbsUpdateURLAllowed(request.URL) ? request : nil);
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
    didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten
    totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
    (void)session; (void)bytesWritten;
    int64_t expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : [self.candidate[@"size"] longLongValue];
    double percent = expected > 0 ? MIN(100.0,100.0*totalBytesWritten/expected) : 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (task != self.downloadTask || !self.downloading) return;
        self.progress.doubleValue = percent;
        self.statusLabel.stringValue = [NSString stringWithFormat:@"正在下载模块：%.0f%%",percent];
    });
}
- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)task
    didFinishDownloadingToURL:(NSURL *)location
{
    (void)session;
    self.downloadHandled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.progress.doubleValue = 100;
        self.statusLabel.stringValue = @"下载完成，正在校验模块…";
    });
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:location.path error:nil];
    BOOL valid = [response isKindOfClass:NSHTTPURLResponse.class] && response.statusCode == 200 &&
        MbsUpdateURLAllowed(response.URL) && [attributes[NSFileSize] longLongValue] == [self.candidate[@"size"] longLongValue] &&
        [MbsFileSha256(location) isEqualToString:self.expectedDigest];
    NSURL *destination = nil;
    NSError *saveError = nil;
    BOOL saved = NO;
    if (valid) {
        NSURL *base = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
            inDomains:NSUserDomainMask].firstObject;
        NSURL *directory = [base URLByAppendingPathComponent:[@"Mbs Office/Updates" stringByAppendingPathComponent:self.candidate[@"version"]]
            isDirectory:YES];
        if ([NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES
            attributes:nil error:&saveError]) {
            destination = [directory URLByAppendingPathComponent:self.candidate[@"name"]];
            if ([NSFileManager.defaultManager fileExistsAtPath:destination.path]) {
                NSURL *staging = [directory URLByAppendingPathComponent:[NSString stringWithFormat:@".module-%@.zip",NSUUID.UUID.UUIDString]];
                if ([NSFileManager.defaultManager copyItemAtURL:location toURL:staging error:&saveError]) {
                    saved = [NSFileManager.defaultManager replaceItemAtURL:destination withItemAtURL:staging
                        backupItemName:nil options:0 resultingItemURL:nil error:&saveError];
                    if (!saved) [NSFileManager.defaultManager removeItemAtURL:staging error:nil];
                }
            } else saved = [NSFileManager.defaultManager copyItemAtURL:location toURL:destination error:&saveError];
        }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!valid) { [self downloadFailed:@"模块下载未通过完整性校验，请重新检查更新。"] ; return; }
        if (saveError || !saved || !destination) { [self downloadFailed:@"模块已校验，但无法保存下载文件。请检查可用空间后重试。"] ; return; }
        self.downloadedURL = destination;
        self.progress.doubleValue = 100;
        self.statusLabel.stringValue = @"模块已下载并通过 SHA-256 校验，正在校验安装签名…";
        [self fetch:self.candidate[@"signatureURL"] completion:^(NSData *signatureData, NSInteger signatureStatus, NSError *signatureError) {
            NSString *expected = self.candidate[@"signatureDigest"];
            BOOL signatureOK = !signatureError && signatureStatus == 200 && MbsSignatureDataValid(signatureData) &&
                (!expected.length || [MbsDataSha256(signatureData) isEqualToString:expected]);
            if (!signatureOK) {
                [self downloadFailed:@"更新签名无效，未进行安装。请稍后重试。"];
                return;
            }
            NSURL *signatureURL = [destination URLByAppendingPathExtension:@"sig"];
            NSError *signatureSaveError = nil;
            BOOL signatureSaved = [signatureData writeToURL:signatureURL options:NSDataWritingAtomic error:&signatureSaveError];
            if (!signatureSaved || signatureSaveError) {
                [self downloadFailed:@"更新签名已校验，但无法保存安装文件。请检查可用空间后重试。"];
                return;
            }
            self.downloadedSignatureURL = signatureURL;
            self.downloading = NO;
            self.downloadTask = nil;
            [self startInstaller];
        }];
    });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    (void)session;
    if (task != self.downloadTask || self.downloadHandled || !error) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self downloadFailed:@"模块下载失败，请检查网络后重试。"];
    });
}
@end

static MbsUpdatesController *MbsUpdates(void)
{
    static MbsUpdatesController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[MbsUpdatesController alloc] init]; });
    return controller;
}
extern "C" void MbsShowUpdates(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        MbsUpdatesController *controller = MbsUpdates();
        [controller show];
        [controller start];
        [controller check:YES];
    });
}
extern "C" void MbsStartUpdateChecks(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{ [MbsUpdates() start]; });
}
