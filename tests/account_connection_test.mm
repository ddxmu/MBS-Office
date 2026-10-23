#import <AppKit/AppKit.h>
#import <objc/runtime.h>
static NSString *MbsTestHomeDirectory(void) { return @(getenv("MBS_TEST_HOME")); }
#define NSHomeDirectory MbsTestHomeDirectory
#include "../src/MbsLocalAccount.mm"
#undef NSHomeDirectory

static BOOL cachedGrant, offline;
static BOOL appActive = YES;
static NSInteger responseCode = 200, grantRequests, codeRequests;
static NSString *testEmail = @"ui-check@example.invalid";
static NSString *testToken = @"synthetic-test-session-token-000000000000";
bool MbsHasVerifiedEditorLicense(void) { return cachedGrant; }
bool MbsCanRestoreAccountSession(const char *token, const char *email) {
    return cachedGrant && token && email && [@(token) isEqual:testToken] && [@(email) isEqual:testEmail];
}
void MbsRequestEditorLicense(const char *token, const char *email) { ++grantRequests; }
void MbsRedeemActivationCode(const char *code) { ++codeRequests; }
void MbsResetEditorLicense(void) { cachedGrant = NO; }
char *MbsCopyEditorAuthorizationState(void) { return strdup("{}"); }

@interface AccountProtocol : NSURLProtocol @end
@implementation AccountProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"ttys.ddxmu.com"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    if (offline) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
        return;
    }
    NSDictionary *payload = responseCode == 200 ? @{@"ok":@YES,@"token":testToken,@"user":@{@"email":testEmail,@"plan":@"free"}} : @{@"ok":@NO,@"error":@"登录状态已过期"};
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:responseCode HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static void pump(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!done() && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(done());
}
int main(int argc, const char **argv) { @autoreleasepool {
    assert(argc == 2 && getenv("MBS_TEST_HOME"));
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    method_setImplementation(class_getInstanceMethod(NSApplication.class,@selector(isActive)),
        imp_implementationWithBlock(^BOOL(id receiver) { return appActive; }));
    Method method = class_getClassMethod(NSURLSessionConfiguration.class,@selector(ephemeralSessionConfiguration));
    IMP original = method_getImplementation(method);
    method_setImplementation(method,imp_implementationWithBlock(^NSURLSessionConfiguration *(id receiver) {
        NSURLSessionConfiguration *configuration = ((NSURLSessionConfiguration *(*)(id,SEL))original)(receiver,@selector(ephemeralSessionConfiguration));
        configuration.protocolClasses = @[AccountProtocol.class];
        return configuration;
    }));
    NSString *mode = @(argv[1]);
    MbsLocalAccountController *c = MbsLocalAccountController.shared;
    if ([mode isEqual:@"activation-status"]) {
        [c ensureAccountPopover];
        NSDictionary *activation = @{@"plan":@"standard",@"expiresAt":@1800000000};
        [c updateActivationState:@{@"verified":@YES,@"nativeAccepted":@YES,
            @"originalVendorLicense":@NO,@"status":@"授权码已激活",@"activation":activation}];
        assert([c.accountPanelAuthorization.stringValue containsString:@"Mbs 账号授权码已验证"]);
        assert([c.accountPanelAuthorization.stringValue containsString:@"编辑器许可未验证"]);
        assert(![c.accountPanelAuthorization.stringValue containsString:@"已激活"]);
        assert([c.activationSummary.stringValue containsString:@"Mbs 账号标准授权"]);
        [c updateActivationState:@{@"verified":@NO,@"status":@"登录已失效"}];
        assert([c.accountPanelAuthorization.stringValue isEqual:@"登录已失效"]);
        assert([c.activationSummary.stringValue containsString:@"输入新授权码激活"]);
        c.sessionEmail=testEmail; c.sessionToken=testToken;
        c.activationCode.stringValue=@"  "; [c redeemActivationCode:nil];
        assert(grantRequests==1 && codeRequests==0);
        c.activationCode.stringValue=@"MBS-test"; [c redeemActivationCode:nil];
        assert(grantRequests==1 && codeRequests==1);
        puts("PASS activation-status"); return 0;
    }
    if ([mode isEqual:@"login"] || [mode isEqual:@"signed-in-click"] || [mode isEqual:@"background-refresh"] || [mode isEqual:@"signed-in-login-form"]) {
        [c show]; c.email.stringValue = testEmail; c.password.stringValue = @"synthetic-password";
        [c submit:nil]; pump(^BOOL{ return !c.session; });
        assert([c.sessionEmail isEqual:testEmail] && !c.window.isVisible && !c.password.stringValue.length);
        assert(MbsLoadSession()[@"token"] && !MbsLoadSession()[@"password"]);
        assert(c.statusPanel.isVisible);
        if ([mode isEqual:@"signed-in-login-form"]) {
            [c showLoginForm];
            assert(c.window.isVisible && !c.accountPanel.isVisible && !c.statusPanel.isVisible);
            assert([c.email.stringValue isEqual:testEmail] && !c.password.stringValue.length && c.mode.selectedSegment == 0);
            [c deferLogin:nil];
            assert(!c.window.isVisible && [c.sessionEmail isEqual:testEmail]);
            puts("PASS signed-in-login-form"); return 0;
        }
        if ([mode isEqual:@"signed-in-click"] || [mode isEqual:@"background-refresh"]) {
            NSWindow *host = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,600)
                styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            [host makeKeyAndOrderFront:nil];
            [c show];
            assert(c.accountPanel.isVisible && !c.window.isVisible && !c.statusPanel.isVisible);
            assert([c.accountPanelEmail.stringValue isEqual:testEmail]);
            if ([mode isEqual:@"background-refresh"]) {
                appActive=NO;
                [NSNotificationCenter.defaultCenter postNotificationName:NSApplicationDidResignActiveNotification object:NSApp];
                [c showStatusPanel]; [c showAccountPopoverForWindow:host point:NSMakePoint(800,500)];
                assert(!c.accountPanel.isVisible && !c.statusPanel.isVisible);
                assert(c.window.level==NSNormalWindowLevel && c.accountPanel.level==NSNormalWindowLevel);
            }
            printf("PASS %s\n",argv[1]); return 0;
        }
        pump(^BOOL{ return !c.statusPanel.isVisible; });
    } else {
        MbsSaveSession(testEmail,testToken);
        offline = YES; cachedGrant = ![mode isEqual:@"no-cache"];
        if ([mode isEqual:@"background-expiry"]) appActive=NO;
        if ([mode isEqual:@"expired-session"] || [mode isEqual:@"revoked-session"] || [mode isEqual:@"background-expiry"]) {
            offline = NO; responseCode = [mode isEqual:@"revoked-session"] ? 403 : 401;
        }
        [c startSession];
        assert(!c.window.isVisible);
        pump(^BOOL{ return !c.restoringSession; });
        if ([mode isEqual:@"background-expiry"]) {
            assert(!c.window.isVisible && !MbsLoadSession());
            puts("PASS background-expiry"); return 0;
        }
        assert(c.window.isVisible && !c.sessionEmail.length);
        if ([mode isEqual:@"expired-session"] || [mode isEqual:@"revoked-session"]) {
            assert(!MbsLoadSession() && !c.deferredSession && c.retry.hidden && !cachedGrant);
        } else if ([mode isEqual:@"retry"]) {
            assert(!c.retry.hidden && c.webLogin.hidden);
            offline = NO; [c retryConnection:nil]; pump(^BOOL{ return !c.restoringSession; });
            assert([c.sessionEmail isEqual:testEmail] && !c.window.isVisible && !c.deferredSession);
        } else {
            if ([mode isEqual:@"expires-before-later"]) cachedGrant = NO;
            [c deferLogin:nil];
            BOOL permitted = [mode isEqual:@"cached"] || [mode isEqual:@"cached-then-revoked"];
            assert((c.sessionEmail.length > 0) == permitted);
            assert((grantRequests > 0) == permitted);
            if (permitted) {
                assert(!c.vip && c.membershipTimer && [c.membershipLabel containsString:@"待联网同步"]);
                offline = NO;
                if ([mode isEqual:@"cached-then-revoked"]) responseCode = 403;
                [c membershipTimerFired:nil]; pump(^BOOL{ return !c.membershipTask; });
                if (responseCode == 403) assert(!c.sessionEmail.length && !MbsLoadSession() && !cachedGrant);
                else assert([c.sessionEmail isEqual:testEmail] && !c.vip);
            }
        }
    }
    printf("PASS %s\n",argv[1]);
    return 0;
} }
