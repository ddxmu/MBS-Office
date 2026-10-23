#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "MbsAbout.h"
#import "MbsBrandAppearance.h"
#import "MbsStartupRouting.h"
#import "MbsUpdates.h"

static NSString *const MbsRepositoryURL = @"https://github.com/ddxmu/MBS-Office";

static NSString *MbsApplicationVersion(void) {
    NSBundle *bundle = NSBundle.mainBundle;
    NSString *version = bundle.infoDictionary[@"MbsModuleVersion"];
    if (!version.length) version = bundle.infoDictionary[@"CFBundleShortVersionString"];
    return version.length ? version : @"未知版本";
}

@interface MbsAboutController : NSObject
@property(nonatomic, strong) NSWindow *window;
+ (instancetype)shared;
- (void)show;
@end
@implementation MbsAboutController
+ (instancetype)shared {
    static MbsAboutController *value; static dispatch_once_t once;
    dispatch_once(&once, ^{ value = [MbsAboutController new]; }); return value;
}
- (void)openRepository:(id)sender { [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:MbsRepositoryURL]]; }
- (void)repairStartup:(id)sender { MbsShowStartupRepair(); }
- (void)show {
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,450,260)
            styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
        self.window.title = @"关于 Mbs Office"; self.window.releasedWhenClosed = NO;
        NSView *view = self.window.contentView;
        NSImageView *art = [[NSImageView alloc] initWithFrame:NSMakeRect(24,130,100,100)];
        art.image = MbsBrandArtwork(); art.imageScaling = NSImageScaleProportionallyUpOrDown; [view addSubview:art];
        NSArray *labels = @[@"Mbs Office", [@"版本 " stringByAppendingString:MbsApplicationVersion()], @"让灵感连接每一份文档", MbsRepositoryURL];
        for (NSUInteger i=0;i<labels.count;i++) {
            NSTextField *label = [NSTextField labelWithString:labels[i]];
            label.frame = i<2 ? NSMakeRect(138,187-i*38,285,32) : NSMakeRect(26,104-(i-2)*32,400,24);
            label.font = i==0 ? MbsBrandFont(25) : [NSFont systemFontOfSize:13];
            label.textColor = i==0 ? MbsBrandInk() : NSColor.secondaryLabelColor;
            label.selectable = YES; [view addSubview:label];
        }
        NSButton *button = [NSButton buttonWithTitle:@"打开 GitHub" target:self action:@selector(openRepository:)];
        button.frame = NSMakeRect(300,20,126,32); button.bezelStyle = NSBezelStyleRounded; [view addSubview:button];
        NSButton *repair=[NSButton buttonWithTitle:@"一键修复启动回调" target:self action:@selector(repairStartup:)];
        repair.frame=NSMakeRect(24,20,192,32); repair.bezelStyle=NSBezelStyleRounded; [view addSubview:repair];
        [self.window center];
    }
    [self.window makeKeyAndOrderFront:nil];
}
@end
void MbsShowAbout(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsAboutController shared] show]; });
}

static IMP MbsSendActionOriginal;
static BOOL MbsSendAction(id self, SEL selector, SEL action, id target, id sender) {
    if ([sender isKindOfClass:NSMenuItem.class]) {
        NSString *title = [(NSMenuItem *)sender title];
        if ([title isEqualToString:@"软件更新…"] || [title isEqualToString:@"软件更新..."] ||
            [title isEqualToString:@"Software Update…"]) { MbsShowUpdates(); return YES; }
        if ([title isEqualToString:@"关于 Mbs Office"] || [title isEqualToString:@"关于Mbs Office"] ||
            [title isEqualToString:@"About Mbs Office"]) { MbsShowAbout(); return YES; }
    }
    return ((BOOL (*)(id,SEL,SEL,id,id))MbsSendActionOriginal)(self,selector,action,target,sender);
}
__attribute__((constructor)) static void MbsInstallAboutMenu(void) {
    Method method = class_getInstanceMethod(NSApplication.class,@selector(sendAction:to:from:));
    if (method) { MbsSendActionOriginal = method_getImplementation(method); method_setImplementation(method,(IMP)MbsSendAction); }
}
