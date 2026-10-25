#import <Foundation/Foundation.h>
#import "MbsEditorAuthorization.h"
#import "MbsNativeAuthorizationState.h"
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <limits.h>
#include <math.h>
#include <string.h>

struct MbsAuthWeakData { int weak, strong; void *destroyer; };
struct MbsAuthQString { const void *data; };
struct MbsAuthQStringData { int ref, length; unsigned allocation, padding; intptr_t offset; };
static_assert(sizeof(MbsAuthQStringData)==24,"Bundled Qt string layout");
#define MBS_AUTH_TEXT(name, text) \
static const struct { MbsAuthQStringData header; char16_t chars[sizeof(u##text)/2]; } name##Data = \
    {{-1,(int)(sizeof(u##text)/2)-1,0,0,24},u##text}; \
static const MbsAuthQString name = {&name##Data.header}
MBS_AUTH_TEXT(MbsAuthInvalidText,"AuthType_Invalid");
MBS_AUTH_TEXT(MbsAuthFullText,"AuthType_FullFeatured");
MBS_AUTH_TEXT(MbsAuthPublicText,"Authority_Public");
MBS_AUTH_TEXT(MbsAuthInvalidAuthority,"Authority_Invalid");
MBS_AUTH_TEXT(MbsAuthCloudAccount,"Authority_CloudAccount");
MBS_AUTH_TEXT(MbsAuthCloudTrial,"Authority_CloudTrial");
MBS_AUTH_TEXT(MbsAuthCloudSN,"Authority_CloudSN");
MBS_AUTH_TEXT(MbsAuthCloudVIP,"Authority_CloudVipAccount");
MBS_AUTH_TEXT(MbsAuthGroup,"AuthInfo");
MBS_AUTH_TEXT(MbsAuthReadOnlyKey,"readOnlyMode");
MBS_AUTH_TEXT(MbsAuthTypeKey,"AuthType");
#undef MBS_AUTH_TEXT

#ifdef MBS_NATIVE_AUTH_STATE_TEST
bool MbsNativeAuthTestValid(void *);
MbsAuthWeakData *MbsNativeAuthTestWeak(void *);
void MbsNativeAuthTestWeakFree(void *);
void MbsNativeAuthTestLock(void *);
void MbsNativeAuthTestUnlock(void *);
void MbsNativeAuthTestAssign(void *,const MbsAuthQString &);
void *MbsNativeAuthTestHashSlot(void *,const MbsAuthQString &);
void MbsNativeAuthTestSettings(bool,int);
#else
MbsAuthWeakData *MbsAuthQtWeak(const void *) __asm__("__ZN6kso_qt15QtSharedPointer20ExternalRefCountData9getAndRefEPKNS_7QObjectE");
void MbsAuthQtDelete(void *) __asm__("__ZdlPv");
void MbsAuthQtLock(void *) __asm__("__ZN6kso_qt6QMutex4lockEv");
void MbsAuthQtUnlock(void *) __asm__("__ZN6kso_qt6QMutex6unlockEv");
void MbsAuthQtAssign(void *,const MbsAuthQString &) __asm__("__ZN6kso_qt7QStringaSERKS0_");
void MbsAuthSettingsCtor(void *,int) __asm__("__ZN3krt15KCommonSettingsC1EN6kso_qt9QSettings5ScopeE");
void MbsAuthSettingsDtor(void *) __asm__("__ZN3krt15KCommonSettingsD1Ev");
void MbsAuthBeginGroup(void *,const MbsAuthQString &) __asm__("__ZN6kso_qt9QSettings10beginGroupERKNS_7QStringE");
void MbsAuthEndGroup(void *) __asm__("__ZN6kso_qt9QSettings8endGroupEv");
void MbsAuthSetValue(void *,const MbsAuthQString &,const void *) __asm__("__ZN6kso_qt9QSettings8setValueERKNS_7QStringERKNS_8QVariantE");
void MbsAuthVariantBool(void *,bool) __asm__("__ZN6kso_qt8QVariantC1Eb");
void MbsAuthVariantInt(void *,int) __asm__("__ZN6kso_qt8QVariantC1Ei");
void MbsAuthVariantDtor(void *) __asm__("__ZN6kso_qt8QVariantD1Ev");
#endif

static bool MbsAuthRead(const void *address,void *out,size_t size) {
    mach_vm_size_t count=0;
    return address && mach_vm_read_overwrite(mach_task_self(),(mach_vm_address_t)address,size,
        (mach_vm_address_t)out,&count)==KERN_SUCCESS && count==size;
}
static NSString *MbsAuthReadString(const void *value) {
    const void *data=nullptr; MbsAuthQStringData header;
    if (!MbsAuthRead(value,&data,sizeof(data)) || !MbsAuthRead(data,&header,sizeof(header)) ||
        header.length<0 || header.length>128 || header.offset<24 || header.offset>1024*1024) return nil;
    unichar characters[128];
    if (header.length && !MbsAuthRead((const char *)data+header.offset,characters,header.length*2)) return nil;
    return [[NSString alloc] initWithCharacters:characters length:header.length];
}
static bool MbsAuthLocalAuthority(const void *authority) {
    if (!authority) return true;
    NSString *name=MbsAuthReadString(authority);
    return name && (!name.length || [name isEqualToString:@"Authority_Public"]);
}
static uintptr_t MbsAuthImage(void *manager) {
#ifdef MBS_NATIVE_AUTH_STATE_TEST
    return MbsNativeAuthTestValid(manager) ? 1 : 0;
#else
    static uintptr_t verifiedBase;
    const void *table=nullptr; Dl_info info;
    if (!MbsAuthRead(manager,&table,sizeof(table))) return 0;
    uintptr_t cached=__atomic_load_n(&verifiedBase,__ATOMIC_ACQUIRE);
    if (cached) return (uintptr_t)table==cached+0xf3608 ? cached : 0;
    if (!dladdr(table,&info)) return 0;
    NSString *path=[[NSString stringWithUTF8String:info.dli_fname] stringByStandardizingPath];
    NSString *expected=[[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
        @"Contents/Frameworks/office6/libauth.dylib"] stringByStandardizingPath];
    uintptr_t base=(uintptr_t)info.dli_fbase;
    if (![path isEqualToString:expected] || (uintptr_t)table!=base+0xf3608) return 0;
    __atomic_store_n(&verifiedBase,base,__ATOMIC_RELEASE);
    return base;
#endif
}
static void MbsAuthAssign(void *target,const MbsAuthQString &value) {
    if (*(const void **)target==value.data) return;
#ifdef MBS_NATIVE_AUTH_STATE_TEST
    MbsNativeAuthTestAssign(target,value);
#else
    MbsAuthQtAssign(target,value);
#endif
}
static void MbsAuthWriteSettings(bool active) {
#ifdef MBS_NATIVE_AUTH_STATE_TEST
    MbsNativeAuthTestSettings(!active,active ? 1 : 0);
#else
    // Exact bundled KCommonSettings/QVariant layouts, observed in CheckAuth.
    alignas(8) unsigned char settings[16],variant[16];
    MbsAuthSettingsCtor(settings,0); MbsAuthBeginGroup(settings,MbsAuthGroup);
    MbsAuthVariantBool(variant,!active); MbsAuthSetValue(settings,MbsAuthReadOnlyKey,variant);
    MbsAuthVariantDtor(variant);
    MbsAuthVariantInt(variant,active ? 1 : 0); MbsAuthSetValue(settings,MbsAuthTypeKey,variant);
    MbsAuthVariantDtor(variant);
    MbsAuthEndGroup(settings); MbsAuthSettingsDtor(settings);
#endif
}
static void *MbsAuthHashSlot(void *manager,const MbsAuthQString &authority,uintptr_t image) {
#ifdef MBS_NATIVE_AUTH_STATE_TEST
    return MbsNativeAuthTestHashSlot(manager,authority);
#else
    // The unmodified QString/QString QHash operator[] used by native setAuthStatus.
    static const unsigned char code[]={0xff,0x43,0x01,0xd1,0xf8,0x5f,0x01,0xa9,0xf6,0x57,0x02,0xa9,
        0xf4,0x4f,0x03,0xa9,0xfd,0x7b,0x04,0xa9};
    auto entry=(const unsigned char *)(image+0x26a24);
    if (memcmp(entry,code,sizeof(code))) return nullptr;
    return ((void *(*)(void *,const MbsAuthQString &))entry)((char *)manager+0x58,authority);
#endif
}

@interface MbsNativeAuthRegistration : NSObject {
@public void *_manager; MbsAuthWeakData *_weak;
}
@end
@implementation MbsNativeAuthRegistration
- (void)dealloc {
    if (_weak && __atomic_sub_fetch(&_weak->weak,1,__ATOMIC_ACQ_REL)==0) {
#ifdef MBS_NATIVE_AUTH_STATE_TEST
        MbsNativeAuthTestWeakFree(_weak);
#else
        MbsAuthQtDelete(_weak);
#endif
    }
}
@end
static NSMutableDictionary<NSValue *,MbsNativeAuthRegistration *> *MbsNativeAuthObjects;
static int MbsNativeSettingsActive=-1;
static int64_t MbsNativeActivationExpiry;
static uint64_t MbsNativeStateCalls, MbsNativeStateSyncs;
static void MbsAuthReadExpiry(void) {
    char *text=MbsCopyEditorAuthorizationState();
    NSDictionary *state=text ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:text length:strlen(text)] options:0 error:nil] : nil;
    free(text);
    id activation=[state[@"activation"] isKindOfClass:NSDictionary.class] ? state[@"activation"] : nil;
    double expiry=[activation[@"expiresAt"] doubleValue];
    __atomic_store_n(&MbsNativeActivationExpiry,isfinite(expiry) && expiry>0 && expiry<(double)INT64_MAX ? (int64_t)expiry : 0,__ATOMIC_RELEASE);
}
static void MbsAuthSyncObject(void *manager,uintptr_t image) {
    bool active=MbsHasVerifiedEditorLicense();
    void *mutex=(char *)manager+0x30;
#ifdef MBS_NATIVE_AUTH_STATE_TEST
    MbsNativeAuthTestLock(mutex);
#else
    MbsAuthQtLock(mutex);
#endif
    auto bytes=(unsigned char *)manager;
    bytes[97]=1; bytes[98]=!active; bytes[99]=1;
    *(unsigned *)(bytes+0x50)=active ? 1 : 0;
    MbsAuthAssign(bytes+0x40,active ? MbsAuthFullText : MbsAuthInvalidText);
    MbsAuthAssign(bytes+0x48,active ? MbsAuthPublicText : MbsAuthInvalidAuthority);
    const MbsAuthQString *authorities[]={&MbsAuthPublicText,&MbsAuthCloudAccount,&MbsAuthCloudTrial,&MbsAuthCloudSN,&MbsAuthCloudVIP};
    for (auto authority:authorities) {
        void *slot=MbsAuthHashSlot(manager,*authority,image);
        if (slot) MbsAuthAssign(slot,authority==&MbsAuthPublicText && active ? MbsAuthFullText : MbsAuthInvalidText);
    }
#ifdef MBS_NATIVE_AUTH_STATE_TEST
    MbsNativeAuthTestUnlock(mutex);
#else
    MbsAuthQtUnlock(mutex);
#endif
    if (MbsNativeSettingsActive!=(int)active) { MbsAuthWriteSettings(active); MbsNativeSettingsActive=active; }
}
static void MbsAuthRefreshRegistered(void) {
    if (!NSThread.isMainThread) return;
    MbsAuthReadExpiry();
    for (NSValue *key in MbsNativeAuthObjects.allKeys) {
        MbsNativeAuthRegistration *record=MbsNativeAuthObjects[key];
        if (!record->_weak || __atomic_load_n(&record->_weak->strong,__ATOMIC_ACQUIRE)==0) {
            [MbsNativeAuthObjects removeObjectForKey:key]; continue;
        }
        uintptr_t image=MbsAuthImage(record->_manager);
        if (image) MbsAuthSyncObject(record->_manager,image);
    }
}
static void MbsAuthInstallObserver(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        [NSNotificationCenter.defaultCenter addObserverForName:@"MbsEditorAuthorizationDidChange" object:nil queue:nil
            usingBlock:^(NSNotification *) {
                if (NSThread.isMainThread) MbsAuthRefreshRegistered();
                else dispatch_async(dispatch_get_main_queue(),^{ MbsAuthRefreshRegistered(); });
            }];
    });
}
static void MbsAuthRegister(void *manager) {
    if (!MbsNativeAuthObjects) MbsNativeAuthObjects=[NSMutableDictionary dictionary];
    NSValue *key=[NSValue valueWithPointer:manager];
    MbsNativeAuthRegistration *previous=MbsNativeAuthObjects[key];
    if (previous && previous->_weak && __atomic_load_n(&previous->_weak->strong,__ATOMIC_ACQUIRE)!=0) return;
    MbsNativeAuthRegistration *record=[MbsNativeAuthRegistration new]; record->_manager=manager;
#ifdef MBS_NATIVE_AUTH_STATE_TEST
    record->_weak=MbsNativeAuthTestWeak(manager);
#else
    record->_weak=MbsAuthQtWeak(manager);
#endif
    if (record->_weak) MbsNativeAuthObjects[key]=record;
}

extern "C" uint64_t MbsNativeAuthorizationDispatch(void *manager,unsigned operation,
    const void *arg1,const void *arg2,void *result) {
    __atomic_add_fetch(&MbsNativeStateCalls,1,__ATOMIC_RELAXED);
    uintptr_t image=MbsAuthImage(manager);
    bool active=image && MbsHasVerifiedEditorLicense();
    // Pure getters never take the manager mutex: native authList holds it while
    // invoking authStatus. Old setters/callbacks are routed only to Sync.
    if (operation==MbsNativeAuthSync) {
        if (!image || !NSThread.isMainThread) return 0;
        MbsAuthInstallObserver(); MbsAuthRegister(manager); MbsAuthReadExpiry();
        MbsAuthSyncObject(manager,image);
        __atomic_add_fetch(&MbsNativeStateSyncs,1,__ATOMIC_RELAXED); return 0;
    }
    if (operation==MbsNativeAuthStatus || operation==MbsNativeAuthAuthority || operation==MbsNativeAuthType) {
        const MbsAuthQString *value=&MbsAuthInvalidText;
        if (operation==MbsNativeAuthAuthority) value=active ? &MbsAuthPublicText : &MbsAuthInvalidAuthority;
        else if (active && (operation==MbsNativeAuthType || MbsAuthLocalAuthority(arg1))) value=&MbsAuthFullText;
        if (result) memcpy(result,&value->data,sizeof(value->data));
        return 0;
    }
    if (operation==MbsNativeAuthCheck || operation==MbsNativeAuthPaying) return active;
    if (operation==MbsNativeAuthFree || operation==MbsNativeAuthInvalid || operation==MbsNativeAuthVisitor) return !active;
    if (operation==MbsNativeAuthRemainingSecs || operation==MbsNativeAuthRemainingDays) {
        if (!active || (operation==MbsNativeAuthRemainingSecs && !MbsAuthLocalAuthority(arg1))) return 0;
        double remaining=__atomic_load_n(&MbsNativeActivationExpiry,__ATOMIC_ACQUIRE)-NSDate.date.timeIntervalSince1970;
        if (remaining<=0) return 0;
        return (uint64_t)MIN((double)INT_MAX,operation==MbsNativeAuthRemainingDays ? ceil(remaining/86400) : floor(remaining));
    }
    return 0;
}
extern "C" char *MbsCopyNativeAuthorizationDiagnostics(void) {
    if (!NSThread.isMainThread) return nullptr;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{
        @"dispatchCalls":@(__atomic_load_n(&MbsNativeStateCalls,__ATOMIC_RELAXED)),
        @"nativeSyncs":@(__atomic_load_n(&MbsNativeStateSyncs,__ATOMIC_RELAXED)),
        @"registeredManagers":@(MbsNativeAuthObjects.count),
        @"compatibilityStateInitialized":@(MbsNativeSettingsActive>=0),
        @"readOnly":@(MbsNativeSettingsActive!=1),
        @"websiteEditingAllowed":@(MbsHasVerifiedEditorLicense())} options:0 error:nil];
    return data ? strndup((const char *)data.bytes,data.length) : nullptr;
}
#ifndef MBS_NATIVE_AUTH_STATE_TEST
__attribute__((constructor)) static void MbsNativeAuthStart(void) {
    dispatch_async(dispatch_get_main_queue(),^{ MbsAuthInstallObserver(); });
}
#endif
