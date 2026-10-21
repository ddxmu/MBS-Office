#import "../src/MbsAccountEntry.h"
static NSString *email;
static int forms,accounts;
const char *MbsCurrentAccountEmail(void) { return email.length ? strdup(email.UTF8String) : NULL; }
void MbsShowLoginForm(void) { ++forms; }
void MbsShowLocalAccount(void) { ++accounts; }
int main(void) { @autoreleasepool {
    assert([MbsAccountEntryTitle() isEqual:@"立即登录"]);
    MbsOpenAccountEntry(); assert(forms==1 && accounts==0);
    email=@"first.user@example.invalid";
    assert([MbsAccountEntryTitle() isEqual:@"first.user"]);
    assert(MbsIsAccountEntryText(@"first.user") && !MbsIsAccountEntryText(@"立即登录旁边"));
    MbsOpenAccountEntry(); assert(forms==1 && accounts==1);
    email=@"second.user@example.invalid";
    assert([MbsAccountEntryTitle() isEqual:@"second.user"]);
    assert(!MbsIsAccountEntryText(@"first.user"));
    email=nil;
    assert([MbsAccountEntryTitle() isEqual:@"立即登录"]);
    assert(!MbsIsAccountEntryText(@"second.user"));
    MbsOpenAccountEntry(); assert(forms==2 && accounts==1);
    puts("PASS account entry login, account switching, sign-out and click routing");
} }
