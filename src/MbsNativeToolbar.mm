#import <AppKit/AppKit.h>
#import "MbsNativeToolbar.h"
#import "MbsAiPanel.h"
#import "MbsLocalAccount.h"

static const NSInteger kMbsToolbarTagSettings = 1;
static const NSInteger kMbsToolbarTagWrite = 2;
static const NSInteger kMbsToolbarTagPresentation = 3;
static const NSInteger kMbsToolbarTagHistory = 4;
static const NSInteger kMbsToolbarTagAccount = 5;

@interface MbsNativeToolbarController : NSObject
@property(nonatomic,strong) NSPanel *panel;
@property(nonatomic,weak) NSWindow *host;
+ (instancetype)shared;
- (void)showForWindow:(NSWindow *)window;
- (void)reposition;
- (void)action:(NSButton *)sender;
@end

@implementation MbsNativeToolbarController

+ (instancetype)shared {
    static MbsNativeToolbarController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [MbsNativeToolbarController new]; });
    return controller;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidBecomeKey:)
                                                 name:NSWindowDidBecomeKeyNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowDidResize:)
                                                 name:NSWindowDidResizeNotification object:nil];
    return self;
}

- (void)windowDidBecomeKey:(NSNotification *)note {
    NSWindow *window = note.object;
    if (![window isKindOfClass:NSWindow.class] || [window isKindOfClass:NSPanel.class]) return;
    [self showForWindow:window];
}

- (void)windowDidResize:(NSNotification *)note {
    if (note.object == self.host) [self reposition];
}

- (NSButton *)button:(NSString *)title tag:(NSInteger)tag tooltip:(NSString *)tooltip {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:@selector(action:)];
    button.tag = tag;
    button.toolTip = tooltip;
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

- (void)showForWindow:(NSWindow *)window {
    if (!window || window == self.panel || !window.isVisible) return;
    if (window.frame.size.width < 520 || window.frame.size.height < 240) return;
    self.host = window;
    if (!self.panel) {
        self.panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 478, 52)
                                                styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                  backing:NSBackingStoreBuffered defer:NO];
        self.panel.opaque = NO;
        self.panel.backgroundColor = NSColor.clearColor;
        self.panel.hasShadow = YES;
        self.panel.floatingPanel = NO;
        self.panel.hidesOnDeactivate = NO;
        self.panel.becomesKeyOnlyIfNeeded = YES;
        self.panel.level = NSNormalWindowLevel;
        self.panel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;

        NSVisualEffectView *effect = [NSVisualEffectView new];
        effect.material = NSVisualEffectMaterialHeaderView;
        effect.blendingMode = NSVisualEffectBlendingModeWithinWindow;
        effect.state = NSVisualEffectStateActive;
        effect.wantsLayer = YES;
        effect.layer.cornerRadius = 12.0;
        effect.layer.borderWidth = 1.0;
        effect.layer.borderColor = [NSColor colorWithWhite:0.72 alpha:0.75].CGColor;
        effect.translatesAutoresizingMaskIntoConstraints = NO;
        self.panel.contentView = effect;

        NSTextField *brand = [NSTextField labelWithString:@"Mbs"]; 
        brand.font = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        brand.textColor = [NSColor colorWithRed:0.08 green:0.28 blue:0.58 alpha:1.0];
        brand.translatesAutoresizingMaskIntoConstraints = NO;
        [effect addSubview:brand];

        NSButton *settings = [self button:@"设置" tag:kMbsToolbarTagSettings tooltip:@"打开统一 AI 设置"];
        NSButton *write = [self button:@"写作" tag:kMbsToolbarTagWrite tooltip:@"打开 Mbs AI 写作"];
        NSButton *presentation = [self button:@"演示" tag:kMbsToolbarTagPresentation tooltip:@"打开 Mbs AI 演示生成"];
        NSButton *history = [self button:@"历史" tag:kMbsToolbarTagHistory tooltip:@"打开本地 AI 历史"];
        NSButton *account = [self button:@"账号" tag:kMbsToolbarTagAccount tooltip:@"打开 Mbs 账号与授权"];
        for (NSButton *button in @[settings, write, presentation, history, account]) [effect addSubview:button];

        [NSLayoutConstraint activateConstraints:@[
            [brand.leadingAnchor constraintEqualToAnchor:effect.leadingAnchor constant:14],
            [brand.centerYAnchor constraintEqualToAnchor:effect.centerYAnchor],
            [settings.leadingAnchor constraintEqualToAnchor:brand.trailingAnchor constant:12],
            [settings.centerYAnchor constraintEqualToAnchor:effect.centerYAnchor],
            [write.leadingAnchor constraintEqualToAnchor:settings.trailingAnchor constant:6],
            [write.centerYAnchor constraintEqualToAnchor:effect.centerYAnchor],
            [presentation.leadingAnchor constraintEqualToAnchor:write.trailingAnchor constant:6],
            [presentation.centerYAnchor constraintEqualToAnchor:effect.centerYAnchor],
            [history.leadingAnchor constraintEqualToAnchor:presentation.trailingAnchor constant:6],
            [history.centerYAnchor constraintEqualToAnchor:effect.centerYAnchor],
            [account.leadingAnchor constraintEqualToAnchor:history.trailingAnchor constant:6],
            [account.trailingAnchor constraintEqualToAnchor:effect.trailingAnchor constant:-10],
            [account.centerYAnchor constraintEqualToAnchor:effect.centerYAnchor],
            [effect.topAnchor constraintEqualToAnchor:self.panel.contentView.topAnchor],
            [effect.bottomAnchor constraintEqualToAnchor:self.panel.contentView.bottomAnchor],
            [effect.leadingAnchor constraintEqualToAnchor:self.panel.contentView.leadingAnchor],
            [effect.trailingAnchor constraintEqualToAnchor:self.panel.contentView.trailingAnchor]
        ]];
    }
    if (self.panel.parentWindow != window) {
        [self.panel.parentWindow removeChildWindow:self.panel];
        [window addChildWindow:self.panel ordered:NSWindowAbove];
    }
    [self reposition];
    [self.panel orderFront:nil];
}

- (void)reposition {
    NSWindow *window = self.host;
    if (!window || !window.isVisible || !self.panel) return;
    NSRect host = window.frame;
    NSRect panel = self.panel.frame;
    panel.origin.x = NSMaxX(host) - panel.size.width - 16.0;
    panel.origin.y = NSMaxY(host) - panel.size.height - 34.0;
    [self.panel setFrame:panel display:NO];
}

- (void)action:(NSButton *)sender {
    switch (sender.tag) {
        case kMbsToolbarTagSettings: MbsShowAiSettings(); break;
        case kMbsToolbarTagWrite: MbsShowAiAssistant("write", ""); break;
        case kMbsToolbarTagPresentation: MbsShowAiAssistant("ppt", ""); break;
        case kMbsToolbarTagHistory: MbsShowAiAssistant("history", ""); break;
        case kMbsToolbarTagAccount: MbsShowLocalAccount(); break;
        default: break;
    }
}

@end

void MbsStartNativeToolbar(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        MbsNativeToolbarController *controller = [MbsNativeToolbarController shared];
        NSWindow *window = NSApp.keyWindow;
        if (window && ![window isKindOfClass:NSPanel.class]) [controller showForWindow:window];
    });
}
