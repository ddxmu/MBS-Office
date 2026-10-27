#define MBS_NATIVE_ACCOUNT_ROUTING_TEST 1
#include "../src/MbsNativeAccountRouting.mm"

static bool editing=true, killOnLicense;
static unsigned logins, logouts, licenseEvents, authEvents, userEvents;
static NSString *account=@"fixture@example.invalid";
static MbsAccountWeakData firstWeak={1,-1,nullptr}, secondWeak={1,-1,nullptr};
static int firstProxy, secondProxy;
MbsAccountWeakData *MbsAccountWeak(const void *object) {
    auto weak=object==&firstProxy ? &firstWeak : &secondWeak;
    ++weak->weak; return weak;
}
void MbsAccountVariantBool(void *output,bool value) {
    memset(output,0,16); ((unsigned char *)output)[0]=value;
    ((unsigned char *)output)[15]=0xA5;
}
void MbsAccountLicenseChanged(void *proxy) {
    assert(NSThread.isMainThread); ++licenseEvents;
    if (killOnLicense) (proxy==&firstProxy ? firstWeak : secondWeak).strong=0;
}
void MbsAccountLoginChanged(void *) {}
void MbsAccountUserChanged(void *) { assert(NSThread.isMainThread); ++userEvents; }
void MbsAccountAuthChanged(void *) { assert(NSThread.isMainThread); ++authEvents; }
bool MbsHasVerifiedEditorLicense(void) { return editing; }
const char *MbsCurrentAccountEmail(void) { return account ? strdup(account.UTF8String) : nullptr; }
void MbsShowLoginForm(void) { ++logins; }
void MbsLocalAccountSignOut(void) { ++logouts; editing=false; account=nil; }

struct StringData { int ref,length; unsigned allocation,padding; intptr_t offset; uint16_t text[64]; };
static void query(NSString *key,bool handled,bool expected) {
    StringData data={-1,(int)key.length,0,0,24,{}};
    [key getCharacters:data.text range:NSMakeRange(0,key.length)];
    const void *string=&data;
    unsigned char output[16]; memset(output,0xCC,sizeof(output));
    assert(MbsNativeAccountQuery(&firstProxy,&string,output)==handled);
    if (handled) assert(output[0]==expected && output[15]==0xA5);
    else assert(output[0]==0xCC && output[15]==0xCC);
}
static void pump(void) {
    NSDate *end=[NSDate dateWithTimeIntervalSinceNow:0.04];
    while (end.timeIntervalSinceNow>0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
}
int main(void) { @autoreleasepool {
    assert(MbsForceAccountLoggedIn(nullptr));
    editing=false; assert(!MbsForceAccountLoggedIn(nullptr)); editing=true;
    MbsRegisterNativeAccountRouting();
    assert(MbsNativeAccountRoute(&firstProxy,1)==1 && logins==0);
    editing=false; assert(MbsNativeAccountRoute(&firstProxy,1)==1 && logins==1); editing=true;
    assert(!MbsNativeAccountRoute(&firstProxy,3) && !MbsNativeAccountRoute(&firstProxy,4));
    query(@"forbidEditInForceLogin",true,false);
    editing=false; query(@"forbidEditInForceLogin",true,true);
    query(@"unrelatedCloudProperty",false,false);
    query(@"forbidEditInForceLoginExtra",false,false);
    [NSNotificationCenter.defaultCenter postNotificationName:@"MbsEditorAuthorizationDidChange" object:nil]; pump();
    assert(licenseEvents==1 && authEvents==1 && userEvents==1);
    [NSNotificationCenter.defaultCenter postNotificationName:@"MbsEditorAuthorizationDidChange" object:nil]; pump();
    assert(licenseEvents==1 && authEvents==1 && userEvents==1);
    editing=true;
    [NSNotificationCenter.defaultCenter postNotificationName:@"MbsEditorAuthorizationDidChange" object:nil]; pump();
    assert(licenseEvents==2 && authEvents==2);
    account=@"another@example.invalid";
    [NSNotificationCenter.defaultCenter postNotificationName:@"MbsLocalAccountDidChange" object:nil]; pump();
    assert(licenseEvents==3 && authEvents==3);
    [NSNotificationCenter.defaultCenter postNotificationName:@"LegacyTrialChanged" object:nil]; pump();
    assert(licenseEvents==3 && authEvents==3);
    assert(MbsNativeAccountRoute(&firstProxy,2)==1 && logouts==1 && !editing && !account);
    [NSNotificationCenter.defaultCenter postNotificationName:@"MbsLocalAccountDidChange" object:nil]; pump();
    assert(licenseEvents==4 && authEvents==4);
    editing=true;
    dispatch_semaphore_t posted=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"MbsEditorAuthorizationDidChange" object:nil];
        dispatch_semaphore_signal(posted);
    });
    assert(!dispatch_semaphore_wait(posted,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC)));
    pump(); assert(licenseEvents==5 && authEvents==5);
    firstWeak.strong=0;
    editing=false;
    [NSNotificationCenter.defaultCenter postNotificationName:@"MbsEditorAuthorizationDidChange" object:nil]; pump();
    assert(licenseEvents==5 && authEvents==5);
    MbsNativeAccountRoute(&secondProxy,3); killOnLicense=true;
    [NSNotificationCenter.defaultCenter postNotificationName:@"MbsEditorAuthorizationDidChange" object:nil]; pump();
    assert(licenseEvents==6 && authEvents==5);
    MbsNativeAccount=nil;
    assert(firstWeak.weak==1 && secondWeak.weak==1);
    puts("PASS: own login/logout, exact force-login query, old auto/SN login disabled, state-change coalescing and weak QObject lifetime");
} return 0; }
