#import <AppKit/AppKit.h>
#import "MbsNativeLoginRecovery.h"
#import "MbsStartupRouting.h"
#import "MbsAccountEntry.h"
#import "MbsRecentHomeView.h"
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach-o/getsect.h>

static unsigned MbsStartupRoutes;
static BOOL MbsRecoveringLegacyWindow;
static NSDate *MbsLastStartupRecovery;
static unsigned MbsQuietStartupKinds;
static NSUserDefaults *MbsRecoveryPreferences;
static CFRunLoopTimerRef MbsAutomaticRecoveryTimer;
static BOOL MbsInitialStartupRecovery=YES;
static NSString *const MbsRecoveryEnabledKey=@"MbsStartupRecoveryEnabled";
static NSString *const MbsRecoveryValueKey=@"MbsStartupRecoveryIntervalValue";
static NSString *const MbsRecoveryUnitKey=@"MbsStartupRecoveryIntervalUnit";
static NSString *const MbsRecoveryLastKey=@"MbsStartupRecoveryLastSuccess";
static NSUserDefaults *MbsRecoveryDefaults(void) {
    if (!MbsRecoveryPreferences) MbsRecoveryPreferences=NSUserDefaults.standardUserDefaults;
    [MbsRecoveryPreferences registerDefaults:@{MbsRecoveryEnabledKey:@YES,
        MbsRecoveryValueKey:@3,MbsRecoveryUnitKey:@1}];
    return MbsRecoveryPreferences;
}
static NSTimeInterval MbsRecoveryInterval(NSInteger value, NSInteger unit) {
    if (value<1 || value>NSIntegerMax/86400 || unit<0 || unit>2) return 0;
    const NSTimeInterval seconds[]={86400,3600,60};
    return value*seconds[unit];
}
static NSTimeInterval MbsSavedRecoveryInterval(void) {
    NSUserDefaults *preferences=MbsRecoveryDefaults();
    NSTimeInterval interval=MbsRecoveryInterval([preferences integerForKey:MbsRecoveryValueKey],
        [preferences integerForKey:MbsRecoveryUnitKey]);
    return interval ?: 3*3600;
}
static BOOL MbsAutomaticRecoveryDue(NSDate *now) {
    NSUserDefaults *preferences=MbsRecoveryDefaults();
    if (![preferences boolForKey:MbsRecoveryEnabledKey]) return NO;
    if (MbsInitialStartupRecovery) return YES;
    NSDate *last=[preferences objectForKey:MbsRecoveryLastKey];
    return ![last isKindOfClass:NSDate.class] || [now timeIntervalSinceDate:last]>=MbsSavedRecoveryInterval();
}
static void MbsConfigureAutomaticRecovery(void);

extern "C" unsigned MbsLegacyQuietStartupKinds(void) { return MbsQuietStartupKinds; }

// Keep the real Qt window and its completion action alive. Only its old
// presentation is quiet; a raw close would skip the startup callback.
static char MbsLegacyAccountRequested, MbsLegacyCompletionQueued;
static void MbsScheduleLegacyCompletion(NSWindow *window);
static BOOL MbsIsQuietLegacyWindow(NSWindow *window) {
    if ([window.title isEqualToString:@"账号登录"]) return YES;
    NSSize size=window.frame.size;
    return !window.title.length && !(window.styleMask & NSWindowStyleMaskTitled) &&
        size.width<=850 && size.height<=120 && MbsHasLegacyCloudNotice(window);
}
static char MbsQuietOriginalAlpha;
static IMP MbsOriginalWindowTitle, MbsOriginalWindowOrder, MbsOriginalWindowAlpha, MbsOriginalWindowKey;
static void MbsApplyQuietPresentation(NSWindow *window) {
    NSNumber *saved=objc_getAssociatedObject(window,&MbsQuietOriginalAlpha);
    if (MbsIsQuietLegacyWindow(window)) {
        MbsQuietStartupKinds|=[window.title isEqualToString:@"账号登录"] ? 1 : 2;
        if (!saved) objc_setAssociatedObject(window,&MbsQuietOriginalAlpha,@(window.alphaValue),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        window.alphaValue=0;
    } else if (saved) {
        objc_setAssociatedObject(window,&MbsQuietOriginalAlpha,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        window.alphaValue=saved.doubleValue;
    }
}
static void MbsQuietWindowTitle(id window,SEL action,NSString *title) {
    ((void (*)(id,SEL,id))MbsOriginalWindowTitle)(window,action,title);
    MbsApplyQuietPresentation(window);
    MbsScheduleLegacyCompletion(window);
}
static void MbsQuietWindowOrder(id window,SEL action,NSWindowOrderingMode mode,NSInteger other) {
    if (mode!=NSWindowOut && ![window isVisible] && [[window title] isEqualToString:@"账号登录"]) {
        NSEvent *event=NSApp.currentEvent;
        if ((event.type==NSEventTypeLeftMouseUp || event.type==NSEventTypeKeyDown) &&
            NSProcessInfo.processInfo.systemUptime-event.timestamp<1)
            objc_setAssociatedObject(window,&MbsLegacyAccountRequested,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (mode!=NSWindowOut) MbsApplyQuietPresentation(window);
    ((void (*)(id,SEL,NSWindowOrderingMode,NSInteger))MbsOriginalWindowOrder)(window,action,mode,other);
    if (mode!=NSWindowOut) MbsScheduleLegacyCompletion(window);
}
static void MbsQuietWindowAlpha(id window,SEL action,CGFloat alpha) {
    if (MbsIsQuietLegacyWindow(window)) {
        if (!objc_getAssociatedObject(window,&MbsQuietOriginalAlpha))
            objc_setAssociatedObject(window,&MbsQuietOriginalAlpha,@(alpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        alpha=0;
    }
    ((void (*)(id,SEL,CGFloat))MbsOriginalWindowAlpha)(window,action,alpha);
}
static void MbsQuietWindowKey(id window,SEL action) {
    if (MbsIsQuietLegacyWindow(window)) {
        MbsApplyQuietPresentation(window); MbsScheduleLegacyCompletion(window); return;
    }
    ((void (*)(id,SEL))MbsOriginalWindowKey)(window,action);
}
static void MbsInstallQuietPresentation(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL selectors[]={@selector(setTitle:),@selector(orderWindow:relativeTo:),@selector(setAlphaValue:),@selector(makeKeyWindow)};
        IMP replacements[]={(IMP)MbsQuietWindowTitle,(IMP)MbsQuietWindowOrder,(IMP)MbsQuietWindowAlpha,(IMP)MbsQuietWindowKey};
        IMP *originals[]={&MbsOriginalWindowTitle,&MbsOriginalWindowOrder,&MbsOriginalWindowAlpha,&MbsOriginalWindowKey};
        for (NSUInteger index=0;index<4;++index) {
            Method method=class_getInstanceMethod(NSWindow.class,selectors[index]);
            *originals[index]=method_setImplementation(method,replacements[index]);
        }
    });
}

extern "C" unsigned MbsLegacyStartupPromptCount(void) {
    return __atomic_load_n(&MbsStartupRoutes,__ATOMIC_RELAXED);
}

extern "C" void MbsNoteNativeStartupCompletion(void) {
    MbsInitialStartupRecovery=NO;
    if (MbsLegacyStartupPromptCount()!=0) return;
    __atomic_add_fetch(&MbsStartupRoutes,1,__ATOMIC_RELAXED);
    MbsLastStartupRecovery=NSDate.date;
    [MbsRecoveryDefaults() setObject:MbsLastStartupRecovery forKey:MbsRecoveryLastKey];
    if (MbsAutomaticRecoveryTimer) CFRunLoopTimerSetNextFireDate(MbsAutomaticRecoveryTimer,
        CFAbsoluteTimeGetCurrent()+MbsSavedRecoveryInterval());
}

static BOOL MbsRecoverFailedLogin(NSWindow *window, BOOL recordRecovery=YES) {
    if (!NSThread.isMainThread || MbsRecoveringLegacyWindow || !window.isVisible ||
        ![window.title isEqualToString:@"账号登录"]) return NO;
    MbsRecoveringLegacyWindow = YES;
    id later = MbsNativeLoginLaterAction(window,NO);
    BOOL handled = NO;
    if ([later respondsToSelector:@selector(accessibilityPerformAction:)]) {
        [later accessibilityPerformAction:NSAccessibilityPressAction];
        handled = YES;
    } else if ([later respondsToSelector:@selector(accessibilityPerformPress)]) {
        handled = [later accessibilityPerformPress];
    }
    MbsRecoveringLegacyWindow = NO;
    if (handled) {
        MbsInitialStartupRecovery=NO;
        if ([objc_getAssociatedObject(window,&MbsLegacyAccountRequested) boolValue]) {
            objc_setAssociatedObject(window,&MbsLegacyAccountRequested,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dispatch_async(dispatch_get_main_queue(),^{ MbsOpenAccountEntry(); });
        }
        if (recordRecovery) {
            __atomic_add_fetch(&MbsStartupRoutes,1,__ATOMIC_RELAXED);
            MbsLastStartupRecovery=NSDate.date;
            [MbsRecoveryDefaults() setObject:MbsLastStartupRecovery forKey:MbsRecoveryLastKey];
            if (MbsAutomaticRecoveryTimer) CFRunLoopTimerSetNextFireDate(MbsAutomaticRecoveryTimer,
                CFAbsoluteTimeGetCurrent()+MbsSavedRecoveryInterval());
        }
    }
    return handled;
}

// Finishing an obsolete modal is required to keep the editor interactive.
// It is separate from the optional timed repair and never opens the old page.
static void MbsRunLegacyCompletion(NSWindow *window) {
    if (window.isVisible && [window.title isEqualToString:@"账号登录"])
        MbsRecoverFailedLogin(window,MbsAutomaticRecoveryDue(NSDate.date));
    if (window.isVisible && [window.title isEqualToString:@"账号登录"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
            MbsRunLegacyCompletion(window);
        });
    } else objc_setAssociatedObject(window,&MbsLegacyCompletionQueued,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void MbsScheduleLegacyCompletion(NSWindow *window) {
    if (![window.title isEqualToString:@"账号登录"] ||
        [objc_getAssociatedObject(window,&MbsLegacyCompletionQueued) boolValue]) return;
    objc_setAssociatedObject(window,&MbsLegacyCompletionQueued,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    dispatch_async(dispatch_get_main_queue(),^{ MbsRunLegacyCompletion(window); });
}

static BOOL MbsRecoverAutomatically(NSWindow *window) {
    if (!MbsAutomaticRecoveryDue(NSDate.date)) return NO;
    BOOL recovered=MbsRecoverFailedLogin(window);
    // The first error page may finish loading after the initial timer fires.
    // Wait only for that visible login; after success the saved interval applies.
    if (!recovered && window.isVisible && [window.title isEqualToString:@"账号登录"] && MbsAutomaticRecoveryTimer) {
        CFAbsoluteTime retry=CFAbsoluteTimeGetCurrent()+2;
        if (CFRunLoopTimerGetNextFireDate(MbsAutomaticRecoveryTimer)>retry)
            CFRunLoopTimerSetNextFireDate(MbsAutomaticRecoveryTimer,retry);
    }
    return recovered;
}
static void MbsConfigureAutomaticRecovery(void) {
    if (MbsAutomaticRecoveryTimer) {
        CFRunLoopTimerInvalidate(MbsAutomaticRecoveryTimer);
        CFRelease(MbsAutomaticRecoveryTimer); MbsAutomaticRecoveryTimer=NULL;
    }
    if (![MbsRecoveryDefaults() boolForKey:MbsRecoveryEnabledKey]) return;
    NSTimeInterval interval=MbsSavedRecoveryInterval();
    NSDate *last=[MbsRecoveryDefaults() objectForKey:MbsRecoveryLastKey];
    NSTimeInterval delay=!MbsInitialStartupRecovery && [last isKindOfClass:NSDate.class] ?
        MAX(0.5,interval+last.timeIntervalSinceNow) : 0.5;
    MbsAutomaticRecoveryTimer=CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent()+delay,interval,0,0,^(CFRunLoopTimerRef timer) {
            for (NSWindow *window in NSApp.windows.copy) {
                MbsApplyQuietPresentation(window);
                MbsRecoverAutomatically(window);
            }
            if (MbsInitialStartupRecovery && MbsAutomaticRecoveryDue(NSDate.date))
                CFRunLoopTimerSetNextFireDate(timer,CFAbsoluteTimeGetCurrent()+2);
        });
    CFRunLoopAddTimer(CFRunLoopGetMain(),MbsAutomaticRecoveryTimer,kCFRunLoopCommonModes);
}

@interface MbsStartupRepairController : NSObject
@property NSOpenPanel *documentPicker;
+ (instancetype)shared;
- (void)repair:(id)sender;
- (void)openService:(id)sender;
- (void)openDocument:(id)sender;
@end
@implementation MbsStartupRepairController
+ (instancetype)shared {
    static MbsStartupRepairController *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value=[MbsStartupRepairController new]; }); return value;
}
- (BOOL)validateMenuItem:(NSMenuItem *)item { return YES; }
- (BOOL)worksWhenModal { return YES; }
- (void)openService:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"https://ttys.ddxmu.com/"]];
}
- (void)openDocument:(id)sender {
    if (self.documentPicker) { [self.documentPicker makeKeyAndOrderFront:nil]; return; }
    NSWindow *home = [sender isKindOfClass:NSView.class] ? [sender window] : NSApp.keyWindow;
    if (!home) return;
    NSOpenPanel *picker=[NSOpenPanel openPanel]; self.documentPicker=picker;
    picker.title=@"打开文档"; picker.prompt=@"打开";
    picker.canChooseFiles=YES; picker.canChooseDirectories=NO; picker.allowsMultipleSelection=NO;
    picker.allowedFileTypes=@[@"doc",@"docx",@"dot",@"dotx",@"odt",@"rtf",@"txt",@"wps",@"wpt",
        @"xls",@"xlsx",@"xlsm",@"xlsb",@"csv",@"ods",@"et",@"ett",@"ppt",@"pptx",@"pptm",@"odp",@"dps",@"dpt",@"pdf"];
    [picker beginSheetModalForWindow:home completionHandler:^(NSModalResponse result) {
        self.documentPicker=nil;
        if (result!=NSModalResponseOK || !picker.URL) return;
        // Address this editor explicitly; the system default may be another app.
        [NSWorkspace.sharedWorkspace openURLs:@[picker.URL] withApplicationAtURL:NSBundle.mainBundle.bundleURL
            configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:^(NSRunningApplication *app,NSError *error) {
                if (!error) return;
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSAlert *alert=[NSAlert new]; alert.messageText=@"文档未能打开";
                    alert.informativeText=error.localizedDescription; [alert runModal];
                });
            }];
    }];
}
- (void)repair:(id)sender {
    BOOL recovered=NO;
    for (NSWindow *window in NSApp.windows.copy) recovered=MbsRecoverFailedLogin(window) || recovered;
    NSAlert *alert=[NSAlert new];
    alert.messageText=@"修复启动回调";
    if (recovered) {
        alert.informativeText=@"已执行启动恢复回调，请返回文档检查工具栏。";
    } else alert.informativeText=@"当前没有待处理的失败回调。点击首页刷新按钮仍可手动修复；若工具栏仍为灰色，可保存文档并正常重启。";
    if (MbsLastStartupRecovery) {
        NSDateFormatter *format=[NSDateFormatter new]; format.dateFormat=@"HH:mm:ss";
        alert.informativeText=[NSString stringWithFormat:@"本次启动已完成 %u 次恢复回调，最近一次：%@。若工具栏仍为灰色，可保存文档并正常重启修复。",
            MbsLegacyStartupPromptCount(),[format stringFromDate:MbsLastStartupRecovery]];
    }
    NSView *settings=[[NSView alloc] initWithFrame:NSMakeRect(0,0,370,142)];
    NSButton *automatic=[NSButton checkboxWithTitle:@"启用自动回调" target:nil action:nil];
    automatic.frame=NSMakeRect(0,110,350,24);
    automatic.state=[MbsRecoveryDefaults() boolForKey:MbsRecoveryEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;
    [settings addSubview:automatic];
    NSTextField *label=[NSTextField labelWithString:@"回调间隔"]; label.frame=NSMakeRect(0,75,80,22);
    [settings addSubview:label];
    NSTextField *value=[[NSTextField alloc] initWithFrame:NSMakeRect(86,72,110,26)];
    value.stringValue=[NSString stringWithFormat:@"%ld",(long)[MbsRecoveryDefaults() integerForKey:MbsRecoveryValueKey]];
    value.accessibilityLabel=@"回调间隔数值"; [settings addSubview:value];
    NSPopUpButton *unit=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(206,71,100,28) pullsDown:NO];
    [unit addItemsWithTitles:@[@"天",@"小时",@"分钟"]];
    [unit selectItemAtIndex:[MbsRecoveryDefaults() integerForKey:MbsRecoveryUnitKey]];
    unit.accessibilityLabel=@"回调时间单位"; [settings addSubview:unit];
    NSTextField *hint=[NSTextField wrappingLabelWithString:@"启用时先完成本次启动恢复，之后默认每 3 小时一次。关闭后仅手动修复；旧登录页仍会静默关闭。设置重启后保留。"];
    hint.frame=NSMakeRect(0,2,370,60); hint.textColor=NSColor.secondaryLabelColor;
    [settings addSubview:hint]; alert.accessoryView=settings;
    [alert addButtonWithTitle:@"保存设置"];
    [alert addButtonWithTitle:@"保存并重启修复"];
    [alert addButtonWithTitle:@"取消"];
    NSModalResponse response;
    while ((response=[alert runModal])==NSAlertFirstButtonReturn) {
        long long quantity=0; NSScanner *scanner=[NSScanner scannerWithString:value.stringValue];
        if (![scanner scanLongLong:&quantity] || !scanner.isAtEnd ||
            !MbsRecoveryInterval(quantity,unit.indexOfSelectedItem)) {
            hint.stringValue=@"请输入大于 0 的整数，并选择天、小时或分钟。";
            hint.textColor=NSColor.systemRedColor; continue;
        }
        [MbsRecoveryDefaults() setBool:automatic.state==NSControlStateValueOn forKey:MbsRecoveryEnabledKey];
        [MbsRecoveryDefaults() setInteger:quantity forKey:MbsRecoveryValueKey];
        [MbsRecoveryDefaults() setInteger:unit.indexOfSelectedItem forKey:MbsRecoveryUnitKey];
        [MbsRecoveryDefaults() synchronize];
        MbsConfigureAutomaticRecovery(); return;
    }
    if (response!=NSAlertSecondButtonReturn) return;
    // The Qt host can exit without NSApplicationWillTerminateNotification.
    // Start the waiter before asking it to quit, and cancel the waiter if
    // terminate: returns (for example, when a document save was cancelled).
    NSURL *outer=NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent
        .URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:@"/bin/sh"];
    task.arguments=@[@"-c", @"i=0; while [ \"$i\" -lt 600 ]; do i=$((i+1)); if ! /bin/kill -0 \"$1\" 2>/dev/null; then /bin/sleep 1; exec /usr/bin/open -n \"$2\"; fi; /bin/sleep 0.2; done",
        @"mbs-startup-repair", [NSString stringWithFormat:@"%d",getpid()], outer.path];
    task.standardInput=NSFileHandle.fileHandleWithNullDevice;
    task.standardOutput=NSFileHandle.fileHandleWithNullDevice;
    task.standardError=NSFileHandle.fileHandleWithNullDevice;
    NSError *error=nil;
    if (![task launchAndReturnError:&error]) {
        NSAlert *failure=[NSAlert new]; failure.messageText=@"无法准备自动重启";
        failure.informativeText=error.localizedDescription; [failure runModal]; return;
    }
    [NSApp terminate:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // Qt may reply NSTerminateLater and finish quitting asynchronously.
        // A surviving app without a save sheet means the quit was cancelled.
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
            BOOL saving=NSApp.modalWindow!=nil;
            for (NSWindow *window in NSApp.windows) saving=saving || window.attachedSheet!=nil;
            if (!task.running || !saving) {
                if (task.running) [task terminate];
                [timer invalidate];
            }
        }];
    });
}
@end
void MbsShowStartupRepair(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [MbsStartupRepairController.shared repair:nil]; });
}
static void MbsInstallRepairMenu(void) {
    NSMenu *help=[NSApp.mainMenu itemWithTitle:@"帮助"].submenu;
    if (!help) return;
    NSMenuItem *existing=[help itemWithTitle:@"修复启动回调…"];
    if (existing) { existing.enabled=YES; return; }
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"修复启动回调…" action:@selector(repair:) keyEquivalent:@""];
    item.target=MbsStartupRepairController.shared;
    [help addItem:item];
}
static NSImage *MbsStartupRepairIcon(void) {
    Dl_info image; unsigned long size=0;
    if (!dladdr((const void *)MbsStartupRepairIcon,&image)) return nil;
    const unsigned char *bytes=getsectiondata((const struct mach_header_64 *)image.dli_fbase,
                                            "__TEXT","__mbs_repair",&size);
    return bytes && size ? [[NSImage alloc] initWithData:[NSData dataWithBytes:bytes length:size]] : nil;
}
static void MbsInstallHomeRepairButton(NSWindow *window) {
    if (!window.contentView) return;
#ifndef MBS_STARTUP_ROUTING_TEST
    MbsUpdateRecentHomeView(window);
#endif
    NSView *view=window.contentView;
    BOOL home=[window.title isEqualToString:@"首页"];
    // The two icon tiles are painted by Qt and omitted from its AX tree.
    // Own transparent hit targets preserve the artwork and expose real actions.
    for (NSUInteger index=0;index<2;++index) {
        NSInteger tag=0x4d425344+index;
        NSButton *entry=(NSButton *)[view viewWithTag:tag];
        if (!entry && home) {
            entry=[NSButton buttonWithTitle:@"" target:MbsStartupRepairController.shared
                action:index==0 ? @selector(openDocument:) : @selector(openService:)];
            entry.tag=tag; entry.transparent=YES;
            entry.accessibilityLabel=index==0 ? @"文档" : @"服务";
            entry.toolTip=index==0 ? @"选择并打开文档" : @"打开 Mbs Office 官网";
            entry.frame=NSMakeRect(8,view.isFlipped ? 98+72*index : NSHeight(view.bounds)-160-72*index,52,62);
            entry.autoresizingMask=view.isFlipped ? NSViewMaxYMargin : NSViewMinYMargin;
            [view addSubview:entry positioned:NSWindowAbove relativeTo:nil];
        }
        entry.hidden=!home;
    }
    NSView *existing=[view viewWithTag:0x4d425352];
    if (existing) { existing.hidden=!home; return; }
    if (!home) return;
    NSButton *button=[NSButton buttonWithTitle:@"" target:MbsStartupRepairController.shared action:@selector(repair:)];
    button.tag=0x4d425352; button.bordered=NO;
    button.image=MbsStartupRepairIcon(); button.imageScaling=NSImageScaleProportionallyUpOrDown;
    button.toolTip=@"一键修复启动回调"; button.accessibilityLabel=button.toolTip;
    // This is a child of the home window, anchored in its narrow left rail.
    button.frame=NSMakeRect(18,view.isFlipped ? NSHeight(view.bounds)-54 : 18,32,32);
    button.autoresizingMask=view.isFlipped ? NSViewMinYMargin : NSViewMaxYMargin;
    [view addSubview:button positioned:NSWindowAbove relativeTo:nil];
}

#ifndef MBS_STARTUP_ROUTING_TEST
__attribute__((constructor)) static void MbsInstallStartupRouting(void) {
    MbsInstallQuietPresentation();
    // Closing the Cocoa window skips the editor's Later-login completion.
    // Complete only the obsolete native login through its existing Later action;
    // document windows and the Mbs account panel keep their own lifecycle.
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidUpdateNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
            usingBlock:^(NSNotification *note) {
                MbsApplyQuietPresentation(note.object);
                MbsScheduleLegacyCompletion(note.object);
                MbsInstallHomeRepairButton(note.object);
                MbsInstallRepairMenu();
            }];
    }
    // The common-mode timer also runs during the native login's nested loop.
    // Successful callbacks share one persisted cooldown with window events.
    MbsConfigureAutomaticRecovery();
    for (NSNotificationName name in @[NSApplicationDidFinishLaunchingNotification, NSWindowDidBecomeKeyNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                MbsInstallRepairMenu();
                for (NSWindow *window in NSApp.windows) MbsInstallHomeRepairButton(window);
            });
        }];
    }
}
#endif
