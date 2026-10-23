#import <AppKit/AppKit.h>
#import "MbsNativeLoginRecovery.h"
#import "MbsStartupRouting.h"
#include <dlfcn.h>
#include <mach-o/getsect.h>

static unsigned MbsStartupRoutes;
static BOOL MbsRecoveringLegacyWindow;

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
    if (handled) __atomic_add_fetch(&MbsStartupRoutes,1,__ATOMIC_RELAXED);
    return handled;
}

@interface MbsStartupRepairController : NSObject
+ (instancetype)shared;
- (void)repair:(id)sender;
@end
@implementation MbsStartupRepairController
+ (instancetype)shared {
    static MbsStartupRepairController *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value=[MbsStartupRepairController new]; }); return value;
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
    NSView *existing=[view viewWithTag:0x4d425352];
    BOOL home=[window.title isEqualToString:@"首页"];
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
    // Closing the Cocoa window skips the editor's Later-login completion.
    // Recover only a failed page through its existing action; leave a working
    // native login, document windows and Mbs account panels untouched.
    for (NSNotificationName name in @[NSWindowDidBecomeKeyNotification, NSWindowDidUpdateNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
            usingBlock:^(NSNotification *note) {
                MbsRecoverFailedLogin(note.object);
                MbsInstallHomeRepairButton(note.object);
            }];
    }
    // A native login can run a nested event loop before app launch completes.
    CFRunLoopTimerRef timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault,
        CFAbsoluteTimeGetCurrent()+0.5, 0.5, 0, 0, ^(CFRunLoopTimerRef) {
            for (NSWindow *window in NSApp.windows) MbsRecoverFailedLogin(window);
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
