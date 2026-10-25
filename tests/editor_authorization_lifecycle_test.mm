#define MBS_EDITOR_AUTH_TESTS 1
#include "../src/MbsEditorAuthorization.mm"

static NSDictionary *grant(NSString *state, double expiry) {
    NSMutableDictionary *claims = [@{@"activationState":state,@"expiresAt":@(expiry)} mutableCopy];
    if ([state isEqual:@"active"]) claims[@"activation"] = @{@"expiresAt":@(expiry),@"plan":@"standard"};
    return claims;
}
int main(void) { @autoreleasepool {
    assert(getenv("MBS_TEST_HOME"));
    MbsEditorAuthorization *value = MbsEditorAuthorization.shared;
    NSData *fixture = [@"synthetic verified-response fixture" dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *state in @[@"revoked",@"expired",@"device_limit"]) {
        [value acceptVerifiedGrant:grant(@"active",NSDate.date.timeIntervalSince1970+60) response:fixture];
        assert(MbsHasVerifiedEditorLicense());
        [value acceptVerifiedGrant:grant(state,NSDate.date.timeIntervalSince1970+60) response:fixture];
        assert(!MbsHasVerifiedEditorLicense() && [value.activationState isEqual:state]);
    }
    [value acceptVerifiedGrant:grant(@"active",NSDate.date.timeIntervalSince1970+0.1) response:fixture];
    [value notify];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (![value.activationState isEqual:@"expired"] && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(!MbsHasVerifiedEditorLicense() && [value.activationState isEqual:@"expired"]);
    assert([value.status containsString:@"已到期"]);

    [value acceptVerifiedGrant:grant(@"active",NSDate.date.timeIntervalSince1970+60) response:fixture];
    NSString *home = @(getenv("MBS_TEST_HOME"));
    // Prevent cache writes without relying on permission bits or root behavior.
    setenv("MBS_TEST_HOME","/dev/null",1);
    [value acceptVerifiedGrant:grant(@"revoked",NSDate.date.timeIntervalSince1970+60) response:fixture];
    assert(!MbsHasVerifiedEditorLicense() && [value.activationState isEqual:@"revoked"]);
    setenv("MBS_TEST_HOME",home.UTF8String,1);
    MbsResetEditorLicense();
    assert(!MbsHasVerifiedEditorLicense() && !MbsReadGrantFile("editor-license.json"));
    assert(!value.timer && !value.expiryTimer);
    puts("PASS: active, revoked, expired, device limit, timed expiry, failed persistence and logout");
} return 0; }
