#import "../src/MbsNativeLoginRecovery.h"

@interface LoginNode : NSObject
@property NSString *accessibilityRole, *accessibilityTitle, *accessibilityLabel;
@property NSArray *accessibilityChildren;
@end
@implementation LoginNode
@end

static LoginNode *node(NSString *role, NSString *title, NSArray *children) {
    LoginNode *value = [LoginNode new];
    value.accessibilityRole = role;
    value.accessibilityTitle = title;
    value.accessibilityChildren = children ?: @[];
    return value;
}

int main(void) { @autoreleasepool {
    LoginNode *later = node(NSAccessibilityButtonRole,@"稍后登录",nil);
    LoginNode *normal = node(NSAccessibilityWindowRole,@"账号登录",@[
        node(NSAccessibilityStaticTextRole,@"请输入账号和密码",nil),later]);
    NSCAssert(!MbsFailedNativeLoginAction(normal),@"A normal login must remain open");
    LoginNode *failed = node(NSAccessibilityWindowRole,@"账号登录",@[
        node(NSAccessibilityStaticTextRole,@"页面加载失败 错误码：-1003",nil),later]);
    NSCAssert(MbsFailedNativeLoginAction(failed) == later,@"Only the failed page's Later action is recoverable");
    LoginNode *noAction = node(NSAccessibilityWindowRole,@"账号登录",@[
        node(NSAccessibilityStaticTextRole,@"页面加载失败",nil)]);
    NSCAssert(!MbsFailedNativeLoginAction(noAction),@"Never invent a missing action");
    puts("PASS: normal login preserved; failed-page recovery requires its actual Later button");
} return 0; }
