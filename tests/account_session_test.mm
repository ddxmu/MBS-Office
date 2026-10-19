#import <AppKit/AppKit.h>
static NSString *MbsTestHomeDirectory(void) { return [NSString stringWithUTF8String:getenv("MBS_TEST_HOME")]; }
#define NSHomeDirectory MbsTestHomeDirectory
#include "../src/MbsLocalAccount.mm"
#undef NSHomeDirectory
static void pump(BOOL (^done)(void)) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:35];
    while (!done() && end.timeIntervalSinceNow > 0) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    if (!done()) { fprintf(stderr,"timeout\n"); exit(2); }
}
int main(int argc, const char **argv) { @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSString *mode = @(argv[1]);
    NSDictionary *credentials = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(getenv("MBS_TEST_CREDENTIALS"))] options:0 error:nil];
    MbsLocalAccountController *c = [MbsLocalAccountController shared];
    if ([mode isEqual:@"restore"] || [mode isEqual:@"invalid-session"] || [mode isEqual:@"logout-restored"]) {
        if ([mode isEqual:@"invalid-session"]) MbsSaveSession(credentials[@"email"], @"invalid-session-000000000000000000000000");
        [c startSession];
        if (c.window.isVisible) return 11; // Saved sessions must validate without flashing the form.
        pump(^BOOL{ return !c.restoringSession; });
        if ([mode isEqual:@"restore"] || [mode isEqual:@"logout-restored"]) {
            if (![c.sessionEmail isEqual:credentials[@"email"]] || c.window.isVisible) return 3;
            if ([mode isEqual:@"logout-restored"]) {
                [c logout:nil];
                if (MbsLoadSession() || c.sessionEmail.length) return 10;
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
            }
        } else if (c.sessionEmail.length || MbsLoadSession() || ![c.status.stringValue containsString:@"过期"]) return 4;
    } else {
        [c show];
        if (c.remember.state != NSControlStateValueOn) return 12;
        c.email.stringValue = credentials[@"email"];
        c.password.stringValue = [mode isEqual:@"bad-password"] ? @"this-password-is-wrong" : credentials[@"password"];
        c.remember.state = [mode isEqual:@"no-remember"] ? NSControlStateValueOff : NSControlStateValueOn;
        [c submit:nil];
        pump(^BOOL{ return !c.session; });
        if ([mode isEqual:@"bad-password"]) {
            if (c.sessionEmail.length || !c.window.isVisible) return 5;
        } else {
            if (![c.sessionEmail isEqual:credentials[@"email"]] || c.window.isVisible || c.password.stringValue.length) return 6;
            NSDictionary *saved = MbsLoadSession();
            if ([mode isEqual:@"no-remember"]) { if (saved) return 7; }
            else if (![saved[@"token"] isEqual:c.sessionToken] || saved[@"password"]) return 8;
            if ([mode isEqual:@"logout"] || [mode isEqual:@"no-remember"]) {
                [c logout:nil];
                if (MbsLoadSession() || c.sessionEmail.length) return 9;
                [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
            }
        }
    }
    printf("PASS %s\n", argv[1]);
    return 0;
}}
