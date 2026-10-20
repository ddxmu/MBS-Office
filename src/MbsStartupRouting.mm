#import <AppKit/AppKit.h>
#import <objc/runtime.h>
static unsigned MbsStartupRoutes;
extern "C" unsigned MbsLegacyStartupPromptCount(void) {
    return __atomic_load_n(&MbsStartupRoutes,__ATOMIC_RELAXED);
}
static IMP MbsOriginalWindowOrder, MbsOriginalWindowTitle;
static IMP MbsOriginalMakeKey, MbsOriginalOrderFront, MbsOriginalFrontRegardless;
static BOOL MbsClosingLegacyWindow;
static BOOL MbsCloseLegacyWindow(NSWindow *window) {
    if (MbsClosingLegacyWindow || ![window.title isEqualToString:@"账号登录"]) return NO;
    MbsClosingLegacyWindow = YES;
    window.alphaValue = 0;
    [window performClose:nil];
    [window orderOut:nil];
    MbsClosingLegacyWindow = NO;
    __atomic_add_fetch(&MbsStartupRoutes,1,__ATOMIC_RELAXED);
    return YES;
}
static void MbsOrderWindow(NSWindow *window, SEL selector, NSWindowOrderingMode place, NSInteger relative) {
    if (place != NSWindowOut && MbsCloseLegacyWindow(window)) return;
    ((void (*)(id,SEL,NSWindowOrderingMode,NSInteger))MbsOriginalWindowOrder)(window,selector,place,relative);
}
static void MbsSetWindowTitle(NSWindow *window, SEL selector, NSString *title) {
    ((void (*)(id,SEL,id))MbsOriginalWindowTitle)(window,selector,title);
    if ([title isEqualToString:@"账号登录"]) {
        // The embedded web window may receive its title after being ordered.
        window.alphaValue = 0;
        dispatch_async(dispatch_get_main_queue(),^{ MbsCloseLegacyWindow(window); });
    }
}
static void MbsMakeKey(NSWindow *window, SEL selector, id sender) {
    if (!MbsCloseLegacyWindow(window)) ((void (*)(id,SEL,id))MbsOriginalMakeKey)(window,selector,sender);
}
static void MbsOrderFront(NSWindow *window, SEL selector, id sender) {
    if (!MbsCloseLegacyWindow(window)) ((void (*)(id,SEL,id))MbsOriginalOrderFront)(window,selector,sender);
}
static void MbsFrontRegardless(NSWindow *window, SEL selector) {
    if (!MbsCloseLegacyWindow(window)) ((void (*)(id,SEL))MbsOriginalFrontRegardless)(window,selector);
}
static IMP MbsReplaceWindowMethod(SEL selector, IMP implementation) {
    return method_setImplementation(class_getInstanceMethod(NSWindow.class,selector),implementation);
}
__attribute__((constructor)) static void MbsInstallStartupRouting(void) {
    MbsOriginalWindowOrder = MbsReplaceWindowMethod(@selector(orderWindow:relativeTo:),(IMP)MbsOrderWindow);
    MbsOriginalWindowTitle = MbsReplaceWindowMethod(@selector(setTitle:),(IMP)MbsSetWindowTitle);
    MbsOriginalMakeKey = MbsReplaceWindowMethod(@selector(makeKeyAndOrderFront:),(IMP)MbsMakeKey);
    MbsOriginalOrderFront = MbsReplaceWindowMethod(@selector(orderFront:),(IMP)MbsOrderFront);
    MbsOriginalFrontRegardless = MbsReplaceWindowMethod(@selector(orderFrontRegardless),(IMP)MbsFrontRegardless);
}
