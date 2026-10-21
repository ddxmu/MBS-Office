#import "../src/MbsLoginAccessibility.mm"
static int shown, passed, accounts;
static NSString *signedInEmail;
void MbsShowLoginForm(void) { ++shown; }
void MbsShowLocalAccount(void) { ++accounts; }
const char *MbsCurrentAccountEmail(void) { return signedInEmail.length ? strdup(signedInEmail.UTF8String) : NULL; }
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
    signedInEmail=@"ui-check@example.invalid";
    item.title=@"ui-check";
    [item accessibilityPerformPress]; assert(accounts==1 && shown==2 && passed==3);
    item.title=@"立即登录";
    [item accessibilityPerformAction:NSAccessibilityPressAction]; assert(accounts==2 && shown==2);
    signedInEmail=nil;
    item.title=@"ui-check";
    [item accessibilityPerformPress]; assert(accounts==2 && shown==2 && passed==4);
    item.title=@"立即登录";
    [item accessibilityPerformPress]; assert(accounts==2 && shown==3);
    puts("PASS: legacy and modern login actions, exact target, disabled and other actions delegated");
} return 0; }
