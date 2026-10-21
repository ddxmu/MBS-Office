#define MBS_UI_ACTIONS_TEST
#include "../src/MbsUiActions.mm"
static NSString *email;
static int accountOpened;
const char *MbsCurrentAccountEmail(void) { return email.length ? strdup(email.UTF8String) : NULL; }
void MbsShowLoginForm(void) {}
void MbsShowLocalAccount(void) { ++accountOpened; }
void MbsShowUpdates(void) {}
void applicationCtor(void *,int &,char **,int,void *) __asm__("__ZN6kso_qt12QApplicationC1ERiPPciPNS_26QPlatformIntegrationConfigE");
void buttonCtor(void *,const kso_qt::QString &,void *) __asm__("__ZN6kso_qt11QPushButtonC1ERKNS_7QStringEPNS_7QWidgetE");
void labelCtor(void *,const kso_qt::QString &,void *,int) __asm__("__ZN6kso_qt6QLabelC1ERKNS_7QStringEPNS_7QWidgetENS_6QFlagsINS_2Qt10WindowTypeEEE");
void eventCtor(void *,int) __asm__("__ZN6kso_qt6QEventC1ENS0_4TypeE");
unsigned nativeColorRgba(const void *) __asm__("__ZNK6kso_qt6QColor4rgbaEv");

int main(int argc,char **argv) { @autoreleasepool {
    // Qt public widget objects contain private pointers; keep ample aligned
    // storage for the exact bundled Qt ABI, without relying on missing headers.
    applicationCtor(calloc(1,4096),argc,argv,0,nullptr);
    assert(MbsIsLegacyAccountPanel(@"KPromeAccountPanelWidget"));
    assert(MbsIsLegacyAccountPanel(@"KPromeAccountPanelKeletonWidgetV2"));
    assert(!MbsIsLegacyAccountPanel(@"MbsAccountPanel"));
    assert(!MbsIsLegacyAccountPanel(@"KPromeHeaderBar"));
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    auto *center=(kso_qt::QObject *)calloc(1,4096);
    auto *header=(kso_qt::QObject *)calloc(1,4096);
    auto *other=(kso_qt::QObject *)calloc(1,4096);
    buttonCtor(center,literal(@"立即登录"),nullptr);
    labelCtor(header,literal(@"立即登录"),nullptr,0);
    buttonCtor(other,literal(@"打开"),nullptr);
    assert(center->property("width").toInt()>0 && center->property("height").toInt()>0);
    MbsQtPoint origin=widgetMapToGlobal((kso_qt::QWidget *)center,{0,0});
    assert(abs(origin.x)<100000 && abs(origin.y)<100000);
    MbsRefreshAccountEntries();
    assert([property(center,"text") isEqual:@"立即登录"]);
    email=@"first.user@example.invalid";
    const int avatarStyle[]={1,0x08000f04},otherStyle[]={1,1};
    alignas(8) unsigned char blue[32],red[32]; nativeColorCtor(red,0xffff0000);
    const void *accountColor=MbsNativeAccountTextColor(avatarStyle,literal(@"first.user"),red,blue);
    assert(accountColor==blue && nativeColorRgba(accountColor)==0xff006ce7);
    assert(MbsNativeAccountTextColor(otherStyle,literal(@"first.user"),red,blue)==red);
    assert(MbsNativeAccountTextColor(avatarStyle,literal(@"普通正文"),red,blue)==red);
    assert(MbsNativeAccountTextColor(nullptr,literal(@"first.user"),red,blue)==red);
    MbsRefreshAccountEntries();
    assert([property(center,"text") isEqual:@"first.user"] && [property(header,"text") isEqual:@"first.user"]);
    assert([property(center,"toolTip") isEqual:email]);
    auto *documentHeader=(kso_qt::QObject *)calloc(1,4096);
    buttonCtor(documentHeader,literal(@"立即登录"),nullptr);
    assert([property(documentHeader,"text") isEqual:@"立即登录"]);
    auto *showEvent=(kso_qt::QEvent *)calloc(1,64);
    eventCtor(showEvent,17);
    routeClick(documentHeader,showEvent);
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    while (![property(documentHeader,"text") isEqual:@"first.user"] && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert([property(documentHeader,"text") isEqual:@"first.user"]);
    auto *clickEvent=(kso_qt::QEvent *)calloc(1,64); eventCtor(clickEvent,3);
    assert(routeClick(documentHeader,clickEvent) && accountOpened==1);
    auto *avatarChild=(kso_qt::QObject *)calloc(1,4096);
    labelCtor(avatarChild,literal(@"头像"),documentHeader,0);
    const unsigned short hoverTypes[]={5,10,127,129};
    for (unsigned short type : hoverTypes) {
        assert(MbsSuppressLegacyAccountHover(documentHeader,type));
        assert(MbsSuppressLegacyAccountHover(avatarChild,type));
        assert(!MbsSuppressLegacyAccountHover(other,type));
    }
    const unsigned short otherTypes[]={2,3,6,11,110,128};
    for (unsigned short type : otherTypes) assert(!MbsSuppressLegacyAccountHover(documentHeader,type));
    ((kso_qt::QAbstractButton *)other)->setText(literal(@"first.user"));
    assert(!MbsSuppressLegacyAccountHover(other,10));
    ((kso_qt::QAbstractButton *)other)->setText(literal(@"打开"));
    email=@"second.user@example.invalid";
    buttonText((kso_qt::QAbstractButton *)center,literal(@"立即登录"));
    labelText((kso_qt::QLabel *)header,literal(@"立即登录"));
    assert([property(center,"text") isEqual:@"second.user"] && [property(header,"text") isEqual:@"second.user"]);
    for (int count=0;count<100;++count) MbsRefreshAccountEntries();
    assert([property(center,"text") isEqual:@"second.user"] && [property(header,"text") isEqual:@"second.user"]);
    email=nil;
    MbsRefreshAccountEntries();
    assert([property(center,"text") isEqual:@"立即登录"] && [property(header,"text") isEqual:@"立即登录"]);
    assert([property(documentHeader,"text") isEqual:@"立即登录"]);
    assert([property(other,"text") isEqual:@"打开"]);
    puts("PASS actual bundled Qt buttons: delayed document toolbar, account hover and child hover suppressed, clicks/leave/tooltips/unrelated controls preserved, login/switch/sign-out synchronized");
} }
