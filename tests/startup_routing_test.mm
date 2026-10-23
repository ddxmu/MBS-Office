#define MBS_STARTUP_ROUTING_TEST
#import "../src/MbsStartupRouting.mm"

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
    StartupWindow *window=[StartupWindow new]; window.title=@"账号登录"; window.isVisible=YES;
    StartupNode *later=node(NSAccessibilityButtonRole,@"稍后登录");
    StartupNode *status=node(NSAccessibilityStaticTextRole,@"请输入账号和密码");
    window.accessibilityChildren=@[status,later];
    assert(!MbsRecoverFailedLogin((NSWindow *)window) && later.presses==0);
    status.accessibilityTitle=@"页面加载失败 错误码：-1003";
    assert(MbsRecoverFailedLogin((NSWindow *)window) && later.presses==1);
    assert(window.closes==0 && MbsLegacyStartupPromptCount()==1);
    window.title=@"文字文稿1";
    assert(!MbsRecoverFailedLogin((NSWindow *)window) && later.presses==1);
    window.title=@"账号登录"; window.isVisible=NO;
    assert(!MbsRecoverFailedLogin((NSWindow *)window));
    window.isVisible=YES; window.accessibilityChildren=@[status];
    assert(!MbsRecoverFailedLogin((NSWindow *)window) && window.closes==0);
    puts("PASS: failed login uses native Later completion; normal login/documents/hidden windows preserved; no forced close");
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
    assert(MbsRecoverFailedLogin(legacy) && later.presses==2 && legacy.isVisible);
    legacy.nodes=@[node(NSAccessibilityStaticTextRole,@"请输入账号和密码")];
    objc_setAssociatedObject(legacy,&MbsLegacyLoadingSince,[NSDate dateWithTimeIntervalSinceNow:-11],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    MbsApplyQuietPresentation(legacy); assert(legacy.alphaValue==1);
    legacy.title=@"Mbs Office 登录"; assert(!MbsIsQuietLegacyWindow(legacy));
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
} }
