#define MBS_LEGACY_DIALOG_TEST
#include "../src/MbsLegacyDialogRouting.mm"
#include <assert.h>

static unsigned completions;
extern "C" void MbsNoteNativeStartupCompletion(void) { completions++; }
void MbsTestQtApp(void *,int &,char **,int,void *) __asm__("__ZN6kso_qt12QApplicationC1ERiPPciPNS_26QPlatformIntegrationConfigE");
void MbsTestDialogCtor(void *,void *,int) __asm__("__ZN6kso_qt7QDialogC1EPNS_7QWidgetENS_6QFlagsINS_2Qt10WindowTypeEEE");
void MbsTestDialogDtor(void *) __asm__("__ZN6kso_qt7QDialogD1Ev");
void MbsTestSetTitle(void *,const MbsDialogString &) __asm__("__ZN6kso_qt7QWidget14setWindowTitleERKNS_7QStringE");
void MbsTestSetResult(void *,int) __asm__("__ZN6kso_qt7QDialog9setResultEi");
int MbsTestResult(const void *) __asm__("__ZNK6kso_qt7QDialog6resultEv");
static void *dialog(NSString *title) {
    void *value=calloc(1,4096); MbsTestDialogCtor(value,nullptr,0);
    struct Data { int ref,length; unsigned allocation,padding; long offset; };
    Data *data=(Data *)calloc(1,24+(title.length+1)*2);
    data->ref=-1;data->length=(int)title.length;data->offset=24;
    [title getCharacters:(unichar *)(data+1) range:NSMakeRange(0,title.length)];
    MbsDialogString text; text.data=data; MbsTestSetTitle(value,text);
    MbsTestSetResult(value,99); return value;
}
static void pump(NSTimeInterval seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,seconds,false);
}
int main(int argc,char **argv) { @autoreleasepool {
    MbsTestQtApp(calloc(1,4096),argc,argv,0,nullptr);
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    void *first=dialog(@"账号登录");
    MbsOldDialogVisible(first,true);
    pump(0.1); assert(MbsTestResult(first)==0 && completions==1);
    MbsTestDialogDtor(first);free(first);

    void *second=dialog(@"账号登录");
    MbsOldDialogVisible(second,true);
    pump(0.1);assert(MbsTestResult(second)==0 && completions==2);
    MbsTestDialogDtor(second);free(second);

    void *own=dialog(@"Mbs Office 账号");
    MbsOldDialogVisible(own,true);pump(0.1);
    assert(MbsTestResult(own)==99 && completions==2);
    MbsOldDialogVisible(own,false);MbsTestDialogDtor(own);free(own);

    void *deleted=dialog(@"账号登录");
    MbsOldDialogVisible(deleted,true);
    MbsTestDialogDtor(deleted);free(deleted);pump(1.1);
    assert(completions==2 && MbsLegacyDialogs.count==0);
    void *modal=dialog(@"账号登录");
    CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
    assert(MbsOldDialogExec(modal)==0 && completions==3);
    assert(CFAbsoluteTimeGetCurrent()-start<0.1);
    MbsTestDialogDtor(modal);free(modal);
    puts("PASS: old login never enters modal exec, all old dialogs finish without delay, Mbs account stays open, deleted Qt objects are safe");
} }
