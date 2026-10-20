#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "MbsLocalAccount.h"
#import "MbsUpdates.h"
#import "MbsNativeLoginRecovery.h"
#include <string.h>

namespace kso_qt {
class __attribute__((visibility("hidden"))) QString {
public: const void *data;
    explicit QString(const void *p):data(p){} ~QString(){}
    __attribute__((visibility("default"))) QString &operator=(const QString&);
};
class __attribute__((visibility("hidden"))) QVariant {
public: alignas(8) unsigned char data[16];
    __attribute__((visibility("default"))) ~QVariant();
    __attribute__((visibility("default"))) QString toString() const;
};
class QObject { public: QVariant property(const char*)const; };
class QEvent;
class QMetaObject { public: const char *className()const; };
class QCoreApplication { public: static bool notifyInternal2(QObject*,QEvent*); };
class QLabel { public: void setText(const QString&); };
class QAbstractButton { public: void setText(const QString&); };
class QMouseEvent;
}
class KLiteClickableLabel;
class KPromeHeaderAvatar;
class KPromeHeaderAuthTip;
class KAppEntryWidget;
void labelSetText(void*,const kso_qt::QString&) __asm__("__ZN6kso_qt6QLabel7setTextERKNS_7QStringE");
void buttonSetText(void*,const kso_qt::QString&) __asm__("__ZN6kso_qt15QAbstractButton7setTextERKNS_7QStringE");
void buttonMouseReleaseOriginal(kso_qt::QAbstractButton*,kso_qt::QMouseEvent*) __asm__("__ZN6kso_qt15QAbstractButton17mouseReleaseEventEPNS_11QMouseEventE");
void clickableLabelMouseReleaseOriginal(void*,kso_qt::QMouseEvent*) __asm__("__ZN19KLiteClickableLabel17mouseReleaseEventEPN6kso_qt11QMouseEventE");
void headerAvatarMouseReleaseOriginal(void*,kso_qt::QMouseEvent*) __asm__("__ZN18KPromeHeaderAvatar17mouseReleaseEventEPN6kso_qt11QMouseEventE");
void headerAuthTipMouseReleaseOriginal(void*,kso_qt::QMouseEvent*) __asm__("__ZN19KPromeHeaderAuthTip17mouseReleaseEventEPN6kso_qt11QMouseEventE");
void appEntryMouseReleaseOriginal(void*,kso_qt::QMouseEvent*) __asm__("__ZN15KAppEntryWidget17mouseReleaseEventEPN6kso_qt11QMouseEventE");
void unloginedButtonClickOriginal(void*) __asm__("__ZN18KPromeHeaderAvatar22onUnloginedButtonClickEv");
void promeGuideLoginOriginal(void*) __asm__("__ZN12KxMainWindow17onPromeGuideLoginEv");
void headerAvatarClickedOriginal(void*,const kso_qt::QString&) __asm__("__ZN18KPromeHeaderAvatar7clickedERKN6kso_qt7QStringE");
void headerAvatarPointClickedOriginal(void*,const void*,const kso_qt::QString&) __asm__("__ZN18KPromeHeaderAvatar7clickedERKN6kso_qt6QPointERKNS0_7QStringE");
void headAvatarClickedOriginal(void*,const kso_qt::QString&) __asm__("__ZN18KPromeHeaderAvatar19onHeadAvatarClickedERKN6kso_qt7QStringE");
bool desktopOpenUrlOriginal(const void*) __asm__("__ZN6kso_qt16QDesktopServices7openUrlERKNS_4QUrlE");
kso_qt::QString qurlPathOriginal(const void*,int) __asm__("__ZNK6kso_qt4QUrl4pathENS_6QFlagsINS0_25ComponentFormattingOptionEEE");
kso_qt::QString qurlHostOriginal(const void*,int) __asm__("__ZNK6kso_qt4QUrl4hostENS_6QFlagsINS0_25ComponentFormattingOptionEEE");
struct Data { int ref,len;unsigned allocation,padding;long offset; };
static const struct { Data h; unsigned short text[1]; } empty={{-1,0,0,0,24},{0}};
static NSString *read(const kso_qt::QString &value) {
    const auto *d=(const Data*)value.data;
    if(!d||d->len<0)return @"";
    return [[NSString alloc] initWithCharacters:(const unichar*)((const char*)d+d->offset) length:d->len];
}
static kso_qt::QString literal(NSString *value) {
    static NSMutableDictionary<NSString*,NSValue*>*cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSMutableDictionary dictionary];});
    @synchronized(cache) {
        if(!cache[value]) {auto*d=(Data*)calloc(1,24+(value.length+1)*2);d->ref=-1;d->len=(int)value.length;d->offset=24;
            [value getCharacters:(unichar*)(d+1) range:NSMakeRange(0,value.length)];cache[value]=[NSValue valueWithPointer:d];}
        return kso_qt::QString(cache[value].pointerValue);
    }
}
static NSString *MbsAccountInitialForEmail(NSString *email) {
    NSString *local = [[email componentsSeparatedByString:@"@"] firstObject];
    if (!local.length) local = email;
    if (!local.length) return @"";
    NSRange first = [local rangeOfComposedCharacterSequenceAtIndex:0];
    return [[local substringWithRange:first] uppercaseString];
}
static BOOL isRemovedAssistantText(NSString *text) {
    return [text containsString:@"灵犀"] || [text containsString:@"超级派"];
}
static NSString *updated(NSString *text) {
    if (isRemovedAssistantText(text)) return @"";
    NSString *result = [text stringByReplacingOccurrencesOfString:@"免费使用企业版" withString:@"版本升级"];
    return result;
}
static BOOL isUpgradeText(NSString *text) {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [value isEqualToString:@"升级"] || [value isEqualToString:@"版本升级"];
}
static BOOL isBlockedRemoteHost(NSString *host) {
    return [host isEqualToString:@"personal.local.wps.cn"] ||
           [host isEqualToString:@"personal.local.wps.com"] ||
           [host isEqualToString:@"personal.local.wps365.com"];
}
static BOOL isLegacyAssistantHost(NSString *host) {
    return [host isEqualToString:@"lingxi.kdocs.cn"] ||
           [host isEqualToString:@"lingxi.wps.cn"];
}
static BOOL isLegacyUpgradeHost(NSString *host) {
    return [host isEqualToString:@"plus.wps.cn"];
}
static BOOL isLegacyLoginURL(NSURL *url) {
    return [url.host.lowercaseString isEqualToString:@"account.wps.cn"] &&
           [url.path isEqualToString:@"/wpsmaclogin"];
}
static IMP MbsWorkspaceOpenURLOriginal;
static BOOL MbsWorkspaceOpenURL(id self, SEL selector, NSURL *url) {
    NSString *host = url.host.lowercaseString;
    if (isLegacyLoginURL(url)) {
        // Background SDK navigation is not a request to open the browser.
        // Only the Mbs form's explicit web-login button opens our login page.
        return YES;
    }
    if (isLegacyAssistantHost(host)) return YES;
    if (isLegacyUpgradeHost(host)) {
        MbsShowUpdates();
        return YES;
    }
    if (isBlockedRemoteHost(host)) return YES;
    if (!MbsWorkspaceOpenURLOriginal) return NO;
    return ((BOOL (*)(id, SEL, NSURL *))MbsWorkspaceOpenURLOriginal)(self, selector, url);
}
static void InstallMbsWorkspaceURLHook(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method method = class_getInstanceMethod([NSWorkspace class], @selector(openURL:));
        if (method) {
            MbsWorkspaceOpenURLOriginal = method_getImplementation(method);
            method_setImplementation(method, (IMP)MbsWorkspaceOpenURL);
        }
    });
}
static BOOL MbsAccountSignedIn = NO;
static NSPanel *MbsAccountBadgePanel;
static NSTextField *MbsAccountBadgeLabel;
static id MbsNativeAccessibilityValue(id item,NSString *attribute);
static NSRect MbsAccountControlFrame(NSWindow *window) {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:window];
    for (NSUInteger inspected=0;pending.count && inspected<256;++inspected) {
        id<NSAccessibility> item = pending.lastObject;
        [pending removeLastObject];
        NSString *role = [item respondsToSelector:@selector(accessibilityRole)] ? item.accessibilityRole : nil;
        NSString *title = [item respondsToSelector:@selector(accessibilityTitle)] ? item.accessibilityTitle : nil;
        NSString *label = [item respondsToSelector:@selector(accessibilityLabel)] ? item.accessibilityLabel : nil;
        if ([role isEqualToString:NSAccessibilityButtonRole] &&
            ([title isEqualToString:@"立即登录"] || [label isEqualToString:@"立即登录"]) &&
            [item respondsToSelector:@selector(accessibilityFrame)]) {
            NSRect frame = item.accessibilityFrame;
            if (frame.size.width >= 20 && frame.size.width < 200 &&
                frame.size.height >= 12 && frame.size.height < 60) return frame;
        }
        NSArray *children = [item respondsToSelector:@selector(accessibilityChildren)] ? item.accessibilityChildren : nil;
        if (!children.count) children = MbsNativeAccessibilityValue(item,NSAccessibilityChildrenAttribute);
        if ([children isKindOfClass:NSArray.class]) [pending addObjectsFromArray:children];
    }
    // The document title bar is not exposed through the editor's AX tree.
    // Its account control has a fixed trailing inset in this bundled layout.
    NSString *title = window.title ?: @"";
    if ([title.pathExtension.lowercaseString length] || [title hasPrefix:@"文字文稿"] ||
        [title hasPrefix:@"工作簿"] || [title hasPrefix:@"演示文稿"]) {
        NSRect bounds = window.contentView.bounds;
        return [window convertRectToScreen:NSMakeRect(NSMaxX(bounds)-92,NSMaxY(bounds)-33,68,22)];
    }
    return NSZeroRect;
}
static void MbsRefreshAccountBadge(void) {
    if (!MbsAccountSignedIn) {
        [MbsAccountBadgePanel orderOut:nil];
        return;
    }
    NSWindow *main = nil;
    for (NSWindow *candidate in NSApp.windows) {
        if (candidate != MbsAccountBadgePanel && candidate.isVisible &&
            candidate.frame.size.width > 600 && candidate.frame.size.height > 300) {
            main = candidate;
            break;
        }
    }
    if (!main) return;
    NSRect target = MbsAccountControlFrame(main);
    if (NSIsEmptyRect(target)) { [MbsAccountBadgePanel orderOut:nil]; return; }
    if (!MbsAccountBadgePanel) {
        MbsAccountBadgePanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 42, 42)
                                                            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                              backing:NSBackingStoreBuffered
                                                                defer:NO];
        MbsAccountBadgePanel.releasedWhenClosed = NO;
        MbsAccountBadgePanel.level = NSNormalWindowLevel;
        MbsAccountBadgePanel.opaque = NO;
        MbsAccountBadgePanel.backgroundColor = NSColor.windowBackgroundColor;
        MbsAccountBadgePanel.ignoresMouseEvents = YES;
        MbsAccountBadgePanel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
        MbsAccountBadgeLabel = [NSTextField labelWithString:@""];
        MbsAccountBadgeLabel.alignment = NSTextAlignmentCenter;
        MbsAccountBadgeLabel.font = [NSFont systemFontOfSize:16.0 weight:NSFontWeightSemibold];
        MbsAccountBadgeLabel.textColor = NSColor.whiteColor;
        MbsAccountBadgeLabel.frame = NSMakeRect(0, 0, 42, 42);
        MbsAccountBadgeLabel.wantsLayer = YES;
        MbsAccountBadgeLabel.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.12 green:0.39 blue:0.86 alpha:1.0].CGColor;
        MbsAccountBadgeLabel.layer.cornerRadius = 21.0;
        [MbsAccountBadgePanel.contentView addSubview:MbsAccountBadgeLabel];
    }
    const char *email = MbsCurrentAccountEmail();
    NSString *initial = email ? MbsAccountInitialForEmail([NSString stringWithUTF8String:email]) : @"";
    MbsAccountBadgeLabel.stringValue = initial;
    free((void *)email);
    CGFloat diameter = MIN(18.0,target.size.height);
    MbsAccountBadgeLabel.frame = NSMakeRect(0,(target.size.height-diameter)/2,diameter,diameter);
    MbsAccountBadgeLabel.layer.cornerRadius = diameter/2;
    [MbsAccountBadgePanel setFrame:target display:NO];
    if (MbsAccountBadgePanel.parentWindow != main) {
        [MbsAccountBadgePanel.parentWindow removeChildWindow:MbsAccountBadgePanel];
        [main addChildWindow:MbsAccountBadgePanel ordered:NSWindowAbove];
    }
    [MbsAccountBadgePanel orderFrontRegardless];
}
static void MbsRefreshAccountHeader(NSNumber *signedIn) {
    const char *email = MbsCurrentAccountEmail();
    MbsAccountSignedIn = signedIn ? signedIn.boolValue : (email != NULL);
    // Native header widgets are owned by their windows. Never retain raw Qt
    // pointers across account notifications or document-window destruction.
    free((void *)email);
    MbsRefreshAccountBadge();
}
static void labelText(kso_qt::QLabel*label,const kso_qt::QString&text) {
    NSString *value=read(text),*replacement=updated(value);
    if(![value isEqualToString:replacement])label->setText(literal(replacement));else label->setText(text);
}
static void buttonText(kso_qt::QAbstractButton*button,const kso_qt::QString&text) {
    NSString *value=read(text),*replacement=updated(value);
    if(![value isEqualToString:replacement])button->setText(literal(replacement));else button->setText(text);
}
static NSString *property(kso_qt::QObject*object,const char*key) {
    auto variant=object->property(key);auto value=variant.toString();NSString *result=read(value);
    value=kso_qt::QString(&empty);return result;
}
static NSString *className(kso_qt::QObject*object) {
    // Verified QtKso 5.12 arm64: QObject::property at 0x207ea4 calls
    // metaObject through vtable slot zero. QObjectPrivate::setParent_helper
    // at 0x200464 reads q_ptr at +8 and parent at +16.
    auto **table=*(void***)object;
    auto meta=((const kso_qt::QMetaObject*(*)(const void*))table[0])(object);
    const char *name=meta?meta->className():nullptr;
    return name?[NSString stringWithUTF8String:name]:@"";
}
static bool routeClick(kso_qt::QObject*receiver,kso_qt::QEvent*event) {
    unsigned short type=0;if(event)memcpy(&type,(char*)event+16,2);
    if(type==3 && NSThread.isMainThread) {
        @autoreleasepool {
            kso_qt::QObject*object=receiver;
            for(int depth=0;object&&depth<7;++depth) {
                NSString *name=className(object),*text=property(object,"text");
                if (isRemovedAssistantText(text)) return true;
                if (isUpgradeText(text)) {
                    MbsShowUpdates();return true;
                }
                void *data=nullptr;memcpy(&data,(char*)object+8,8);
                auto *parent=data?*(kso_qt::QObject**)((char*)data+16):nullptr;
                if(parent==object)break;object=parent;
            }
        }
    }
    return kso_qt::QCoreApplication::notifyInternal2(receiver,event);
}
static void buttonMouseRelease(kso_qt::QAbstractButton *button,kso_qt::QMouseEvent *event) {
    NSString *text=property((kso_qt::QObject*)button,"text");
    if (isRemovedAssistantText(text)) return;
    if (isUpgradeText(text)) {
        MbsShowUpdates();
        return;
    }
    if ([text containsString:@"立即登录"] || [text isEqualToString:@"登录"]) {
        MbsShowLocalAccount();
        return;
    }
    buttonMouseReleaseOriginal(button,event);
}
static bool maybeShowLocalAccount(void *button) {
    NSString *text=property((kso_qt::QObject*)button,"text");
    if (isRemovedAssistantText(text)) return true;
    if (isUpgradeText(text)) {
        MbsShowUpdates(); return true;
    }
    if ([text containsString:@"立即登录"] || [text isEqualToString:@"登录"]) {
        MbsShowLocalAccount(); return true;
    }
    return false;
}
static void clickableLabelMouseRelease(void *button,kso_qt::QMouseEvent *event) {
    if (!maybeShowLocalAccount(button)) clickableLabelMouseReleaseOriginal(button,event);
}
static void headerAvatarMouseRelease(void *button,kso_qt::QMouseEvent *event) {
    if (!maybeShowLocalAccount(button)) headerAvatarMouseReleaseOriginal(button,event);
}
static void headerAuthTipMouseRelease(void *button,kso_qt::QMouseEvent *event) {
    if (!maybeShowLocalAccount(button)) headerAuthTipMouseReleaseOriginal(button,event);
}
static void appEntryMouseRelease(void *button,kso_qt::QMouseEvent *event) {
    if (!maybeShowLocalAccount(button)) appEntryMouseReleaseOriginal(button,event);
}
static void MbsShowAccountForUserClick(void) {
    NSEvent *event = NSApp.currentEvent;
    if ((event.type == NSEventTypeLeftMouseDown || event.type == NSEventTypeLeftMouseUp ||
         event.type == NSEventTypeKeyDown) &&
        NSProcessInfo.processInfo.systemUptime - event.timestamp < 1.0) MbsShowLocalAccount();
}
static void unloginedButtonClick(void *self) {
    MbsShowAccountForUserClick();
}
static void promeGuideLogin(void *self) {
    MbsShowAccountForUserClick();
}
static void headerAvatarClicked(void *self,const kso_qt::QString &value) {
    MbsShowAccountForUserClick();
}
static void headerAvatarPointClicked(void *self,const void *point,const kso_qt::QString &value) {
    MbsShowAccountForUserClick();
}
static void headAvatarClicked(void *self,const kso_qt::QString &value) {
    MbsShowAccountForUserClick();
}
static bool desktopOpenUrl(const void *url) {
    if (url) {
        auto hostValue = qurlHostOriginal(url, 0);
        NSString *host = read(hostValue);
        auto pathValue = qurlPathOriginal(url, 0);
        if ([host.lowercaseString isEqualToString:@"account.wps.cn"] &&
            [read(pathValue) isEqualToString:@"/wpsmaclogin"]) {
            return true;
        }
        if (isLegacyAssistantHost(host)) return true;
        if (isLegacyUpgradeHost(host)) {
            MbsShowUpdates();
            return true;
        }
        if (isBlockedRemoteHost(host)) return true;
    }
    return desktopOpenUrlOriginal(url);
}
struct Interpose {const void*replacement;const void*original;};
__attribute__((used,section("__DATA,__interpose"))) static const Interpose actions[]={
    {(const void*)&labelText,(const void*)&labelSetText},
    {(const void*)&buttonText,(const void*)&buttonSetText},
    {(const void*)&buttonMouseRelease,(const void*)&buttonMouseReleaseOriginal},
    {(const void*)&clickableLabelMouseRelease,(const void*)&clickableLabelMouseReleaseOriginal},
    {(const void*)&headerAvatarMouseRelease,(const void*)&headerAvatarMouseReleaseOriginal},
    {(const void*)&headerAuthTipMouseRelease,(const void*)&headerAuthTipMouseReleaseOriginal},
    {(const void*)&appEntryMouseRelease,(const void*)&appEntryMouseReleaseOriginal},
    {(const void*)&unloginedButtonClick,(const void*)&unloginedButtonClickOriginal},
    {(const void*)&promeGuideLogin,(const void*)&promeGuideLoginOriginal},
    {(const void*)&headerAvatarClicked,(const void*)&headerAvatarClickedOriginal},
    {(const void*)&headerAvatarPointClicked,(const void*)&headerAvatarPointClickedOriginal},
    {(const void*)&headAvatarClicked,(const void*)&headAvatarClickedOriginal},
    {(const void*)&desktopOpenUrl,(const void*)&desktopOpenUrlOriginal},
    {(const void*)&routeClick,(const void*)&kso_qt::QCoreApplication::notifyInternal2}
};
static id MbsLoginMouseMonitor;
static void MbsUseNativeOfflineAction(NSWindow *window) {
    if (!NSThread.isMainThread || !window.isVisible || ![window.title isEqualToString:@"账号登录"]) return;
    static BOOL handling = NO;
    if (handling) return;
    handling = YES;
    id later = MbsFailedNativeLoginAction(window);
    if ([later respondsToSelector:@selector(accessibilityPerformAction:)])
        [later accessibilityPerformAction:NSAccessibilityPressAction];
    else if ([later respondsToSelector:@selector(accessibilityPerformPress)])
        [later accessibilityPerformPress];
    handling = NO;
}
static void InstallMbsOfflineActionObserver(void) {
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification,NSWindowDidUpdateNotification]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                      usingBlock:^(NSNotification *note) {
            MbsUseNativeOfflineAction(note.object);
        }];
    }
    // The editor can enter its login loop before applicationDidFinishLaunching,
    // so a dispatch-to-main observer alone starts too late.
    CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent()+0.5,0.5,0,0,^(CFRunLoopTimerRef) {
            for (NSWindow *window in NSApp.windows) MbsUseNativeOfflineAction(window);
        });
    CFRunLoopAddTimer(CFRunLoopGetMain(),timer,kCFRunLoopCommonModes);
    CFRelease(timer);
}
static void InstallMbsLoginMouseMonitor(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (MbsLoginMouseMonitor) return;
        [[NSNotificationCenter defaultCenter] addObserverForName:@"MbsLocalAccountDidChange"
                                                            object:nil
                                                             queue:[NSOperationQueue mainQueue]
                                                        usingBlock:^(NSNotification *note) {
            MbsRefreshAccountHeader(note.userInfo[@"signedIn"]);
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification
                                                            object:nil
                                                             queue:[NSOperationQueue mainQueue]
                                                        usingBlock:^(NSNotification *note) {
            NSWindow *window = note.object;
            if (window) {
                window.acceptsMouseMovedEvents = YES;
            }
        }];
        for (NSWindow *window in NSApp.windows) window.acceptsMouseMovedEvents = YES;
        MbsLoginMouseMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskLeftMouseUp | NSEventMaskMouseMoved) handler:^NSEvent *(NSEvent *event) {
            NSWindow *window=event.window;
            NSPoint point=event.locationInWindow;
            BOOL isMbsAiWindow = [window.title isEqualToString:@"AI 设置"] ||
                                 [window.title isEqualToString:@"AI"];
            if (event.type == NSEventTypeMouseMoved) {
                MbsRefreshAccountBadge();
                // Keep the hover target deliberately small: only the top-right
                // account control can open the account card.
                NSPoint screenPoint = [window convertPointToScreen:point];
                BOOL accountHoverHit = !isMbsAiWindow && MbsAccountSignedIn &&
                    MbsAccountBadgePanel.isVisible && MbsAccountBadgePanel.parentWindow == window &&
                    NSPointInRect(screenPoint,MbsAccountBadgePanel.frame);
                if (accountHoverHit) {
                    MbsAccountHoverAtWindow((__bridge void *)window, point.x, point.y);
                } else {
                    MbsHideAccountPopover();
                }
                return event;
            }
            return event;
        }];
    });
}
__attribute__((constructor)) static void startChecks() {
    InstallMbsWorkspaceURLHook();
    InstallMbsOfflineActionObserver();
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification*){MbsStartUpdateChecks();MbsStartAccountSession();}];
    InstallMbsLoginMouseMonitor();
}
