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
    [home.contentView setFrameSize:NSMakeSize(900,700)]; assert(repair.frame.origin.y==18);
    home.title=@"文字文稿1"; MbsInstallHomeRepairButton(home); assert(repair.hidden);
    home.title=@"首页"; MbsInstallHomeRepairButton(home); assert(!repair.hidden);
    puts("PASS: supplied refresh image embedded; home-only button stays bottom-left and is reused across tabs");
} }
