#import <Foundation/Foundation.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach-o/loader.h>
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
void MbsAccountLoginChanged(void *)
    __asm__("__ZN11kacctoutsdk16KAccountSdkProxy16loginInfoChangedEv");
void MbsAccountUserChanged(void *)
    __asm__("__ZN11kacctoutsdk16KAccountSdkProxy15userInfoChangedEv");
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
    MbsAccountLoginChanged(reference->_proxy);
    if (MbsAccountAlive(reference)) MbsAccountUserChanged(reference->_proxy);
    if (MbsAccountAlive(reference)) MbsAccountLicenseChanged(reference->_proxy);
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
void MbsRepublishNativeAccountState(void) {
    if (!NSThread.isMainThread) return;
    MbsNativeAccountPublished=NO;
    MbsScheduleNativeAccountState();
}
static bool MbsForceAccountLoggedIn(void *) { return MbsHasVerifiedEditorLicense(); }
#ifndef MBS_NATIVE_ACCOUNT_ROUTING_TEST
// A single version-verified interface represents the original force-login
// account. Its other 46 virtual methods and RTTI remain untouched. The
// replacement reads the signed Mbs grant on every query, including expiry.
static void *MbsForceAccountTable[49];
static bool MbsAccountRead(const void *address,void *out,size_t size) {
    mach_vm_size_t read=0;
    return address && mach_vm_read_overwrite(mach_task_self(),(mach_vm_address_t)address,size,
        (mach_vm_address_t)out,&read)==KERN_SUCCESS && read==size;
}
static bool MbsAccountImage(const Dl_info &image,NSString *relative,const unsigned char uuid[16]) {
    if (!image.dli_fbase || !image.dli_fname) return false;
    NSString *expected=[[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:relative] stringByStandardizingPath];
    if (![[NSString stringWithUTF8String:image.dli_fname].stringByStandardizingPath isEqual:expected]) return false;
    const auto *header=(const mach_header_64 *)image.dli_fbase;
    if (header->magic!=MH_MAGIC_64 || header->ncmds>512 || header->sizeofcmds>1024*1024) return false;
    const unsigned char *cursor=(const unsigned char *)(header+1),*end=cursor+header->sizeofcmds;
    for (uint32_t i=0;i<header->ncmds && cursor+sizeof(load_command)<=end;++i) {
        auto cmd=(const load_command *)cursor;
        if (cmd->cmdsize<sizeof(load_command) || cursor+cmd->cmdsize>end) return false;
        if (cmd->cmd==LC_UUID && cmd->cmdsize>=sizeof(uuid_command))
            return memcmp(((const uuid_command *)cmd)->uuid,uuid,16)==0;
        cursor+=cmd->cmdsize;
    }
    return false;
}
void MbsSyncForceLoginAccount(void) {
    if (!NSThread.isMainThread) return;
    auto self=(void **)dlsym(RTLD_DEFAULT,"_ZN6kso_qt16QCoreApplication4selfE");
    auto coreMeta=dlsym(RTLD_DEFAULT,"_ZN16KCoreApplication16staticMetaObjectE");
    auto accountMeta=dlsym(RTLD_DEFAULT,"_ZN11kacctoutsdk16KAccountSdkProxy16staticMetaObjectE");
    auto cast=(void *(*)(const void *,void *))dlsym(RTLD_DEFAULT,"_ZNK6kso_qt11QMetaObject4castEPNS_7QObjectE");
    auto accountGetter=(void *(*)(void *,const void *))dlsym(RTLD_DEFAULT,"_ZNK11kacctoutsdk16KAccountSdkProxy10getAccountERKN6kso_qt7QStringE");
    Dl_info coreImage={},getterImage={};
    const unsigned char coreUuid[]={0x68,0x24,0x8e,0xb9,0x21,0x52,0x3b,0x09,0xb8,0x6d,0x2f,0x14,0x65,0xb9,0x9b,0x17};
    const unsigned char sdkUuid[]={0xe7,0xf3,0x86,0x69,0xf5,0xc3,0x30,0x43,0xbd,0xec,0x94,0xb0,0x45,0xcd,0xbc,0x39};
    NSString *corePath=@"Contents/Frameworks/office6/ksolite.framework/Versions/A/ksolite";
    if (!self || !*self || !coreMeta || !accountMeta || !cast || !accountGetter ||
        !dladdr(coreMeta,&coreImage) || !dladdr((void *)accountGetter,&getterImage) ||
        coreImage.dli_fbase!=getterImage.dli_fbase || !MbsAccountImage(coreImage,corePath,coreUuid)) return;
    void *app=cast(coreMeta,*self),*core=nullptr,*proxy=nullptr;
    unsigned char initialized=0;
    if (!app || !MbsAccountRead((char *)app+0x18,&core,sizeof(core)) || !core ||
        !MbsAccountRead((char *)core+0x30,&proxy,sizeof(proxy)) || !proxy ||
        cast(accountMeta,proxy)!=proxy || !MbsAccountRead((char *)proxy+0x50,&initialized,1) || !initialized) return;
    static const struct { int ref,len; unsigned allocation,padding; intptr_t offset; char16_t chars[11]; }
        nameData={-1,10,0,0,24,u"forcelogin"};
    const void *name=&nameData;
    void *account=accountGetter(proxy,&name),**table=nullptr;
    if (!MbsAccountRead(account,&table,sizeof(table)) || !table) return;
    if (table==&MbsForceAccountTable[2]) { MbsCaptureNativeAccount(proxy); return; }
    void *method=nullptr; Dl_info tableImage={},methodImage={};
    if (!MbsAccountRead(table+11,&method,sizeof(method)) || !dladdr(table,&tableImage) ||
        !dladdr(method,&methodImage) || tableImage.dli_fbase!=methodImage.dli_fbase ||
        !MbsAccountImage(tableImage,@"Contents/Frameworks/office6/kaccountsdk.framework/Versions/A/kaccountsdk",sdkUuid) ||
        (uintptr_t)table-(uintptr_t)tableImage.dli_fbase!=0x2d3ed0 ||
        (uintptr_t)method-(uintptr_t)tableImage.dli_fbase!=0x5892c) return;
    static const unsigned char expected[]={0x00,0x40,0x00,0xd1,0xd4,0xff,0xff,0x17};
    unsigned char code[sizeof(expected)]; void *entries[49];
    if (!MbsAccountRead(method,code,sizeof(code)) || memcmp(code,expected,sizeof(code)) ||
        !MbsAccountRead(table-2,entries,sizeof(entries))) return;
    static BOOL prepared=NO;
    if (!prepared) {
        memcpy(MbsForceAccountTable,entries,sizeof(entries));
        MbsForceAccountTable[2+11]=reinterpret_cast<void *>(&MbsForceAccountLoggedIn);
        prepared=YES;
    }
    __atomic_store_n((void ***)account,&MbsForceAccountTable[2],__ATOMIC_RELEASE);
    MbsCaptureNativeAccount(proxy);
}
#endif

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
    if (action==1) {
        if (MbsHasVerifiedEditorLicense()) MbsScheduleNativeAccountState();
        else MbsShowLoginForm();
        return 1;
    }
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
