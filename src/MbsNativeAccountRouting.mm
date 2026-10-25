#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>
#import "MbsNativeAccountRouting.h"
#import "MbsLocalAccount.h"
#import "MbsEditorAuthorization.h"

// QtKso 5.12 QObject weak-reference layout, already used by dialog routing.
struct MbsAccountWeakData { int weak, strong; void *destroyer; };
MbsAccountWeakData *MbsAccountWeak(const void *)
    __asm__("__ZN6kso_qt15QtSharedPointer20ExternalRefCountData9getAndRefEPKNS_7QObjectE");
void MbsAccountWeakFree(void *) __asm__("__ZdlPv");
void MbsAccountVariantBool(void *,bool) __asm__("__ZN6kso_qt8QVariantC1Eb");
void MbsAccountLicenseChanged(void *)
    __asm__("__ZN11kacctoutsdk16KAccountSdkProxy18licenseInfoChangedEv");
void MbsAccountAuthChanged(void *)
    __asm__("__ZN11kacctoutsdk16KAccountSdkProxy15authInfoChangedEv");

@interface MbsNativeAccountReference : NSObject {
@public
    void *_proxy;
    MbsAccountWeakData *_weak;
}
@end
@implementation MbsNativeAccountReference
- (void)dealloc {
    if (_weak && __atomic_sub_fetch(&_weak->weak,1,__ATOMIC_ACQ_REL)==0)
        MbsAccountWeakFree(_weak);
}
@end

static MbsNativeAccountReference *MbsNativeAccount;
static BOOL MbsNativeAccountPending, MbsNativeAccountPublishing, MbsNativeAccountPublished;
static BOOL MbsNativeAccountLastEditing;
static NSString *MbsNativeAccountLastEmail;
static void MbsScheduleNativeAccountState(void);

static BOOL MbsAccountAlive(MbsNativeAccountReference *reference) {
    return reference && reference->_weak &&
        __atomic_load_n(&reference->_weak->strong,__ATOMIC_ACQUIRE)!=0;
}
static void MbsCaptureNativeAccount(void *proxy) {
    // The intercepted object is a borrowed KAccountSdkProxy. Never call the
    // application's getAccountSDK getter: it initializes the old SDK/network.
    if (!proxy || !NSThread.isMainThread) return;
    if (MbsAccountAlive(MbsNativeAccount) && MbsNativeAccount->_proxy==proxy) return;
    MbsNativeAccountReference *reference=[MbsNativeAccountReference new];
    reference->_proxy=proxy; reference->_weak=MbsAccountWeak(proxy);
    if (!reference->_weak) return;
    MbsNativeAccount=reference;
    MbsNativeAccountPublished=NO;
    // Deliver the current owned state after the native entry has returned,
    // including when the website lease was restored before this object existed.
    MbsScheduleNativeAccountState();
}
static void MbsPublishNativeAccountState(void) {
    if (!NSThread.isMainThread || MbsNativeAccountPublishing || !MbsAccountAlive(MbsNativeAccount)) return;
    BOOL editing=MbsHasVerifiedEditorLicense();
    const char *value=MbsCurrentAccountEmail();
    NSString *email=value ? [NSString stringWithUTF8String:value] : @"";
    free((void *)value);
    if (MbsNativeAccountPublished && MbsNativeAccountLastEditing==editing &&
        [MbsNativeAccountLastEmail isEqualToString:email]) return;
    MbsNativeAccountPublished=YES; MbsNativeAccountLastEditing=editing;
    MbsNativeAccountLastEmail=email;
    MbsNativeAccountPublishing=YES;
    MbsNativeAccountReference *reference=MbsNativeAccount;
    MbsAccountLicenseChanged(reference->_proxy);
    if (MbsAccountAlive(reference)) MbsAccountAuthChanged(reference->_proxy);
    MbsNativeAccountPublishing=NO;
}
static void MbsScheduleNativeAccountState(void) {
    void (^schedule)(void)=^{
        if (MbsNativeAccountPending) return;
        MbsNativeAccountPending=YES;
        dispatch_async(dispatch_get_main_queue(),^{
            MbsNativeAccountPending=NO; MbsPublishNativeAccountState();
        });
    };
    if (NSThread.isMainThread) schedule(); else dispatch_async(dispatch_get_main_queue(),schedule);
}
static BOOL MbsIsForceLoginQuery(const void *key) {
    if (!key) return NO;
    struct Data { int ref,length; unsigned allocation,padding; intptr_t offset; };
    const auto *data=*(const Data *const *)key;
    const char *expected="forbidEditInForceLogin";
    if (!data || data->length!=(int)strlen(expected)) return NO;
    const auto *text=(const uint16_t *)((const char *)data+data->offset);
    for (int i=0;i<data->length;++i) if (text[i]!=(unsigned char)expected[i]) return NO;
    return YES;
}
int MbsNativeAccountRoute(void *proxy,int action) {
    if (action<1 || action>4) return 0;
    MbsCaptureNativeAccount(proxy);
    if (action==1) { MbsShowLoginForm(); return 1; }
    if (action==2) { MbsLocalAccountSignOut(); return 1; }
    // The Mbs account controller alone restores its saved website session.
    return 0;
}
bool MbsNativeAccountQuery(void *proxy,const void *key,void *output) {
    if (!output || !MbsIsForceLoginQuery(key)) return false;
    MbsCaptureNativeAccount(proxy);
    MbsAccountVariantBool(output,!MbsHasVerifiedEditorLicense());
    return true;
}
static void MbsRegisterNativeAccountRouting(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        for (NSNotificationName name in @[@"MbsEditorAuthorizationDidChange",@"MbsLocalAccountDidChange"])
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                usingBlock:^(NSNotification *note) { MbsScheduleNativeAccountState(); }];
    });
}
#ifndef MBS_NATIVE_ACCOUNT_ROUTING_TEST
__attribute__((constructor)) static void MbsStartNativeAccountRouting(void) {
    @autoreleasepool { MbsRegisterNativeAccountRouting(); }
}
#endif
