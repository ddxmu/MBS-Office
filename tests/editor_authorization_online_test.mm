#include "../src/MbsEditorAuthorization.mm"

static void pump(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:40];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    NSCAssert(done(),@"network timed out");
}
static NSDictionary *post(NSString *path, NSDictionary *body, NSString *token) {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[@"https://ttys.ddxmu.com/api/mbs/" stringByAppendingString:path]]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    if (token) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    __block BOOL done = NO; __block NSDictionary *payload;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error) {
        dispatch_async(dispatch_get_main_queue(),^{
            payload = !error && data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            done = YES;
        });
    }] resume];
    pump(^BOOL{ return done; }); [session finishTasksAndInvalidate]; return payload;
}
int main(int argc,const char **argv) { @autoreleasepool {
    NSCAssert(argc == 2,@"mode required");
    NSString *mode = @(argv[1]);
    if ([mode isEqual:@"fetch"]) {
        NSCAssert(!MbsHasVerifiedEditorLicense(),@"fresh profile must not be licensed");
        NSDictionary *credentials = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(getenv("MBS_TEST_CREDENTIALS"))] options:0 error:nil];
        NSDictionary *login = post(@"login",credentials,nil);
        NSCAssert([login[@"ok"] boolValue],@"QA login failed");
        NSString *token = login[@"token"], *email = login[@"user"][@"email"];
        NSData *saved = [NSJSONSerialization dataWithJSONObject:@{@"token":token,@"email":email} options:0 error:nil];
        NSCAssert(MbsWriteGrantFile("session.json",saved),@"save isolated session");
        MbsRequestEditorLicense(token.UTF8String,email.UTF8String);
        pump(^BOOL{ return !MbsEditorAuthorization.shared.task; });
        NSCAssert(MbsHasVerifiedEditorLicense(),@"server-signed grant must verify");
        NSDictionary *activation=MbsEditorAuthorization.shared.activation;
        NSCAssert([MbsEditorAuthorization.shared.activationState isEqual:@"active"] && [activation[@"plan"] isEqual:@"standard"],@"new account automatically activated");
        NSCAssert([activation[@"expiresAt"] doubleValue]-NSDate.date.timeIntervalSince1970>364*86400,@"full year activation");
        NSCAssert(MbsReadGrantFile("editor-license.json").length,@"signed grant persisted");
        NSCAssert(!MbsNativeAuthorizationStates().count,@"test executable cannot pretend to be native editor");
    } else if ([mode isEqual:@"restore"]) {
        NSCAssert(MbsHasVerifiedEditorLicense(),@"signed grant must restore before main");
    } else if ([mode isEqual:@"reject-cache"]) {
        NSCAssert(!MbsHasVerifiedEditorLicense(),@"changed device or signed cache must be rejected");
    } else if ([mode isEqual:@"logout"]) {
        NSDictionary *saved = [NSJSONSerialization JSONObjectWithData:MbsReadGrantFile("session.json") options:0 error:nil];
        MbsResetEditorLicense();
        NSCAssert(!MbsHasVerifiedEditorLicense() && !MbsReadGrantFile("editor-license.json"),@"logout clears grant");
        NSCAssert([post(@"logout",@{},saved[@"token"])[@"ok"] boolValue],@"revoke QA session");
        int dir = MbsGrantDirectory(); if (dir >= 0) { unlinkat(dir,"session.json",0); close(dir); }
    } else return 2;
    printf("PASS %s\n",argv[1]);
} return 0; }
