#define MBS_NATIVE_AUTH_STATE_TEST 1
#include "../src/MbsNativeAuthorizationState.mm"
#include <map>
#include <string>

struct FakeManager {
    alignas(8) unsigned char bytes[104]={};
    MbsAuthWeakData *weak=new MbsAuthWeakData{2,-1,nullptr};
    std::map<std::string,const void *> authorities;
};
static std::map<void *,FakeManager *> objects;
static bool signedActive;
static double activationExpiry;
static int settingsWrites,lockDepth,releasedWeak;
static bool readOnly;
bool MbsHasVerifiedEditorLicense(void) { return signedActive; }
char *MbsCopyEditorAuthorizationState(void) {
    NSDictionary *state=@{@"activation":signedActive ? (id)@{@"expiresAt":@(activationExpiry)} : NSNull.null};
    NSData *data=[NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    return strndup((const char *)data.bytes,data.length);
}
bool MbsNativeAuthTestValid(void *manager) { return objects.count(manager)!=0; }
MbsAuthWeakData *MbsNativeAuthTestWeak(void *manager) { return objects.at(manager)->weak; }
void MbsNativeAuthTestWeakFree(void *pointer) { ++releasedWeak; delete (MbsAuthWeakData *)pointer; }
void MbsNativeAuthTestLock(void *) { assert(lockDepth++==0); }
void MbsNativeAuthTestUnlock(void *) { assert(--lockDepth==0); }
void MbsNativeAuthTestAssign(void *target,const MbsAuthQString &value) { assert(lockDepth==1); memcpy(target,&value.data,8); }
void *MbsNativeAuthTestHashSlot(void *manager,const MbsAuthQString &key) {
    return &objects.at(manager)->authorities[MbsAuthReadString(&key).UTF8String];
}
void MbsNativeAuthTestSettings(bool value,int type) {
    assert(lockDepth==0 && type==(value ? 0 : 1)); readOnly=value; ++settingsWrites;
}
static uint64_t call(FakeManager &manager,unsigned operation,const void *arg=nullptr,void *result=nullptr) {
    return MbsNativeAuthorizationDispatch(manager.bytes,operation,arg,nullptr,result);
}
static void notify(void) {
    [NSNotificationCenter.defaultCenter postNotificationName:@"MbsEditorAuthorizationDidChange" object:nil];
}
int main(void) { @autoreleasepool {
    unsigned char unreadable;
    assert(!MbsAuthRead((void *)1,&unreadable,1));
    FakeManager manager; objects[manager.bytes]=&manager;
    call(manager,MbsNativeAuthSync);
    assert(readOnly && settingsWrites==1);
    assert(manager.bytes[97]==1 && manager.bytes[98]==1 && manager.bytes[99]==1);
    assert(call(manager,MbsNativeAuthFree)==1 && call(manager,MbsNativeAuthCheck)==0);

    signedActive=true; activationExpiry=NSDate.date.timeIntervalSince1970+365*86400;
    notify();
    assert(!readOnly && settingsWrites==2 && manager.bytes[98]==0);
    assert(*(unsigned *)(manager.bytes+0x50)==1);
    MbsAuthQString result;
    call(manager,MbsNativeAuthStatus,nullptr,&result);
    assert([MbsAuthReadString(&result) isEqualToString:@"AuthType_FullFeatured"]);
    call(manager,MbsNativeAuthAuthority,nullptr,&result);
    assert([MbsAuthReadString(&result) isEqualToString:@"Authority_Public"]);
    call(manager,MbsNativeAuthStatus,&MbsAuthCloudVIP,&result);
    assert([MbsAuthReadString(&result) isEqualToString:@"AuthType_Invalid"]);
    auto cloud=manager.authorities.at("Authority_CloudVipAccount");
    assert([MbsAuthReadString(&cloud) isEqualToString:@"AuthType_Invalid"]);
    assert(call(manager,MbsNativeAuthRemainingSecs)>364*86400);
    assert(call(manager,MbsNativeAuthRemainingDays)==365);
    assert(call(manager,MbsNativeAuthRemainingSecs,&MbsAuthCloudSN)==0);
    assert(call(manager,MbsNativeAuthTrial)==0);

    // Native authList can invoke getters while already holding its mutex.
    lockDepth=1;
    assert(call(manager,MbsNativeAuthCheck)==1);
    call(manager,MbsNativeAuthStatus,nullptr,&result);
    assert(lockDepth==1); lockDepth=0;
    notify(); call(manager,MbsNativeAuthSync);
    assert(settingsWrites==2); // no repeating settings writes or polling timer
    MbsNativeAuthorizationDispatch(manager.bytes,MbsNativeAuthSync,&MbsAuthInvalidAuthority,&MbsAuthInvalidText,nullptr);
    assert(call(manager,MbsNativeAuthCheck)==1 && manager.bytes[98]==0 && settingsWrites==2);

    // A late old callback/setter cannot revive an invalid signed authorization.
    signedActive=false; notify();
    assert(readOnly && settingsWrites==3 && manager.bytes[98]==1);
    const void *oldValue=MbsAuthFullText.data;
    memcpy(manager.bytes+0x40,&oldValue,8); manager.bytes[98]=0;
    MbsNativeAuthorizationDispatch(manager.bytes,MbsNativeAuthSync,&MbsAuthCloudVIP,&MbsAuthFullText,nullptr);
    assert(manager.bytes[98]==1 && call(manager,MbsNativeAuthPaying)==0);
    assert([MbsAuthReadString(manager.bytes+0x40) isEqualToString:@"AuthType_Invalid"]);
    assert(call(manager,MbsNativeAuthRemainingSecs)==0);
    assert(!MbsNativeAuthorizationDispatch((void *)1,MbsNativeAuthCheck,nullptr,nullptr,nullptr));
    MbsNativeAuthorizationDispatch((void *)1,MbsNativeAuthStatus,nullptr,nullptr,&result);
    assert([MbsAuthReadString(&result) isEqualToString:@"AuthType_Invalid"]);

    signedActive=true; activationExpiry=NSDate.date.timeIntervalSince1970-1; notify();
    assert(call(manager,MbsNativeAuthRemainingSecs)==0);
    signedActive=false; notify();

    // A destroyed Qt object is pruned before its old raw pointer is inspected.
    manager.weak->strong=0; manager.weak->weak=1;
    objects.erase(manager.bytes); notify();
    assert(releasedWeak==1 && !MbsNativeAuthObjects.count && lockDepth==0);
    puts("PASS: owned live state, expiry, revocation, late callbacks, foreign authority rejection, pure getters and Qt weak lifetime");
} return 0; }
