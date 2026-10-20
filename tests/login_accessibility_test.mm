#import "../src/MbsLoginAccessibility.mm"
static int shown, passed;
void MbsShowLoginForm(void) { ++shown; }
@interface ActionNode : NSObject
@property NSString *title;
@property BOOL enabled;
- (void)accessibilityPerformAction:(NSString *)action;
- (BOOL)accessibilityPerformPress;
@end
@implementation ActionNode
- (id)accessibilityAttributeValue:(NSString *)attribute {
    if ([attribute isEqual:NSAccessibilityRoleAttribute]) return NSAccessibilityButtonRole;
    if ([attribute isEqual:NSAccessibilityTitleAttribute]) return self.title;
    if ([attribute isEqual:NSAccessibilityEnabledAttribute]) return @(self.enabled);
    return nil;
}
- (void)accessibilityPerformAction:(NSString *)action { ++passed; }
- (BOOL)accessibilityPerformPress { ++passed; return YES; }
@end
int main() { @autoreleasepool {
    ActionNode *item = [ActionNode new]; item.title=@"立即登录"; item.enabled=YES;
    MbsRegisterLoginActions(ActionNode.class); MbsRegisterLoginActions(ActionNode.class);
    [item accessibilityPerformAction:NSAccessibilityPressAction];
    assert(shown==1 && passed==0);
    [item accessibilityPerformPress]; assert(shown==2 && passed==0);
    item.title=@"升级"; [item accessibilityPerformPress]; assert(shown==2 && passed==1);
    item.title=@"立即登录"; item.enabled=NO;
    [item accessibilityPerformAction:NSAccessibilityPressAction]; assert(shown==2 && passed==2);
    item.enabled=YES; [item accessibilityPerformAction:@"AXShowMenu"]; assert(shown==2 && passed==3);
    puts("PASS: legacy and modern login actions, exact target, disabled and other actions delegated");
} return 0; }
