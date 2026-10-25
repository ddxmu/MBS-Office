#import <AppKit/AppKit.h>
void MbsFreeQtWeak(void *) __asm__("__ZdlPv");

void MbsDialogStringFree(void *,size_t,size_t) __asm__("__ZN6kso_qt10QArrayData10deallocateEPS0_mm");
class MbsDialogString {
public:
    const void *data;
    ~MbsDialogString() {
        int *reference=(int *)data;
        if (!reference) return;
        int value=__atomic_load_n(reference,__ATOMIC_ACQUIRE);
        if (value!=-1 && (value==0 || __atomic_sub_fetch(reference,1,__ATOMIC_ACQ_REL)==0))
            MbsDialogStringFree(reference,2,8);
    }
};
MbsDialogString MbsDialogTitle(const void *) __asm__("__ZNK6kso_qt7QWidget11windowTitleEv");
void MbsDialogVisibleOriginal(void *, bool) __asm__("__ZN6kso_qt7QDialog10setVisibleEb");
int MbsDialogExecOriginal(void *) __asm__("__ZN6kso_qt7QDialog4execEv");
void MbsDialogReject(void *) __asm__("__ZN6kso_qt7QDialog6rejectEv");
struct MbsQtWeakData { int weak, strong; void *destroyer; };
MbsQtWeakData *MbsDialogWeak(const void *) __asm__("__ZN6kso_qt15QtSharedPointer20ExternalRefCountData9getAndRefEPKNS_7QObjectE");
extern "C" void MbsNoteNativeStartupCompletion(void);
extern const unsigned char MbsDialogMeta[] __asm__("__ZN6kso_qt7QDialog16staticMetaObjectE");
void *MbsDialogCast(const void *,void *) __asm__("__ZNK6kso_qt11QMetaObject4castEPNS_7QObjectE");

static NSMutableDictionary<NSValue *,id> *MbsLegacyDialogs;
static BOOL MbsFirstLegacyDialogScheduled;
static unsigned MbsLegacyDialogSchedules, MbsLegacyDialogFinishes;
static BOOL MbsIsOldQtLogin(void *dialog) {
    auto title=MbsDialogTitle(dialog);
    struct Data { int ref,length; unsigned allocation,padding; long offset; };
    const auto *data=(const Data *)title.data;
    if (!data || data->length!=4) return NO;
    NSString *text=[[NSString alloc] initWithCharacters:(const unichar *)((const char *)data+data->offset) length:4];
    return [text isEqualToString:@"账号登录"];
}

@interface MbsLegacyDialogDeadline : NSObject {
@public
    void *_dialog;
    MbsQtWeakData *_weak;
    CFRunLoopTimerRef _timer;
    CFAbsoluteTime _scheduledAt;
}
- (void)finish;
@end
@implementation MbsLegacyDialogDeadline
- (void)finish {
    if (_weak && __atomic_load_n(&_weak->strong,__ATOMIC_ACQUIRE)!=0 && MbsIsOldQtLogin(_dialog)) {
        // Use Qt's normal rejected/finished lifecycle; a Cocoa close skips it.
        MbsDialogReject(_dialog);
        MbsNoteNativeStartupCompletion();
        if (++MbsLegacyDialogFinishes<=2)
            NSLog(@"MbsStartupLegacyLogin finished=%u elapsed=%.3fs",MbsLegacyDialogFinishes,
                CFAbsoluteTimeGetCurrent()-_scheduledAt);
    }
    NSValue *key=[NSValue valueWithPointer:_dialog];
    if (MbsLegacyDialogs[key]==self) [MbsLegacyDialogs removeObjectForKey:key];
}
- (void)dealloc {
    if (_timer) { CFRunLoopTimerInvalidate(_timer); CFRelease(_timer); }
    if (_weak && __atomic_sub_fetch(&_weak->weak,1,__ATOMIC_ACQ_REL)==0) MbsFreeQtWeak(_weak);
}
@end

static void MbsScheduleQtLoginEnd(void *dialog) {
    if (!NSThread.isMainThread || !MbsDialogCast(MbsDialogMeta,dialog) || !MbsIsOldQtLogin(dialog)) return;
    if (!MbsLegacyDialogs) MbsLegacyDialogs=[NSMutableDictionary dictionary];
    NSValue *key=[NSValue valueWithPointer:dialog];
    MbsLegacyDialogDeadline *existing=MbsLegacyDialogs[key];
    if (existing && __atomic_load_n(&existing->_weak->strong,__ATOMIC_ACQUIRE)!=0) return;
    MbsLegacyDialogDeadline *deadline=[MbsLegacyDialogDeadline new];
    deadline->_dialog=dialog; deadline->_weak=MbsDialogWeak(dialog);
    if (!deadline->_weak) return;
    NSTimeInterval delay=MbsFirstLegacyDialogScheduled ? 0 : 1;
    MbsFirstLegacyDialogScheduled=YES;
    deadline->_scheduledAt=CFAbsoluteTimeGetCurrent();
    if (++MbsLegacyDialogSchedules<=2)
        NSLog(@"MbsStartupLegacyLogin scheduled=%u delay=%.1fs",MbsLegacyDialogSchedules,delay);
    __weak MbsLegacyDialogDeadline *weakDeadline=deadline;
    deadline->_timer=CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent()+delay,0,0,0,^(CFRunLoopTimerRef timer) { [weakDeadline finish]; });
    MbsLegacyDialogs[key]=deadline;
    CFRunLoopAddTimer(CFRunLoopGetMain(),deadline->_timer,kCFRunLoopCommonModes);
}
extern "C" void MbsScheduleNativeLegacyLogin(void *dialog) { MbsScheduleQtLoginEnd(dialog); }
static void MbsOldDialogVisible(void *dialog, bool visible) {
    MbsDialogVisibleOriginal(dialog,visible);
    if (visible) MbsScheduleQtLoginEnd(dialog);
    else [MbsLegacyDialogs removeObjectForKey:[NSValue valueWithPointer:dialog]];
}
static int MbsOldDialogExec(void *dialog) {
    MbsScheduleQtLoginEnd(dialog);
    int result=MbsDialogExecOriginal(dialog);
    [MbsLegacyDialogs removeObjectForKey:[NSValue valueWithPointer:dialog]];
    return result;
}
#ifndef MBS_LEGACY_DIALOG_TEST
struct MbsDialogInterpose { const void *replacement, *original; };
__attribute__((used,section("__DATA,__interpose"))) static const MbsDialogInterpose MbsDialogRoutes[]={
    {(const void *)&MbsOldDialogVisible,(const void *)&MbsDialogVisibleOriginal},
    {(const void *)&MbsOldDialogExec,(const void *)&MbsDialogExecOriginal}
};
#endif
