#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "MbsNativeLoginRecovery.h"
#import "MbsLocalAccount.h"
#import "MbsAccountEntry.h"

static NSMutableDictionary<NSString *,NSValue *> *MbsLoginActions;
static BOOL MbsIsLoginActionTarget(id item) {
    NSString *role = MbsNativeAccessibilityValue(item,NSAccessibilityRoleAttribute);
    if (!role && [item respondsToSelector:@selector(accessibilityRole)]) role = [item accessibilityRole];
    NSString *title = MbsNativeAccessibilityValue(item,NSAccessibilityTitleAttribute);
    if (!title.length && [item respondsToSelector:@selector(accessibilityTitle)]) title = [item accessibilityTitle];
    NSString *label = MbsNativeAccessibilityValue(item,NSAccessibilityDescriptionAttribute);
    if (!label.length && [item respondsToSelector:@selector(accessibilityLabel)]) label = [item accessibilityLabel];
    NSNumber *enabled = MbsNativeAccessibilityValue(item,NSAccessibilityEnabledAttribute);
    BOOL active = [enabled isKindOfClass:NSNumber.class] ? enabled.boolValue :
        (![item respondsToSelector:@selector(isAccessibilityEnabled)] || [item isAccessibilityEnabled]);
    return [role isEqualToString:NSAccessibilityButtonRole] && active &&
        (MbsIsAccountEntryText(title) || MbsIsAccountEntryText(label));
}
static NSString *MbsLoginActionKey(Class type, SEL selector) {
    return [NSStringFromClass(type) stringByAppendingFormat:@"/%@",NSStringFromSelector(selector)];
}
static IMP MbsOriginalLoginAction(id item, SEL selector) {
    for (Class type=object_getClass(item);type;type=class_getSuperclass(type)) {
        NSValue *value = MbsLoginActions[MbsLoginActionKey(type,selector)];
        if (value) return (IMP)value.pointerValue;
    }
    return NULL;
}
static void MbsPerformLoginAction(id item, SEL selector, NSString *action) {
    if ([action isEqualToString:NSAccessibilityPressAction] && MbsIsLoginActionTarget(item)) {
        MbsOpenAccountEntry(); return;
    }
    IMP original = MbsOriginalLoginAction(item,selector);
    if (original) ((void (*)(id,SEL,id))original)(item,selector,action);
}
static BOOL MbsPerformLoginPress(id item, SEL selector) {
    if (MbsIsLoginActionTarget(item)) { MbsOpenAccountEntry(); return YES; }
    IMP original = MbsOriginalLoginAction(item,selector);
    return original ? ((BOOL (*)(id,SEL))original)(item,selector) : NO;
}
static void MbsRegisterLoginActions(Class type) {
    if (!MbsLoginActions) MbsLoginActions = [NSMutableDictionary dictionary];
    SEL selectors[] = {@selector(accessibilityPerformAction:),@selector(accessibilityPerformPress)};
    IMP replacements[] = {(IMP)MbsPerformLoginAction,(IMP)MbsPerformLoginPress};
    for (NSUInteger index=0;index<2;++index) {
        NSString *key = MbsLoginActionKey(type,selectors[index]);
        if (MbsLoginActions[key]) continue;
        Method method = class_getInstanceMethod(type,selectors[index]);
        if (!method) continue;
        IMP original = method_getImplementation(method);
        if (original == replacements[index]) continue;
        MbsLoginActions[key] = [NSValue valueWithPointer:(const void *)original];
        if (!class_addMethod(type,selectors[index],replacements[index],method_getTypeEncoding(method)))
            method_setImplementation(class_getInstanceMethod(type,selectors[index]),replacements[index]);
    }
}
static void MbsFindLoginActions(NSWindow *window) {
    static BOOL finding;
    if (finding || !window.isVisible || !window.contentView) return;
    finding = YES;
    NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
    for (NSUInteger count=0;pending.count && count<256;++count) {
        id item = pending.lastObject; [pending removeLastObject];
        if (MbsIsLoginActionTarget(item)) MbsRegisterLoginActions(object_getClass(item));
        NSArray *children = MbsNativeAccessibilityValue(item,NSAccessibilityChildrenAttribute);
        if (!children.count && [item respondsToSelector:@selector(accessibilityChildren)]) children = [item accessibilityChildren];
        if ([children isKindOfClass:NSArray.class]) [pending addObjectsFromArray:children];
    }
    finding = NO;
}
__attribute__((constructor)) static void MbsInstallLoginActions(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        for (NSNotificationName name in @[NSWindowDidUpdateNotification,NSWindowDidBecomeKeyNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                MbsFindLoginActions(note.object);
            }];
        }
        for (NSWindow *window in NSApp.windows) MbsFindLoginActions(window);
    });
}
