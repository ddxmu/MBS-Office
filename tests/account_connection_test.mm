#import <AppKit/AppKit.h>
#import <objc/runtime.h>
static NSString *MbsTestHomeDirectory(void) { return @(getenv("MBS_TEST_HOME")); }
#define NSHomeDirectory MbsTestHomeDirectory
#include "../src/MbsLocalAccount.mm"
#undef NSHomeDirectory

static BOOL cachedGrant, offline;
static NSInteger responseCode = 200, grantRequests;
static NSString *testEmail = @"ui-check@example.invalid";
static NSString *testToken = @"synthetic-test-session-token-000000000000";
bool MbsHasVerifiedEditorLicense(void) { return cachedGrant; }
bool MbsCanRestoreAccountSession(const char *token, const char *email) {
    return cachedGrant && token && email && [@(token) isEqual:testToken] && [@(email) isEqual:testEmail];
}
void MbsRequestEditorLicense(const char *token, const char *email) { ++grantRequests; }
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
    Method method = class_getClassMethod(NSURLSessionConfiguration.class,@selector(ephemeralSessionConfiguration));
    IMP original = method_getImplementation(method);
    method_setImplementation(method,imp_implementationWithBlock(^NSURLSessionConfiguration *(id receiver) {
        NSURLSessionConfiguration *configuration = ((NSURLSessionConfiguration *(*)(id,SEL))original)(receiver,@selector(ephemeralSessionConfiguration));
        configuration.protocolClasses = @[AccountProtocol.class];
        return configuration;
    }));
    NSString *mode = @(argv[1]);
    MbsLocalAccountController *c = MbsLocalAccountController.shared;
    if ([mode isEqual:@"login"]) {
        [c show]; c.email.stringValue = testEmail; c.password.stringValue = @"synthetic-password";
        [c submit:nil]; pump(^BOOL{ return !c.session; });
        assert([c.sessionEmail isEqual:testEmail] && !c.window.isVisible && !c.password.stringValue.length);
        assert(MbsLoadSession()[@"token"] && !MbsLoadSession()[@"password"]);
        assert(c.statusPanel.isVisible);
        pump(^BOOL{ return !c.statusPanel.isVisible; });
    } else {
        MbsSaveSession(testEmail,testToken);
        offline = YES; cachedGrant = ![mode isEqual:@"no-cache"];
        if ([mode isEqual:@"expired-session"] || [mode isEqual:@"revoked-session"]) {
            offline = NO; responseCode = [mode isEqual:@"revoked-session"] ? 403 : 401;
        }
        [c startSession];
        assert(!c.window.isVisible);
        pump(^BOOL{ return !c.restoringSession; });
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
