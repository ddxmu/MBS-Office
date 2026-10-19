#import <AppKit/AppKit.h>
#import "MbsLocalAccount.h"

static NSString *MbsLoginURLString = @"https://ttys.ddxmu.com/api/mbs/login";
static NSString *MbsLogoutURLString = @"https://ttys.ddxmu.com/api/mbs/logout";
static NSString *MbsRegisterURLString = @"https://ttys.ddxmu.com/mbs/register";

static NSString *NormalizedEmail(NSString *email) {
    return [[email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
}

static BOOL ValidEmail(NSString *email) {
    if (!email.length || email.length > 254) return NO;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^[A-Z0-9.!#$%&'*+/=?^_{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [pattern numberOfMatchesInString:email options:0 range:NSMakeRange(0, email.length)] == 1;
}

static BOOL ValidPassword(NSString *password) {
    __block NSUInteger count = 0;
    [password enumerateSubstringsInRange:NSMakeRange(0, password.length)
                                 options:NSStringEnumerationByComposedCharacterSequences
                              usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if (++count >= 8) *stop = YES;
    }];
    return count >= 8 && password.length <= 256;
}

static BOOL IsMbsURL(NSURL *url) {
    return url && [url.scheme.lowercaseString isEqualToString:@"https"] &&
           [url.host.lowercaseString isEqualToString:@"ttys.ddxmu.com"];
}

@interface MbsRedirectGuard : NSObject <NSURLSessionTaskDelegate>
@end

@implementation MbsRedirectGuard
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(IsMbsURL(request.URL) ? request : nil);
}
@end

@interface MbsLocalAccountController : NSObject
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSSegmentedControl *mode;
@property(nonatomic, strong) NSTextField *email;
@property(nonatomic, strong) NSSecureTextField *password;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *submit;
@property(nonatomic, strong) NSButton *logout;
@property(nonatomic, copy) NSString *sessionEmail;
@property(nonatomic, copy) NSString *sessionToken;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) MbsRedirectGuard *redirectGuard;
+ (instancetype)shared;
- (void)show;
- (void)submit:(id)sender;
- (void)changeMode:(id)sender;
- (void)logout:(id)sender;
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
    });
    return controller;
}

- (void)show {
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 570, 440)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        self.window.title = @"Mbs Office 账号";
        self.window.releasedWhenClosed = NO;
        [self.window center];

        NSView *view = self.window.contentView;
        AccountLabel(view, @"使用 Mbs Office 账号登录，注册会打开 ttys.ddxmu.com 网页。", NSMakeRect(24, 396, 522, 24));
        AccountLabel(view, @"登录后可使用 Mbs Office 自研功能；文档编辑功能不依赖账号。", NSMakeRect(24, 350, 522, 42));

        self.mode = [NSSegmentedControl segmentedControlWithLabels:@[@"登录", @"注册"]
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self
                                                             action:@selector(changeMode:)];
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

        self.status = AccountLabel(view, @"未登录。登录只连接 Mbs Office 账号服务。", NSMakeRect(24, 75, 522, 87));

        self.submit = [NSButton buttonWithTitle:@"登录" target:self action:@selector(submit:)];
        self.submit.frame = NSMakeRect(422, 24, 124, 32);
        self.submit.bezelStyle = NSBezelStyleRounded;
        [view addSubview:self.submit];

        self.logout = [NSButton buttonWithTitle:@"退出登录" target:self action:@selector(logout:)];
        self.logout.frame = NSMakeRect(24, 24, 124, 32);
        self.logout.bezelStyle = NSBezelStyleRounded;
        self.logout.enabled = self.sessionEmail.length > 0;
        [view addSubview:self.logout];
        [self changeMode:nil];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)changeMode:(id)sender {
    BOOL registering = self.mode.selectedSegment == 1;
    self.submit.title = registering ? @"打开注册页面" : @"登录";
    self.status.stringValue = registering
        ? @"点击“打开注册页面”完成注册，注册后返回此窗口登录。"
        : (self.sessionEmail.length ? [NSString stringWithFormat:@"已登录：%@", self.sessionEmail] : @"未登录。登录只连接 Mbs Office 账号服务。");
}

- (void)setBusy:(BOOL)busy {
    self.submit.enabled = !busy;
    self.mode.enabled = !busy;
    self.email.enabled = !busy;
    self.password.enabled = !busy;
    self.logout.enabled = !busy && self.sessionEmail.length > 0;
}

- (void)submit:(id)sender {
    if (self.mode.selectedSegment == 1) {
        NSURL *url = [NSURL URLWithString:MbsRegisterURLString];
        if ([[NSWorkspace sharedWorkspace] openURL:url]) {
            self.status.stringValue = @"已打开注册页面。完成注册后返回这里输入邮箱和密码登录。";
        } else {
            self.status.stringValue = @"无法打开注册页面，请直接访问 ttys.ddxmu.com/mbs/register。";
        }
        return;
    }

    NSString *email = NormalizedEmail(self.email.stringValue);
    NSString *password = self.password.stringValue;
    if (!ValidEmail(email)) {
        self.status.stringValue = @"请输入有效的邮箱地址。";
        return;
    }
    if (!ValidPassword(password)) {
        self.status.stringValue = @"密码至少需要 8 个字符。";
        return;
    }

    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"email": email, @"password": password}
                                                   options:0
                                                     error:nil];
    if (!body) {
        self.status.stringValue = @"登录请求生成失败，请稍后重试。";
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MbsLoginURLString]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    self.password.stringValue = @"";
    [self setBusy:YES];
    self.status.stringValue = @"正在连接 Mbs Office 账号服务…";
    self.redirectGuard = [MbsRedirectGuard new];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 15.0;
    configuration.timeoutIntervalForResource = 30.0;
    self.session = [NSURLSession sessionWithConfiguration:configuration
                                                  delegate:self.redirectGuard
                                             delegateQueue:[NSOperationQueue mainQueue]];
    __weak MbsLocalAccountController *weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        MbsLocalAccountController *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *message = nil;
        NSString *token = nil;
        NSDictionary *user = nil;
        NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSURL *responseURL = response.URL;
        if (error) {
            message = @"无法连接账号服务，请检查网络后重试。";
        } else if (!IsMbsURL(responseURL)) {
            message = @"账号服务地址校验失败，登录未发送到指定服务。";
        } else {
            NSDictionary *payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *tokenString = [payload[@"token"] isKindOfClass:NSString.class] ? payload[@"token"] : nil;
            if (statusCode >= 200 && statusCode < 300 && [payload[@"ok"] boolValue] &&
                tokenString.length >= 32 &&
                [payload[@"user"][@"email"] isKindOfClass:NSString.class]) {
                token = tokenString;
                user = payload[@"user"];
            } else {
                message = [payload[@"error"] isKindOfClass:NSString.class] ? payload[@"error"] : @"邮箱或密码不正确。";
            }
        }
        if (token.length && user[@"email"]) {
            strongSelf.sessionToken = token;
            strongSelf.sessionEmail = user[@"email"];
            strongSelf.status.stringValue = [NSString stringWithFormat:@"已登录：%@", strongSelf.sessionEmail];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"MbsLocalAccountDidChange"
                                                                object:nil
                                                              userInfo:@{@"signedIn": @YES, @"email": strongSelf.sessionEmail}];
        } else {
            strongSelf.status.stringValue = message ?: @"登录失败，请稍后重试。";
        }
        [strongSelf setBusy:NO];
        [strongSelf.session finishTasksAndInvalidate];
        strongSelf.session = nil;
    }];
    [task resume];
}

- (void)logout:(id)sender {
    NSString *token = self.sessionToken;
    self.sessionToken = nil;
    self.sessionEmail = nil;
    self.password.stringValue = @"";
    self.status.stringValue = @"已退出登录。";
    self.logout.enabled = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MbsLocalAccountDidChange"
                                                        object:nil
                                                      userInfo:@{@"signedIn": @NO}];

    if (!token.length) return;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MbsLogoutURLString]];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate];
    }] resume];
}

@end

void MbsShowLocalAccount(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsLocalAccountController shared] show]; });
}

const char *MbsLocalAccountCapabilities(void) {
    return "{\"version\":2,\"localOnly\":false,\"session\":\"https_memory_token\",\"serverConnected\":true,\"serverBase\":\"https://ttys.ddxmu.com\",\"registration\":\"https://ttys.ddxmu.com/mbs/register\",\"accountRequired\":false,\"allMbsFeaturesAvailable\":true,\"changesWpsPaidEntitlements\":false}";
}

char *MbsCopyLocalAccountState(void) {
    __block NSData *data;
    void (^readState)(void) = ^{
        NSString *email = [MbsLocalAccountController shared].sessionEmail;
        NSDictionary *state = @{
            @"localOnly": @NO,
            @"serverConnected": @YES,
            @"signedIn": @(email.length > 0),
            @"email": email ?: @"",
            @"membershipRequired": @NO,
            @"allMbsFeaturesAvailable": @YES,
            @"vendorEntitlementsChanged": @NO
        };
        data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    };
    if (NSThread.isMainThread) readState(); else dispatch_sync(dispatch_get_main_queue(), readState);
    char *result = (char *)calloc(data.length + 1, 1);
    if (result && data.length) memcpy(result, data.bytes, data.length);
    return result;
}

void MbsLocalAccountSignOut(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsLocalAccountController shared] logout:nil]; });
}
