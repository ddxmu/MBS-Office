#define MBS_STARTUP_ROUTING_TEST
#import "../src/MbsStartupRouting.mm"

static unsigned accountOpens;
extern "C" const char *MbsCurrentAccountEmail(void) { return strdup("preview@example.test"); }
extern "C" void MbsShowLocalAccount(void) { accountOpens++; }
extern "C" void MbsShowLoginForm(void) { accountOpens++; }

@interface StartupNode : NSObject
@property NSString *accessibilityRole, *accessibilityTitle;
@property NSArray *accessibilityChildren;
@property NSUInteger presses;
@end
@implementation StartupNode
- (void)accessibilityPerformAction:(NSString *)action {
    NSCAssert([action isEqual:NSAccessibilityPressAction], @"Must use the real Press action");
    self.presses++;
}
@end
@interface StartupWindow : StartupNode
@property NSString *title;
@property BOOL isVisible;
@property NSUInteger closes;
@end
@implementation StartupWindow
- (void)performClose:(id)sender { self.closes++; }
@end
@interface StartupNativeWindow : NSWindow
@property NSArray *nodes;
@end
@implementation StartupNativeWindow
- (NSArray *)accessibilityChildren { return self.nodes ?: @[]; }
@end
static StartupNode *node(NSString *role, NSString *title) {
    StartupNode *n = [StartupNode new]; n.accessibilityRole=role;
    n.accessibilityTitle=title; n.accessibilityChildren=@[]; return n;
}
int main(void) { @autoreleasepool {
    NSString *suite=[@"MbsStartupRoutingTest-" stringByAppendingString:NSUUID.UUID.UUIDString];
    MbsRecoveryPreferences=[[NSUserDefaults alloc] initWithSuiteName:suite];
    StartupWindow *window=[StartupWindow new]; window.title=@"账号登录"; window.isVisible=YES;
    StartupNode *later=node(NSAccessibilityButtonRole,@"稍后登录");
    StartupNode *status=node(NSAccessibilityStaticTextRole,@"请输入账号和密码");
    window.accessibilityChildren=@[status,later];
    assert(MbsRecoverFailedLogin((NSWindow *)window) && later.presses==1);
    status.accessibilityTitle=@"页面加载失败 错误码：-1003";
    assert(MbsRecoverFailedLogin((NSWindow *)window) && later.presses==2);
    assert(window.closes==0 && MbsLegacyStartupPromptCount()==2);
    window.title=@"文字文稿1";
    assert(!MbsRecoverFailedLogin((NSWindow *)window) && later.presses==2);
    window.title=@"账号登录"; window.isVisible=NO;
    assert(!MbsRecoverFailedLogin((NSWindow *)window));
    window.isVisible=YES; window.accessibilityChildren=@[status];
    assert(!MbsRecoverFailedLogin((NSWindow *)window) && window.closes==0);
    puts("PASS: exact obsolete login uses native Later completion before error; documents and hidden windows preserved; no raw close");
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSWindow *home=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1174,900)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    home.title=@"首页"; MbsInstallHomeRepairButton(home); MbsInstallHomeRepairButton(home);
    NSButton *repair=(NSButton *)[home.contentView viewWithTag:0x4d425352];
    assert(repair && repair.image && !repair.hidden && [repair.accessibilityLabel isEqual:@"一键修复启动回调"]);
    assert(repair.frame.origin.x==18 && repair.frame.size.width==32);
    NSButton *documents=(NSButton *)[home.contentView viewWithTag:0x4d425344];
    NSButton *service=(NSButton *)[home.contentView viewWithTag:0x4d425345];
    assert(documents && service && documents.transparent && service.transparent);
    assert([documents.accessibilityLabel isEqual:@"文档"] && documents.action==@selector(openDocument:));
    assert([service.accessibilityLabel isEqual:@"服务"] && service.action==@selector(openService:));
    assert(NSMaxY(documents.frame)==NSHeight(home.contentView.bounds)-98);
    [home.contentView setFrameSize:NSMakeSize(900,700)]; assert(repair.frame.origin.y==18);
    assert(NSMaxY(documents.frame)==NSHeight(home.contentView.bounds)-98);
    home.title=@"文字文稿1"; MbsInstallHomeRepairButton(home); assert(repair.hidden);
    assert(documents.hidden && service.hidden);
    home.title=@"首页"; MbsInstallHomeRepairButton(home); assert(!repair.hidden);
    puts("PASS: supplied refresh image embedded; home-only button stays bottom-left and is reused across tabs");
    MbsInstallQuietPresentation();
    StartupNativeWindow *legacy=[[StartupNativeWindow alloc] initWithContentRect:NSMakeRect(0,0,800,600)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    legacy.releasedWhenClosed=NO;
    legacy.nodes=@[status,later]; legacy.title=@"账号登录"; [legacy orderFront:nil];
    assert(legacy.isVisible && legacy.alphaValue==0);
    legacy.alphaValue=1; assert(legacy.alphaValue==0);
    [legacy makeKeyWindow]; assert(!legacy.isKeyWindow);
    assert(MbsRecoverFailedLogin(legacy) && later.presses==3 && legacy.isVisible);
    legacy.nodes=@[node(NSAccessibilityStaticTextRole,@"请输入账号和密码")];
    MbsApplyQuietPresentation(legacy); assert(legacy.alphaValue==0);
    legacy.title=@"Mbs Office 登录"; assert(!MbsIsQuietLegacyWindow(legacy) && legacy.alphaValue==1);
    [legacy close];
    StartupNativeWindow *toast=[[StartupNativeWindow alloc] initWithContentRect:NSMakeRect(0,0,520,70)
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    toast.releasedWhenClosed=NO; toast.alphaValue=0.8;
    toast.nodes=@[node(NSAccessibilityStaticTextRole,@"云服务连接异常，已开启离线特殊兼容")];
    [toast orderFront:nil]; assert(toast.isVisible && toast.alphaValue==0);
    toast.nodes=@[node(NSAccessibilityStaticTextRole,@"Mbs 网站暂时无法连接，请重试")];
    MbsApplyQuietPresentation(toast); assert(fabs(toast.alphaValue-0.8)<0.01);
    [toast close];
    assert(MbsLegacyQuietStartupKinds()==3);
    assert(home.alphaValue==1);
    puts("PASS: legacy loading/error and exact old cloud toast stay quiet before ordering; real callback still executes; working login, Mbs errors and reused-window alpha preserved");
    [MbsRecoveryPreferences removePersistentDomainForName:suite];
    MbsInitialStartupRecovery=NO;
    assert(MbsSavedRecoveryInterval()==10800);
    assert(MbsRecoveryInterval(1,0)==86400 && MbsRecoveryInterval(3,1)==10800 && MbsRecoveryInterval(15,2)==900);
    assert(!MbsRecoveryInterval(0,1) && !MbsRecoveryInterval(-1,1) && !MbsRecoveryInterval(1,3));
    NSDate *now=NSDate.date;
    assert(MbsAutomaticRecoveryDue(now));
    [MbsRecoveryDefaults() setObject:[now dateByAddingTimeInterval:-10799] forKey:MbsRecoveryLastKey];
    assert(!MbsAutomaticRecoveryDue(now));
    [MbsRecoveryDefaults() setObject:[now dateByAddingTimeInterval:-10800] forKey:MbsRecoveryLastKey];
    assert(MbsAutomaticRecoveryDue(now));
    window.accessibilityChildren=@[status,later]; window.isVisible=YES; window.title=@"账号登录";
    NSUInteger before=later.presses;
    assert(MbsRecoverAutomatically((NSWindow *)window));
    for (int i=0;i<30;++i) assert(!MbsRecoverAutomatically((NSWindow *)window));
    assert(later.presses==before+1);
    MbsConfigureAutomaticRecovery();
    assert(MbsAutomaticRecoveryTimer && CFRunLoopTimerGetInterval(MbsAutomaticRecoveryTimer)==10800);
    [MbsRecoveryDefaults() setBool:NO forKey:MbsRecoveryEnabledKey];
    MbsConfigureAutomaticRecovery(); assert(!MbsAutomaticRecoveryTimer);
    [MbsRecoveryDefaults() setObject:[now dateByAddingTimeInterval:-86400] forKey:MbsRecoveryLastKey];
    assert(!MbsRecoverAutomatically((NSWindow *)window));
    assert(MbsRecoverFailedLogin((NSWindow *)window) && later.presses==before+2);
    unsigned repairCount=MbsLegacyStartupPromptCount();
    NSUInteger completed=later.presses;
    MbsRunLegacyCompletion((NSWindow *)window);
    assert(later.presses==completed+1 && MbsLegacyStartupPromptCount()==repairCount);
    window.isVisible=NO; // End the simulated modal's follow-up check.
    [MbsRecoveryDefaults() setInteger:15 forKey:MbsRecoveryValueKey];
    [MbsRecoveryDefaults() setInteger:2 forKey:MbsRecoveryUnitKey];
    MbsRecoveryPreferences=[[NSUserDefaults alloc] initWithSuiteName:suite];
    assert(![MbsRecoveryDefaults() boolForKey:MbsRecoveryEnabledKey] && MbsSavedRecoveryInterval()==900);
    [MbsRecoveryDefaults() setBool:YES forKey:MbsRecoveryEnabledKey];
    assert(!MbsAutomaticRecoveryDue(NSDate.date));
    window.isVisible=YES;
    objc_setAssociatedObject(window,&MbsLegacyAccountRequested,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    assert(MbsRecoverFailedLogin((NSWindow *)window));
    MbsInitialStartupRecovery=YES;
    assert(MbsAutomaticRecoveryDue(NSDate.date));
    MbsConfigureAutomaticRecovery();
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.7,false);
    NSTimeInterval remaining=CFRunLoopTimerGetNextFireDate(MbsAutomaticRecoveryTimer)-CFAbsoluteTimeGetCurrent();
    assert(remaining>0 && remaining<=2 && accountOpens==1);
    window.isVisible=NO;
    [MbsRecoveryDefaults() setBool:NO forKey:MbsRecoveryEnabledKey];
    MbsConfigureAutomaticRecovery();
    assert(!MbsAutomaticRecoveryDue(NSDate.date) && !MbsAutomaticRecoveryTimer);
    [MbsRecoveryPreferences removePersistentDomainForName:suite];
    puts("PASS: default three-hour cooldown, all time units, event deduplication, disabled timer, manual bypass and saved preferences across reload");
} }
