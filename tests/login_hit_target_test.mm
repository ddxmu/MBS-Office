#import "../src/MbsNativeLoginRecovery.h"
#import "../src/MbsLoginHitTarget.h"
static NSString *signedInEmail;
const char *MbsCurrentAccountEmail(void) { return signedInEmail.length ? strdup(signedInEmail.UTF8String) : NULL; }
void MbsShowLoginForm(void) {}
void MbsShowLocalAccount(void) {}

@interface LoginNode : NSObject
@property NSString *accessibilityRole;
@property NSString *accessibilityTitle;
@property NSArray *accessibilityChildren;
@property NSRect accessibilityFrame;
@property(getter=isAccessibilityEnabled) BOOL accessibilityEnabled;
@end
@implementation LoginNode @end
@interface LegacyLoginNode : NSObject @end
@implementation LegacyLoginNode
- (id)accessibilityAttributeValue:(NSString *)attribute {
    if ([attribute isEqual:NSAccessibilityRoleAttribute]) return NSAccessibilityButtonRole;
    if ([attribute isEqual:NSAccessibilityTitleAttribute]) return @"立即登录";
    if ([attribute isEqual:NSAccessibilityPositionAttribute]) return [NSValue valueWithPoint:NSMakePoint(450,320)];
    if ([attribute isEqual:NSAccessibilitySizeAttribute]) return [NSValue valueWithSize:NSMakeSize(88,32)];
    return nil;
}
@end
static LoginNode *node(NSString *role, NSString *title, NSRect frame) {
    LoginNode *value = [LoginNode new]; value.accessibilityRole=role;
    value.accessibilityTitle=title; value.accessibilityFrame=frame; value.accessibilityEnabled=YES;
    return value;
}
int main() { @autoreleasepool {
    NSRect window = NSMakeRect(50,30,1000,700);
    LoginNode *root = node(NSAccessibilityWindowRole,@"首页",window);
    LoginNode *top = node(NSAccessibilityButtonRole,@"立即登录",NSMakeRect(850,650,120,24));
    LoginNode *center = node(NSAccessibilityButtonRole,@"立即登录",NSMakeRect(450,320,88,32));
    LoginNode *disabled = node(NSAccessibilityButtonRole,@"立即登录",NSMakeRect(200,320,88,32));
    disabled.accessibilityEnabled=NO;
    root.accessibilityChildren = @[top,center,disabled,
        node(NSAccessibilityStaticTextRole,@"立即登录",NSMakeRect(450,200,88,32)),
        node(NSAccessibilityButtonRole,@"登录后同步",NSMakeRect(450,160,88,32)),
        node(NSAccessibilityButtonRole,@"立即登录",NSMakeRect(200,200,600,170)),
        node(NSAccessibilityButtonRole,@"立即登录",NSMakeRect(-100,100,88,32))];
    NSArray<NSValue *> *frames = MbsLoginButtonFrames(root,window);
    assert(frames.count==2);
    BOOL centerHit=NO,topHit=NO,outsideHit=NO;
    for (NSValue *value in frames) {
        centerHit |= NSPointInRect(NSMakePoint(480,335),value.rectValue);
        topHit |= NSPointInRect(NSMakePoint(900,660),value.rectValue);
        outsideHit |= NSPointInRect(NSMakePoint(449,335),value.rectValue);
    }
    assert(centerHit && topHit && !outsideHit);
    NSArray<NSValue *> *headerFrames=MbsLoginButtonFrames(root,window,YES);
    assert(headerFrames.count==1 && NSEqualRects(headerFrames[0].rectValue,top.accessibilityFrame));
    signedInEmail=@"ui-check@example.invalid";
    top.accessibilityTitle=@"ui-check"; center.accessibilityTitle=@"ui-check";
    frames=MbsLoginButtonFrames(root,window);
    assert(frames.count==2);
    assert(MbsLoginButtonFrames(root,window,YES).count==1);
    signedInEmail=nil;
    frames=MbsLoginButtonFrames(root,window);
    assert(frames.count==0);
    root.accessibilityChildren = @[[LegacyLoginNode new]];
    frames = MbsLoginButtonFrames(root,window);
    assert(frames.count == 1 && NSPointInRect(NSMakePoint(480,335),frames[0].rectValue));
    puts("PASS: both real login buttons, exact bounds, disabled/text/large/outside targets rejected");
} return 0; }
