#import <AppKit/AppKit.h>
#import "MbsNativeLoginRecovery.h"
#import "MbsStartupRouting.h"
#import <objc/runtime.h>
#include <dlfcn.h>
#include <mach-o/getsect.h>

static unsigned MbsStartupRoutes;
static BOOL MbsRecoveringLegacyWindow;
static NSDate *MbsLastStartupRecovery;
static unsigned MbsQuietStartupKinds;
extern "C" unsigned MbsLegacyQuietStartupKinds(void) { return MbsQuietStartupKinds; }

// Keep the real Qt window and its completion action alive. Only its old
// presentation is quiet; a raw close would skip the startup callback.
static char MbsLegacyLoadingSince;
static BOOL MbsIsQuietLegacyWindow(NSWindow *window) {
    if ([window.title isEqualToString:@"账号登录"]) {
        NSDate *since=objc_getAssociatedObject(window,&MbsLegacyLoadingSince);
        if (!since) {
            since=NSDate.date;
            objc_setAssociatedObject(window,&MbsLegacyLoadingSince,since,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // Keep loading quiet, but never strand a working login as an
        // invisible modal if the old service unexpectedly becomes available.
        return MbsFailedNativeLoginAction(window)!=nil || -since.timeIntervalSinceNow<10;
    }
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
}
static void MbsQuietWindowOrder(id window,SEL action,NSWindowOrderingMode mode,NSInteger other) {
    if (mode!=NSWindowOut && ![window isVisible] && [[window title] isEqualToString:@"账号登录"])
        objc_setAssociatedObject(window,&MbsLegacyLoadingSince,NSDate.date,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (mode!=NSWindowOut) MbsApplyQuietPresentation(window);
    ((void (*)(id,SEL,NSWindowOrderingMode,NSInteger))MbsOriginalWindowOrder)(window,action,mode,other);
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
    if (![window isVisible] && [[window title] isEqualToString:@"账号登录"])
        objc_setAssociatedObject(window,&MbsLegacyLoadingSince,NSDate.date,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (MbsIsQuietLegacyWindow(window)) { MbsApplyQuietPresentation(window); return; }
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

static BOOL MbsRecoverFailedLogin(NSWindow *window) {
    if (!NSThread.isMainThread || MbsRecoveringLegacyWindow || !window.isVisible ||
        ![window.title isEqualToString:@"账号登录"]) return NO;
    MbsRecoveringLegacyWindow = YES;
    id later = MbsFailedNativeLoginAction(window);
    BOOL handled = NO;
    if ([later respondsToSelector:@selector(accessibilityPerformAction:)]) {
        [later accessibilityPerformAction:NSAccessibilityPressAction];
        handled = YES;
    } else if ([later respondsToSelector:@selector(accessibilityPerformPress)]) {
        handled = [later accessibilityPerformPress];
    }
    MbsRecoveringLegacyWindow = NO;
    if (handled) {
        __atomic_add_fetch(&MbsStartupRoutes,1,__ATOMIC_RELAXED);
        MbsLastStartupRecovery=NSDate.date;
    }
    return handled;
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
        [alert addButtonWithTitle:@"好"]; [alert runModal]; return;
    }
    alert.informativeText=@"自动回调恢复已启用。若工具栏仍为灰色，可保存文档并正常重启，重新完成启动流程。退出时仍会提示保存未保存的文档。";
    if (MbsLastStartupRecovery) {
        NSDateFormatter *format=[NSDateFormatter new]; format.dateFormat=@"HH:mm:ss";
        alert.informativeText=[NSString stringWithFormat:@"本次启动已在后台完成 %u 次恢复回调，最近一次：%@。若工具栏仍为灰色，可保存文档并正常重启修复。",
            MbsLegacyStartupPromptCount(),[format stringFromDate:MbsLastStartupRecovery]];
    }
    [alert addButtonWithTitle:@"保存并重启修复"];
    [alert addButtonWithTitle:@"取消"];
    if ([alert runModal]!=NSAlertFirstButtonReturn) return;
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
    if (!help || [help itemWithTitle:@"修复启动回调…"]) return;
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
    // Recover only a failed page through its existing action; leave a working
    // native login, document windows and Mbs account panels untouched.
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidUpdateNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
            usingBlock:^(NSNotification *note) {
                MbsApplyQuietPresentation(note.object);
                MbsRecoverFailedLogin(note.object);
                MbsInstallHomeRepairButton(note.object);
            }];
    }
    // A native login can run a nested event loop before app launch completes.
    CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent()+0.5, 0.5, 0, 0, ^(CFRunLoopTimerRef) {
            for (NSWindow *window in NSApp.windows) {
                MbsApplyQuietPresentation(window);
                MbsRecoverFailedLogin(window);
            }
        });
    CFRunLoopAddTimer(CFRunLoopGetMain(), timer, kCFRunLoopCommonModes);
    CFRelease(timer);
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
