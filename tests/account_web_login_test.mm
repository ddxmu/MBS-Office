#import <AppKit/AppKit.h>
static NSString *MbsTestHomeDirectory(void) { return [NSString stringWithUTF8String:getenv("MBS_TEST_HOME")]; }
#define NSHomeDirectory MbsTestHomeDirectory
#include "../src/MbsLocalAccount.mm"
#undef NSHomeDirectory

static void pump(BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:35];
    while (!done() && end.timeIntervalSinceNow > 0)
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if (!done()) { fprintf(stderr, "timeout\n"); exit(2); }
}

static NSDictionary *post(NSString *path, NSDictionary *body, NSString *token) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[@"https://ttys.ddxmu.com/api/mbs/" stringByAppendingString:path]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (token) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    __block BOOL done = NO;
    __block NSDictionary *payload;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            done = YES;
        });
    }] resume];
    pump(^BOOL{ return done; });
    [session finishTasksAndInvalidate];
    return payload;
}

@interface TestWebAccount : MbsLocalAccountController
@property(nonatomic) NSUInteger opens;
@property(nonatomic) BOOL refuseBrowser;
@end
@implementation TestWebAccount
- (BOOL)openWebLoginPage:(NSURL *)url {
    self.opens++;
    return !self.refuseBrowser && IsMbsURL(url) && [url.fragment hasPrefix:@"desktop_flow="];
}
@end

int main(int argc, const char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSDictionary *credentials = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(getenv("MBS_TEST_CREDENTIALS"))] options:0 error:nil];
    NSString *mode = @(argv[1]);
    TestWebAccount *c = [TestWebAccount new];
    [c show];
    c.remember.state = [mode isEqual:@"no-remember"] ? NSControlStateValueOff : NSControlStateValueOn;
    c.refuseBrowser = [mode isEqual:@"browser-failure"];
    [c openWebLogin:nil];
    pump(^BOOL{ return c.webFlow.length > 0 || !c.webSession; });
    if (c.opens != 1) return 3;
    if (c.refuseBrowser) {
        if (c.webSession || !c.window.isVisible || ![c.status.stringValue containsString:@"无法打开"]) return 4;
    } else if ([mode isEqual:@"expiry"]) {
        c.webDeadline = [NSDate dateWithTimeIntervalSinceNow:-1];
        [c pollWebLogin:nil];
        if (c.webSession || ![c.status.stringValue containsString:@"过期"]) return 5;
    } else {
        NSString *flow = c.webFlow;
        [c openWebLogin:nil];
        if (c.opens != 1) return 6;
        if ([mode isEqual:@"cancel"]) [c deferLogin:nil];
        NSDictionary *web = post(@"login", credentials, nil);
        if (![web[@"ok"] boolValue]) return 7;
        NSDictionary *linked = post(@"desktop/complete", @{@"flow": flow}, web[@"token"]);
        if (![linked[@"ok"] boolValue]) return 8;
        if ([mode isEqual:@"cancel"]) {
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
            if (c.sessionEmail.length || c.webSession || c.window.isVisible || MbsLoadSession()) return 9;
        } else {
            pump(^BOOL{ return c.sessionEmail.length > 0 || !c.webSession; });
            if (![c.sessionEmail isEqual:credentials[@"email"]] || c.window.isVisible || c.webSession) return 10;
            if ([mode isEqual:@"no-remember"]) {
                if (MbsLoadSession()) return 11;
                [c logout:nil];
            } else if (![MbsLoadSession()[@"token"] isEqual:c.sessionToken]) return 12;
        }
        post(@"logout", @{}, web[@"token"]);
    }
    [c cancelWebLogin];
    printf("PASS web %s\n", argv[1]);
    return 0;
}}
