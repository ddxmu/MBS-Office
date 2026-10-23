#import <AppKit/AppKit.h>
#import <Security/SecRandom.h>
#import <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#import "MbsLocalAccount.h"
#import "MbsEditorAuthorization.h"
#import "MbsBrandAppearance.h"

static NSString *MbsLoginURLString = @"https://ttys.ddxmu.com/api/mbs/login";
static NSString *MbsLogoutURLString = @"https://ttys.ddxmu.com/api/mbs/logout";
static NSString *MbsRegisterURLString = @"https://ttys.ddxmu.com/mbs/register";
static NSString *MbsVipURLString = @"https://ttys.ddxmu.com/mbs/vip";
// Store a revocable server session, never the account password. The private
// directory and file are accessible only to the current macOS user.
static int MbsAccountDirectory(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Mbs Office/Account"];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES
                                                  attributes:@{NSFilePosixPermissions: @0700} error:nil]) return -1;
    int directory = open(path.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    struct stat info;
    if (directory < 0) return -1;
    if (fstat(directory, &info) || info.st_uid != getuid() || fchmod(directory, 0700)) {
        close(directory);
        return -1;
    }
    return directory;
}

static NSDictionary *MbsLoadSession(void) {
    int directory = MbsAccountDirectory();
    if (directory < 0) return nil;
    int file = openat(directory, "session.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    close(directory);
    if (file < 0) return nil;
    struct stat info;
    char bytes[4096];
    ssize_t count = -1;
    if (!fstat(file, &info) && S_ISREG(info.st_mode) && info.st_uid == getuid() &&
        !(info.st_mode & 0077) && info.st_size > 0 && info.st_size < sizeof(bytes)) {
        count = read(file, bytes, sizeof(bytes));
    }
    close(file);
    if (count <= 0) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:count] options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static BOOL MbsSaveSession(NSString *email, NSString *token) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"email": email, @"token": token} options:0 error:nil];
    int directory = MbsAccountDirectory();
    if (directory < 0) return NO;
    if (!data) { close(directory); return NO; }
    NSString *temporary = [NSString stringWithFormat:@"session-%@.tmp", NSUUID.UUID.UUIDString];
    int file = openat(directory, temporary.UTF8String, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    BOOL saved = file >= 0 && write(file, data.bytes, data.length) == (ssize_t)data.length && fsync(file) == 0;
    if (file >= 0) close(file);
    if (saved) saved = renameat(directory, temporary.UTF8String, directory, "session.json") == 0;
    unlinkat(directory, temporary.UTF8String, 0);
    close(directory);
    return saved;
}

static void MbsDeleteSession(void) {
    int directory = MbsAccountDirectory();
    if (directory < 0) return;
    unlinkat(directory, "session.json", 0);
    close(directory);
}

static NSString *NormalizedEmail(NSString *email) {
    return [[email stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
}

static BOOL ValidEmail(NSString *email) {
    if (!email.length || email.length > 254) return NO;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^[A-Z0-9.!#$%&'*+/=?^_{|}~-]+@[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?(?:\\.[A-Z0-9](?:[A-Z0-9-]*[A-Z0-9])?)+$" options:NSRegularExpressionCaseInsensitive error:nil];
    return [pattern numberOfMatchesInString:email options:0 range:NSMakeRange(0, email.length)] == 1;
}

static BOOL ValidPassword(NSString *password) {
    __block NSUInteger count = 0;
    [password enumerateSubstringsInRange:NSMakeRange(0, password.length)
                                 options:NSStringEnumerationByComposedCharacterSequences
                              usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
        if (++count >= 8) *stop = YES;
    }];
    return count >= 8 && password.length <= 256;
}

static BOOL IsMbsURL(NSURL *url) {
    return url && [url.scheme.lowercaseString isEqualToString:@"https"] &&
           [url.host.lowercaseString isEqualToString:@"ttys.ddxmu.com"];
}

static BOOL MbsStringMeansVIP(NSString *value, BOOL *known) {
    NSString *normalized = value.lowercaseString;
    if ([normalized isEqualToString:@"vip"] || [normalized isEqualToString:@"svip"] ||
        [normalized isEqualToString:@"pro"] || [normalized isEqualToString:@"premium"] ||
        [normalized isEqualToString:@"paid"] || [normalized isEqualToString:@"member"] ||
        [normalized isEqualToString:@"会员"] || [normalized isEqualToString:@"vip会员"]) {
        if (known) *known = YES;
        return YES;
    }
    if ([normalized isEqualToString:@"free"] || [normalized isEqualToString:@"normal"] ||
        [normalized isEqualToString:@"user"] || [normalized isEqualToString:@"普通"] ||
        [normalized isEqualToString:@"普通会员"] || [normalized isEqualToString:@"未开通"]) {
        if (known) *known = YES;
        return NO;
    }
    return NO;
}

static BOOL MbsVIPStatusFromPayload(NSDictionary *payload, NSString **labelOut, BOOL *knownOut) {
    if (labelOut) *labelOut = nil;
    if (knownOut) *knownOut = NO;
    if (![payload isKindOfClass:NSDictionary.class]) return NO;

    id candidate = [payload[ @"user" ] isKindOfClass:NSDictionary.class] ? payload[@"user"] : payload;
    NSArray<NSString *> *booleanKeys = @[@"vip", @"isVip", @"is_vip", @"premium", @"isPremium",
                                         @"pro", @"isPro", @"paid", @"isPaid"];
    for (NSString *key in booleanKeys) {
        id value = [candidate[key] isKindOfClass:NSNumber.class] ? candidate[key] : payload[key];
        if ([value isKindOfClass:NSNumber.class]) {
            if (knownOut) *knownOut = YES;
            if (labelOut) *labelOut = [value boolValue] ? @"VIP 会员" : @"普通账号";
            return [value boolValue];
        }
    }

    id membership = [candidate[@"membership"] isKindOfClass:NSDictionary.class] ? candidate[@"membership"] : nil;
    if (membership) {
        for (NSString *key in booleanKeys) {
            id value = membership[key];
            if ([value isKindOfClass:NSNumber.class]) {
                if (knownOut) *knownOut = YES;
                if (labelOut) *labelOut = [value boolValue] ? @"VIP 会员" : @"普通账号";
                return [value boolValue];
            }
        }
        for (NSString *key in @[@"status", @"plan", @"level", @"name"]) {
            id value = membership[key];
            if ([value isKindOfClass:NSString.class]) {
                BOOL known = NO;
                BOOL vip = MbsStringMeansVIP(value, &known);
                if (known) {
                    if (knownOut) *knownOut = YES;
                    if (labelOut) *labelOut = vip ? @"VIP 会员" : @"普通账号";
                    return vip;
                }
            }
        }
    }

    for (NSString *key in @[@"plan", @"level", @"membershipStatus", @"membership_status", @"role"]) {
        id value = candidate[key] ?: payload[key];
        if ([value isKindOfClass:NSString.class]) {
            BOOL known = NO;
            BOOL vip = MbsStringMeansVIP(value, &known);
            if (known) {
                if (knownOut) *knownOut = YES;
                if (labelOut) *labelOut = vip ? @"VIP 会员" : @"普通账号";
                return vip;
            }
        }
    }
    return NO;
}

@interface MbsRedirectGuard : NSObject <NSURLSessionTaskDelegate>
@end

@implementation MbsRedirectGuard
- (void)URLSession:(NSURLSession *)session
              task:(NSURLSessionTask *)task
willPerformHTTPRedirection:(NSHTTPURLResponse *)response
        newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler {
    completionHandler(IsMbsURL(request.URL) ? request : nil);
}
@end

@interface MbsAccountPanel : NSPanel @end
@implementation MbsAccountPanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface MbsAccountBackdrop : NSView
@end
@implementation MbsAccountBackdrop
- (void)drawRect:(NSRect)dirtyRect {
    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.91 green:0.95 blue:1 alpha:1]
                                                       endingColor:[NSColor colorWithSRGBRed:0.94 green:0.91 blue:1 alpha:1]];
    [gradient drawInRect:self.bounds angle:70];
}
@end

@interface MbsAccountLogo : NSView
@property(nonatomic) BOOL busy;
@property(nonatomic, strong) NSTimer *animationTimer;
@property(nonatomic, strong) NSImage *image;
@end

@implementation MbsAccountLogo
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.image = MbsBrandArtwork();
        if (!self.image) self.image = [[NSImage alloc] initWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"MbsOffice" ofType:@"icns"]];
        self.accessibilityElement = YES;
        self.accessibilityLabel = @"Mbs Office";
    }
    return self;
}
- (void)setBusy:(BOOL)busy {
    _busy = busy;
    [self.animationTimer invalidate];
    self.animationTimer = nil;
    if (busy && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion) {
        __weak MbsAccountLogo *weakSelf = self;
        self.animationTimer = [NSTimer timerWithTimeInterval:1.0/24.0 repeats:YES block:^(NSTimer *timer) {
            weakSelf.needsDisplay = YES;
        }];
        [NSRunLoop.mainRunLoop addTimer:self.animationTimer forMode:NSRunLoopCommonModes];
    }
    self.needsDisplay = YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    NSRect icon = NSInsetRect(self.bounds,12,12);
    if (self.busy && self.animationTimer) icon.origin.y += sin(NSProcessInfo.processInfo.systemUptime*2)*4;
    if (self.image && self.image == MbsBrandArtwork()) MbsDrawBrandRobot(icon);
    else if (self.image) [self.image drawInRect:icon];
    else {
        [NSColor.systemBlueColor setFill];
        [[NSBezierPath bezierPathWithRoundedRect:icon xRadius:12 yRadius:12] fill];
        [@"M" drawAtPoint:NSMakePoint(22,19) withAttributes:@{NSFontAttributeName:[NSFont boldSystemFontOfSize:32], NSForegroundColorAttributeName:NSColor.whiteColor}];
    }
    if (self.busy) {
        for (int index=0;index<3;++index) {
            CGFloat alpha = self.animationTimer ? 0.35+0.65*(sin(NSProcessInfo.processInfo.systemUptime*4-index)+1)/2 : 0.7;
            [[NSColor.systemBlueColor colorWithAlphaComponent:alpha] setFill];
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(NSMidX(self.bounds)-19+index*14,4,8,8)] fill];
        }
    }
}
- (void)dealloc { [self.animationTimer invalidate]; }
@end

@interface MbsLocalAccountController : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) MbsAccountLogo *logo;
@property(nonatomic, strong) NSSegmentedControl *mode;
@property(nonatomic, strong) NSTextField *email;
@property(nonatomic, strong) NSSecureTextField *password;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *submit;
@property(nonatomic, strong) NSButton *retry;
@property(nonatomic, strong) NSButton *webLogin;
@property(nonatomic, strong) NSButton *remember;
@property(nonatomic, strong) NSDate *lastWebLogin;
@property(nonatomic, strong) NSURLSession *webSession;
@property(nonatomic, strong) NSURLSessionDataTask *webTask;
@property(nonatomic, strong) NSTimer *webPollTimer;
@property(nonatomic, strong) NSDate *webDeadline;
@property(nonatomic, copy) NSString *webFlow;
@property(nonatomic, copy) NSString *webVerifier;
@property(nonatomic, copy) NSString *sessionEmail;
@property(nonatomic, copy) NSString *sessionToken;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) MbsRedirectGuard *redirectGuard;
@property(nonatomic, strong) NSPanel *statusPanel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, weak) NSWindow *statusHostWindow;
@property(nonatomic, strong) NSTextField *statusView;
@property(nonatomic, strong) NSTimer *statusDismissTimer;
@property(nonatomic, assign) BOOL vip;
/// 服务端下发的免费额度上限；仅约束 Mbs 自有 AI 功能。
@property(nonatomic, assign) NSInteger dailyFreeLimit;
@property(nonatomic, copy) NSString *membershipLabel;
@property(nonatomic, strong) NSPanel *accountPanel;
@property(nonatomic, strong) NSTextField *activationCode, *activationSummary;
@property(nonatomic, strong) NSButton *activationButton;
@property(nonatomic, strong) NSTextField *accountPanelEmail;
@property(nonatomic, strong) NSTextField *accountPanelMembership;
@property(nonatomic, strong) NSTextField *accountPanelAuthorization;
@property(nonatomic, strong) NSDictionary *deferredSession;
@property(nonatomic, strong) NSButton *accountPanelUpgrade;
@property(nonatomic, strong) NSButton *accountPanelLogout;
@property(nonatomic, weak) NSWindow *accountHostWindow;
@property(nonatomic, strong) NSTimer *membershipTimer;
@property(nonatomic, strong) NSURLSessionDataTask *membershipTask;
@property(nonatomic, strong) NSDate *membershipLastRefresh;
@property(nonatomic, assign) BOOL restoringSession;
+ (instancetype)shared;
- (void)show;
- (void)showForStartup;
- (void)showLoginForm;
- (void)startSession;
- (void)didSignInWithToken:(NSString *)token user:(NSDictionary *)user notify:(BOOL)notify;
- (void)submit:(id)sender;
- (void)changeMode:(id)sender;
- (void)logout:(id)sender;
- (void)refreshMembership:(BOOL)force;
- (void)showAccountPopoverForWindow:(NSWindow *)window point:(NSPoint)point;
- (void)hideAccountPopover;
- (void)openVip:(id)sender;
- (void)openWebLogin:(id)sender;
- (BOOL)openWebLoginPage:(NSURL *)url;
- (void)pollWebLogin:(id)sender;
- (void)cancelWebLogin;
- (void)deferLogin:(id)sender;
- (void)retryConnection:(id)sender;
- (void)postAccountChange;
- (void)authorizationChanged:(NSNotification *)note;
- (void)redeemActivationCode:(id)sender;
- (void)updateActivationState:(NSDictionary *)state;
@end

static NSTextField *AccountLabel(NSView *view, NSString *text, NSRect frame) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.frame = frame;
    [view addSubview:label];
    return label;
}

@implementation MbsLocalAccountController

+ (instancetype)shared {
    static MbsLocalAccountController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        controller = [MbsLocalAccountController new];
        controller.dailyFreeLimit = 3;
        [[NSNotificationCenter defaultCenter] addObserver:controller selector:@selector(authorizationChanged:)
            name:@"MbsEditorAuthorizationDidChange" object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:controller selector:@selector(applicationResignedActive:)
            name:NSApplicationDidResignActiveNotification object:nil];
    });
    return controller;
}

- (void)startSession {
    [self ensureAccountMenu];
    if (self.restoringSession || self.session) return;
    self.deferredSession = nil;
    NSDictionary *saved = MbsLoadSession();
    NSString *token = [saved[@"token"] isKindOfClass:NSString.class] ? saved[@"token"] : nil;
    NSString *email = [saved[@"email"] isKindOfClass:NSString.class] ? saved[@"email"] : nil;
    if (token.length < 32 || token.length > 128 || !ValidEmail(email)) {
        MbsDeleteSession();
        [self showForStartup];
        return;
    }
    [self prepareWindow];
    self.email.stringValue = email;
    self.remember.state = NSControlStateValueOn;
    self.restoringSession = YES;
    [self setBusy:YES];
    self.status.stringValue = @"正在验证已保存的登录状态…";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://ttys.ddxmu.com/api/mbs/me"]];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 15.0;
    configuration.timeoutIntervalForResource = 30.0;
    self.session = [NSURLSession sessionWithConfiguration:configuration delegate:[MbsRedirectGuard new]
                                           delegateQueue:NSOperationQueue.mainQueue];
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *user = [payload[@"user"] isKindOfClass:NSDictionary.class] ? payload[@"user"] : nil;
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        self.restoringSession = NO;
        if (!error && IsMbsURL(response.URL) && code == 200 && [payload[@"ok"] boolValue] &&
            [user[@"email"] isKindOfClass:NSString.class] && ValidEmail(user[@"email"]) &&
            [NormalizedEmail(user[@"email"]) isEqualToString:NormalizedEmail(email)]) {
            [self didSignInWithToken:token user:user notify:NO];
        } else {
            BOOL expired = code == 401 || code == 403;
            BOOL unavailable = error || code >= 500 || code == 408 || code == 429;
            if (expired) {
                MbsResetEditorLicense();
                MbsDeleteSession();
            } else if (unavailable && MbsCanRestoreAccountSession(token.UTF8String,email.UTF8String)) {
                self.deferredSession = saved;
            }
            [self showForStartup];
            self.retry.hidden = expired;
            self.webLogin.hidden = !self.retry.hidden;
            self.status.stringValue = expired ? @"登录状态已过期，请重新输入密码。" :
                (self.deferredSession ? @"连接暂时不可用。点击“稍后登录”可保留有效的 Mbs 账号授权，恢复联网后会重新验证。" : @"连接暂时不可用，请重试。当前没有可恢复的 Mbs 账号授权。");
        }
        [self setBusy:NO];
        [self.session finishTasksAndInvalidate];
        self.session = nil;
    }] resume];
}

- (void)didSignInWithToken:(NSString *)token user:(NSDictionary *)user notify:(BOOL)notify {
    [self cancelWebLogin];
    self.sessionToken = token;
    self.sessionEmail = user[@"email"];
    self.deferredSession = nil;
    self.retry.hidden = YES;
    self.webLogin.hidden = NO;
    MbsRequestEditorLicense(token.UTF8String,self.sessionEmail.UTF8String);
    self.password.stringValue = @"";
    self.status.stringValue = [NSString stringWithFormat:@"已登录：%@", self.sessionEmail];
    [self.window orderOut:nil];
    [self.window resignKeyWindow];

    BOOL known = NO;
    NSString *label = nil;
    self.vip = MbsVIPStatusFromPayload(@{@"user": user}, &label, &known);
    self.membershipLabel = known ? label : @"会员状态同步中…";
    [self.membershipTimer invalidate];
    self.membershipTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self
                                                        selector:@selector(membershipTimerFired:)
                                                        userInfo:nil repeats:YES];
    [self postAccountChange];
    [self refreshMembership:YES];
    if (notify) [self showStatusPanel];
}

- (void)hideStatusPanel {
    [self.statusDismissTimer invalidate];
    self.statusDismissTimer = nil;
    [self.statusPanel orderOut:nil];
    [self.statusView removeFromSuperview];
    self.statusHostWindow = nil;
}

- (void)showStatusPanel {
    if (!NSApp.isActive) { [self hideStatusPanel]; return; }
    if (!self.sessionEmail.length) {
        [self hideStatusPanel];
        return;
    }
    if (!self.statusPanel) {
        self.statusPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 220, 24)
                                                        styleMask:NSWindowStyleMaskBorderless
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        self.statusPanel.level = NSNormalWindowLevel;
        self.statusPanel.hidesOnDeactivate = YES;
        self.statusPanel.opaque = NO;
        self.statusPanel.backgroundColor = NSColor.clearColor;
        self.statusPanel.hasShadow = YES;
        self.statusPanel.ignoresMouseEvents = YES;
        self.statusPanel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
        NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:self.statusPanel.contentView.bounds];
        background.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        background.material = NSVisualEffectMaterialHeaderView;
        background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        background.state = NSVisualEffectStateActive;
        background.wantsLayer = YES;
        background.layer.cornerRadius = 5.0;
        [self.statusPanel.contentView addSubview:background];
        self.statusLabel = [NSTextField labelWithString:@""];
        self.statusLabel.alignment = NSTextAlignmentCenter;
        self.statusLabel.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium];
        self.statusLabel.frame = NSMakeRect(6, 5, 208, 14);
        [self.statusPanel.contentView addSubview:self.statusLabel];
    }
    NSWindow *main = nil;
    for (NSWindow *candidate in NSApp.windows) {
        if (candidate != self.window && candidate != self.statusPanel && candidate.isVisible &&
            candidate.frame.size.width > 600 && candidate.frame.size.height > 300) {
            main = candidate;
            break;
        }
    }
    self.statusLabel.stringValue = [NSString stringWithFormat:@"已登录：%@", self.sessionEmail];
    NSRect target = main ? main.frame : NSScreen.mainScreen.visibleFrame;
    NSRect frame = self.statusPanel.frame;
    frame.origin.x = NSMaxX(target) - frame.size.width - 24;
    frame.origin.y = NSMaxY(target) - frame.size.height - 68;
    [self.statusPanel setFrame:frame display:NO];
    if (main && self.statusPanel.parentWindow != main) {
        [self.statusPanel.parentWindow removeChildWindow:self.statusPanel];
        [main addChildWindow:self.statusPanel ordered:NSWindowAbove];
    }
    [self.statusPanel orderFront:nil];
    [self.statusDismissTimer invalidate];
    self.statusDismissTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                                 target:self
                                                               selector:@selector(hideStatusPanel)
                                                               userInfo:nil
                                                                repeats:NO];
}

- (void)hideAccountPopover {
    [self.accountPanel orderOut:nil];
    if (self.accountHostWindow && [self.accountHostWindow.childWindows containsObject:self.accountPanel]) {
        [self.accountHostWindow removeChildWindow:self.accountPanel];
    }
    self.accountHostWindow = nil;
}

- (void)ensureAccountPopover {
    if (self.accountPanel) return;
    self.accountPanel = [[MbsAccountPanel alloc] initWithContentRect:NSMakeRect(0, 0, 368, 384)
                                                     styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
    self.accountPanel.releasedWhenClosed = NO;
    self.accountPanel.level = NSNormalWindowLevel;
    self.accountPanel.opaque = NO;
    self.accountPanel.backgroundColor = NSColor.clearColor;
    self.accountPanel.hasShadow = YES;
    self.accountPanel.hidesOnDeactivate = YES;
    self.accountPanel.ignoresMouseEvents = NO;
    self.accountPanel.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;

    NSVisualEffectView *background = [[NSVisualEffectView alloc] initWithFrame:self.accountPanel.contentView.bounds];
    background.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    background.material = NSVisualEffectMaterialPopover;
    background.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    background.state = NSVisualEffectStateActive;
    background.wantsLayer = YES;
    background.layer.cornerRadius = 14.0;
    background.layer.masksToBounds = YES;
    [self.accountPanel.contentView addSubview:background];

    NSTextField *title = [NSTextField labelWithString:@"Mbs Office 账号"];
    title.font = [NSFont systemFontOfSize:18.0 weight:NSFontWeightSemibold];
    title.frame = NSMakeRect(24, 338, 320, 24);
    [self.accountPanel.contentView addSubview:title];

    self.accountPanelEmail = [NSTextField labelWithString:@""];
    self.accountPanelEmail.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightMedium];
    self.accountPanelEmail.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.accountPanelEmail.frame = NSMakeRect(24, 303, 320, 22);
    [self.accountPanel.contentView addSubview:self.accountPanelEmail];

    self.accountPanelMembership = [NSTextField labelWithString:@""];
    self.accountPanelMembership.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.accountPanelMembership.textColor = NSColor.secondaryLabelColor;
    self.accountPanelMembership.frame = NSMakeRect(24, 268, 320, 22);
    [self.accountPanel.contentView addSubview:self.accountPanelMembership];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(24, 249, 320, 1)];
    separator.boxType = NSBoxSeparator;
    [self.accountPanel.contentView addSubview:separator];

    self.accountPanelUpgrade = [NSButton buttonWithTitle:@"立即升级" target:self action:@selector(openVip:)];
    self.accountPanelUpgrade.frame = NSMakeRect(24, 193, 320, 38);
    self.accountPanelUpgrade.bezelStyle = NSBezelStyleRounded;
    [self.accountPanel.contentView addSubview:self.accountPanelUpgrade];

    self.activationCode = [NSTextField textFieldWithString:@""];
    self.activationCode.placeholderString = @"输入 Mbs 授权码";
    self.activationCode.accessibilityLabel = @"Mbs 授权码";
    self.activationCode.frame = NSMakeRect(24, 139, 226, 28);
    [self.accountPanel.contentView addSubview:self.activationCode];
    self.activationButton = [NSButton buttonWithTitle:@"激活" target:self action:@selector(redeemActivationCode:)];
    self.activationButton.bezelStyle = NSBezelStyleRounded;
    self.activationButton.frame = NSMakeRect(258, 137, 86, 32);
    [self.accountPanel.contentView addSubview:self.activationButton];
    self.activationSummary = [NSTextField labelWithString:@"可由管理员为当前账号生成授权码"];
    self.activationSummary.font = [NSFont systemFontOfSize:11];
    self.activationSummary.textColor = NSColor.secondaryLabelColor;
    self.activationSummary.frame = NSMakeRect(24, 102, 320, 22);
    [self.accountPanel.contentView addSubview:self.activationSummary];

    self.accountPanelLogout = [NSButton buttonWithTitle:@"退出登录" target:self action:@selector(logout:)];
    self.accountPanelLogout.frame = NSMakeRect(24, 52, 320, 30);
    self.accountPanelLogout.bezelStyle = NSBezelStyleTexturedRounded;
    [self.accountPanel.contentView addSubview:self.accountPanelLogout];

    self.accountPanelAuthorization = [NSTextField wrappingLabelWithString:@"授权状态待验证"];
    NSTextField *hint = self.accountPanelAuthorization;
    hint.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    hint.textColor = NSColor.tertiaryLabelColor;
    hint.frame = NSMakeRect(24, 10, 320, 34);
    [self.accountPanel.contentView addSubview:hint];
}

- (void)showAccountPopoverForWindow:(NSWindow *)window point:(NSPoint)point {
    if (!self.sessionEmail.length || !window || !NSApp.isActive) {
        [self hideAccountPopover];
        return;
    }
    [self ensureAccountPopover];
    self.accountHostWindow = window;
    self.accountPanelEmail.stringValue = self.sessionEmail;
    self.accountPanelMembership.stringValue = self.membershipLabel.length ? self.membershipLabel : @"会员状态同步中…";
    self.accountPanelUpgrade.title = self.vip ? @"已是 VIP 会员" : @"立即升级";
    self.accountPanelUpgrade.enabled = !self.vip;
    self.accountPanelLogout.enabled = YES;
    char *authorization = MbsCopyEditorAuthorizationState();
    NSDictionary *grant = authorization ? [NSJSONSerialization JSONObjectWithData:
        [[NSString stringWithUTF8String:authorization] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil] : nil;
    free(authorization);
    [self updateActivationState:grant];

    NSPoint screenPoint = [window convertPointToScreen:point];
    NSRect frame = self.accountPanel.frame;
    NSScreen *screen = window.screen ?: NSScreen.mainScreen;
    NSRect visible = screen.visibleFrame;
    frame.origin.x = screenPoint.x - frame.size.width + 42.0;
    frame.origin.y = screenPoint.y - frame.size.height - 8.0;
    frame.origin.x = MAX(NSMinX(visible) + 8.0, MIN(NSMaxX(visible) - frame.size.width - 8.0, frame.origin.x));
    frame.origin.y = MAX(NSMinY(visible) + 8.0, MIN(NSMaxY(visible) - frame.size.height - 8.0, frame.origin.y));
    [self.accountPanel setFrame:frame display:NO];
    if (self.accountPanel.parentWindow != window) {
        [self.accountPanel.parentWindow removeChildWindow:self.accountPanel];
        [window addChildWindow:self.accountPanel ordered:NSWindowAbove];
    }
    [self.accountPanel orderFront:nil];
    [self refreshMembership:NO];
}

- (void)postAccountChange {
    NSDictionary *info = @{
        @"signedIn": @(self.sessionEmail.length > 0),
        @"email": self.sessionEmail ?: @"",
        @"isVip": @(self.vip),
        @"plan": self.vip ? @"vip" : @"free",
        @"dailyFreeLimit": @(self.dailyFreeLimit),
        @"membershipLabel": self.membershipLabel ?: @"会员状态待同步"
    };
    [[NSNotificationCenter defaultCenter] postNotificationName:@"MbsLocalAccountDidChange"
                                                        object:nil
                                                      userInfo:info];
}

- (void)authorizationChanged:(NSNotification *)note {
    if (!self.sessionEmail.length) return;
    [self updateActivationState:note.userInfo];
}
- (void)updateActivationState:(NSDictionary *)state {
    NSString *status = state[@"status"] ?: @"授权状态待验证";
    if ([status isEqual:@"授权码已激活"]) status = @"Mbs 账号授权码已验证";
    if ([status isEqual:@"Mbs 授权已验证"]) status = @"Mbs 账号授权已验证";
    // The Mbs grant and the native probe do not establish an editor license.
    BOOL editorUnverified = [state[@"verified"] boolValue] && ![state[@"originalVendorLicense"] boolValue];
    self.accountPanelAuthorization.stringValue = editorUnverified ?
        [status stringByAppendingString:@"\n编辑器许可未验证，当前授权不代表编辑功能可用。"] : status;
    self.accountPanelAuthorization.textColor = editorUnverified ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor;
    self.activationButton.enabled = ![state[@"busy"] boolValue];
    NSDictionary *activation = [state[@"activation"] isKindOfClass:NSDictionary.class] ? state[@"activation"] : nil;
    if ([state[@"verified"] boolValue] && activation) {
        NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"yyyy-MM-dd";
        NSString *date = [format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[activation[@"expiresAt"] doubleValue]]];
        self.activationSummary.stringValue = [NSString stringWithFormat:@"%@ · 有效至 %@",
            [activation[@"plan"] isEqual:@"vip"] ? @"Mbs 账号 VIP 授权" : @"Mbs 账号标准授权",date];
        if ([state[@"status"] isEqual:@"授权码已激活"]) self.activationCode.stringValue = @"";
    } else self.activationSummary.stringValue = @"输入新授权码激活，或点击激活同步网站续期";
    self.activationButton.title = [state[@"busy"] boolValue] ? @"连接中…" : @"激活";
}
- (void)redeemActivationCode:(id)sender {
    if (!self.sessionEmail.length) return;
    self.activationButton.enabled = NO;
    NSString *code = [self.activationCode.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (code.length) MbsRedeemActivationCode(code.UTF8String);
    else MbsRequestEditorLicense(self.sessionToken.UTF8String,self.sessionEmail.UTF8String);
}

- (void)refreshMembership:(BOOL)force {
    if (!self.sessionEmail.length || !self.sessionToken.length) {
        self.vip = NO;
        self.membershipLabel = @"未登录";
        [self postAccountChange];
        return;
    }
    if (!force && (self.membershipTask || (self.membershipLastRefresh &&
                                           -[self.membershipLastRefresh timeIntervalSinceNow] < 10.0))) {
        return;
    }
    self.membershipLastRefresh = [NSDate date];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://ttys.ddxmu.com/api/mbs/me"]];
    request.HTTPMethod = @"GET";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", self.sessionToken] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    MbsRedirectGuard *guard = [MbsRedirectGuard new];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 15.0;
    configuration.timeoutIntervalForResource = 30.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:guard delegateQueue:[NSOperationQueue mainQueue]];
    __weak MbsLocalAccountController *weakSelf = self;
    self.membershipTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        MbsLocalAccountController *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSDictionary *payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        BOOL known = NO;
        NSString *label = nil;
        BOOL vip = MbsVIPStatusFromPayload(payload, &label, &known);
        NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (!error && IsMbsURL(response.URL) && statusCode >= 200 && statusCode < 300 && [payload[@"ok"] boolValue]) {
            strongSelf.vip = known && vip;
            // 服务端可下发免费额度上限，用于 Mbs 自有 AI 功能。
            id limitValue = payload[@"dailyFreeLimit"];
            if (![limitValue isKindOfClass:NSNumber.class]) {
                limitValue = payload[@"user"][@"dailyFreeLimit"];
            }
            if ([limitValue isKindOfClass:NSNumber.class] && [limitValue integerValue] >= 0) {
                strongSelf.dailyFreeLimit = [limitValue integerValue];
            }
            strongSelf.membershipLabel = known ? (label ?: (strongSelf.vip ? @"VIP 会员" : @"普通账号")) : @"会员状态待同步";
        } else if (statusCode == 401 || statusCode == 403) {
            MbsResetEditorLicense();
            MbsDeleteSession();
            strongSelf.sessionToken = nil;
            strongSelf.sessionEmail = nil;
            strongSelf.vip = NO;
            [strongSelf.membershipTimer invalidate];
            strongSelf.membershipTimer = nil;
            strongSelf.membershipLabel = @"登录状态已失效";
            [strongSelf hideStatusPanel];
        } else if (!known) {
            strongSelf.membershipLabel = @"会员状态待同步";
        }
        strongSelf.membershipTask = nil;
        [session finishTasksAndInvalidate];
        [strongSelf postAccountChange];
        if (strongSelf.accountPanel.isVisible) {
            strongSelf.accountPanelMembership.stringValue = strongSelf.membershipLabel;
            strongSelf.accountPanelUpgrade.title = strongSelf.vip ? @"已是 VIP 会员" : @"立即升级";
            strongSelf.accountPanelUpgrade.enabled = !strongSelf.vip;
        }
    }];
    [self.membershipTask resume];
}

- (void)openVip:(id)sender {
    NSURLComponents *components = [NSURLComponents componentsWithString:MbsVipURLString];
    if (self.sessionToken.length) {
        NSString *escapedToken = [self.sessionToken stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
        components.fragment = [NSString stringWithFormat:@"mbs_session=%@", escapedToken ?: @""];
    }
    NSURL *url = components.URL ?: [NSURL URLWithString:MbsVipURLString];
    if (![[NSWorkspace sharedWorkspace] openURL:url]) {
        self.membershipLabel = @"无法打开升级页面";
        [self postAccountChange];
        return;
    }
    self.membershipLabel = @"等待会员状态同步…";
    self.accountPanelMembership.stringValue = self.membershipLabel;
    [self refreshMembership:YES];
    __weak MbsLocalAccountController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf refreshMembership:YES];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf refreshMembership:YES];
    });
}

- (void)membershipTimerFired:(NSTimer *)timer {
    [self ensureAccountMenu];
    [self refreshMembership:NO];
}

- (void)ensureAccountMenu {
    NSMenu *menu = [NSApp.mainMenu itemWithTitle:@"账号"].submenu;
    if (!menu || [menu itemWithTitle:@"Mbs 账号与授权…"]) return;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Mbs 账号与授权…" action:@selector(show) keyEquivalent:@""];
    item.target = self;
    [menu insertItem:item atIndex:0];
    [menu insertItem:NSMenuItem.separatorItem atIndex:1];
}

- (void)applicationResignedActive:(NSNotification *)note {
    [self hideStatusPanel];
    [self hideAccountPopover];
}

- (void)showForStartup {
    [self prepareWindow];
    if (NSApp.isActive) [self show];
}

- (void)show {
    // A successful login is already reflected in the main window. Opening the
    // account entry again must not bring the login form back over the editor.
    if (self.sessionEmail.length) {
        [self postAccountChange];
        [self.window orderOut:nil];
        [self.window resignKeyWindow];
        [self hideStatusPanel];
        NSWindow *host = NSApp.mainWindow;
        if (!host || host == self.window) {
            for (NSWindow *candidate in NSApp.windows) {
                if (candidate != self.window && candidate.isVisible &&
                    candidate.frame.size.width>600 && candidate.frame.size.height>300) { host = candidate; break; }
            }
        }
        if (host && host != self.window) {
            NSRect bounds = host.contentView.bounds;
            [self showAccountPopoverForWindow:host point:NSMakePoint(NSMaxX(bounds)-32,NSMaxY(bounds)-64)];
        }
        return;
    }
    [self prepareWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)showLoginForm {
    [self prepareWindow];
    self.mode.selectedSegment = 0;
    [self changeMode:nil];
    [self hideAccountPopover];
    [self hideStatusPanel];
    if (self.sessionEmail.length) {
        self.email.stringValue = self.sessionEmail;
        self.password.stringValue = @"";
        self.status.stringValue = [NSString stringWithFormat:@"当前账号：%@",self.sessionEmail];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.password.stringValue.length ? self.email :
        (self.email.stringValue.length ? self.password : self.email)];
}

- (void)prepareWindow {
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 500)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        self.window.title = @"Mbs Office 账号";
        self.window.releasedWhenClosed = NO;
        self.window.delegate = self;
        self.window.level = NSNormalWindowLevel;
        self.window.hidesOnDeactivate = YES;
        [self.window center];

        NSView *view = self.window.contentView;
        MbsAccountBackdrop *backdrop = [[MbsAccountBackdrop alloc] initWithFrame:NSMakeRect(0,0,310,500)];
        [view addSubview:backdrop];
        NSTextField *brand = AccountLabel(backdrop, @"Mbs Office", NSMakeRect(30,425,250,36));
        brand.font = MbsBrandFont(29);
        brand.textColor = MbsBrandInk();
        NSTextField *tagline = AccountLabel(backdrop, @"让灵感连接每一份文档", NSMakeRect(30,392,250,26));
        tagline.textColor = NSColor.secondaryLabelColor;
        self.logo = [[MbsAccountLogo alloc] initWithFrame:NSMakeRect(15,112,280,280)];
        [backdrop addSubview:self.logo];
        NSTextField *caption = AccountLabel(backdrop, @"文字 · 表格 · 演示 · AI 助手", NSMakeRect(24,62,262,24));
        caption.alignment = NSTextAlignmentCenter;
        caption.font = [NSFont systemFontOfSize:13];
        caption.textColor = [NSColor colorWithSRGBRed:0.32 green:0.37 blue:0.55 alpha:1];

        NSView *form = [[NSView alloc] initWithFrame:NSMakeRect(350,0,410,500)];
        [view addSubview:form];
        NSTextField *title = AccountLabel(form, @"欢迎回来", NSMakeRect(0,435,410,34));
        title.font = [NSFont boldSystemFontOfSize:25];
        NSTextField *subtitle = AccountLabel(form, @"登录 Mbs 账号，同步你的个人工作空间。", NSMakeRect(0,398,410,28));
        subtitle.textColor = NSColor.secondaryLabelColor;
        subtitle.font = [NSFont systemFontOfSize:13];
        self.mode = [NSSegmentedControl segmentedControlWithLabels:@[@"登录", @"注册"]
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self action:@selector(changeMode:)];
        self.mode.frame = NSMakeRect(0,350,410,30);
        self.mode.selectedSegment = 0;
        [form addSubview:self.mode];

        AccountLabel(form, @"邮箱", NSMakeRect(0,317,410,22));
        self.email = [[NSTextField alloc] initWithFrame:NSMakeRect(0,282,410,30)];
        self.email.placeholderString = @"name@example.com";
        self.email.font = [NSFont systemFontOfSize:15];
        [form addSubview:self.email];
        AccountLabel(form, @"密码", NSMakeRect(0,246,410,22));
        self.password = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0,211,410,30)];
        self.password.placeholderString = @"至少 8 个字符";
        self.password.font = [NSFont systemFontOfSize:15];
        [form addSubview:self.password];
        self.remember = [NSButton checkboxWithTitle:@"保持登录状态（30 天）" target:nil action:nil];
        self.remember.frame = NSMakeRect(0,173,240,24);
        self.remember.state = NSControlStateValueOn;
        [form addSubview:self.remember];
        NSTextField *privacy = AccountLabel(form, @"保存安全会话，不保存账号密码。", NSMakeRect(0,148,410,22));
        privacy.font = [NSFont systemFontOfSize:12];
        privacy.textColor = NSColor.secondaryLabelColor;
        self.status = AccountLabel(form, @"", NSMakeRect(0,82,410,58));
        self.status.font = [NSFont systemFontOfSize:13];
        self.status.textColor = NSColor.secondaryLabelColor;

        self.submit = [NSButton buttonWithTitle:@"登录" target:self action:@selector(submit:)];
        self.submit.frame = NSMakeRect(280,28,130,34);
        self.submit.bezelStyle = NSBezelStyleRounded;
        self.submit.keyEquivalent = @"\r";
        [form addSubview:self.submit];
        self.webLogin = [NSButton buttonWithTitle:@"网页登录" target:self action:@selector(openWebLogin:)];
        self.webLogin.frame = NSMakeRect(133,28,130,34);
        self.webLogin.bezelStyle = NSBezelStyleRounded;
        [form addSubview:self.webLogin];
        self.retry = [NSButton buttonWithTitle:@"重试连接" target:self action:@selector(retryConnection:)];
        self.retry.frame = self.webLogin.frame;
        self.retry.bezelStyle = NSBezelStyleRounded;
        self.retry.hidden = YES;
        [form addSubview:self.retry];
        NSButton *later = [NSButton buttonWithTitle:@"稍后登录" target:self action:@selector(deferLogin:)];
        later.frame = NSMakeRect(0,28,116,34);
        later.bezelStyle = NSBezelStyleRounded;
        [form addSubview:later];
        [self changeMode:nil];
    }
}

- (void)changeMode:(id)sender {
    BOOL registering = self.mode.selectedSegment == 1;
    self.submit.title = registering ? @"打开注册页面" : @"登录";
    self.status.stringValue = registering
        ? @"点击“打开注册页面”完成注册，注册后返回此窗口登录。"
        : (self.sessionEmail.length ? [NSString stringWithFormat:@"已登录：%@", self.sessionEmail] : @"未登录。登录只连接 Mbs Office 账号服务。");
}

- (void)openWebLogin:(id)sender {
    if (self.sessionEmail.length || self.restoringSession || self.session) return;
    if (self.webSession) {
        self.status.stringValue = @"正在等待网页登录，请在已打开的页面完成登录。";
        return;
    }
    if (self.lastWebLogin && -self.lastWebLogin.timeIntervalSinceNow < 5.0) return;
    self.lastWebLogin = NSDate.date;
    unsigned char bytes[32], digest[CC_SHA256_DIGEST_LENGTH];
    if (SecRandomCopyBytes(kSecRandomDefault, sizeof(bytes), bytes) != errSecSuccess) {
        self.status.stringValue = @"无法创建安全登录连接，请使用邮箱和密码登录。";
        return;
    }
    NSString *verifier = [[NSData dataWithBytes:bytes length:sizeof(bytes)] base64EncodedStringWithOptions:0];
    verifier = [[[verifier stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
                 stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@"=" withString:@""];
    self.webVerifier = verifier;
    CC_SHA256(verifier.UTF8String, (CC_LONG)[verifier lengthOfBytesUsingEncoding:NSUTF8StringEncoding], digest);
    NSMutableString *challenge = [NSMutableString string];
    for (unsigned char byte : digest) [challenge appendFormat:@"%02x", byte];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 15;
    configuration.timeoutIntervalForResource = 20;
    self.webSession = [NSURLSession sessionWithConfiguration:configuration delegate:[MbsRedirectGuard new]
                                              delegateQueue:NSOperationQueue.mainQueue];
    NSURLSession *session = self.webSession;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://ttys.ddxmu.com/api/mbs/desktop/start"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"challenge": challenge} options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    self.status.stringValue = @"正在创建网页登录连接…";
    __weak MbsLocalAccountController *weakSelf = self;
    self.webTask = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        MbsLocalAccountController *controller = weakSelf;
        if (!controller || controller.webSession != session) return;
        controller.webTask = nil;
        id payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSString *flow = [payload isKindOfClass:NSDictionary.class] && [payload[@"flow"] isKindOfClass:NSString.class] ? payload[@"flow"] : nil;
        NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_-]{43}$" options:0 error:nil];
        if (error || !IsMbsURL(response.URL) || code != 200 || ![payload isKindOfClass:NSDictionary.class] || ![payload[@"ok"] boolValue] ||
            !flow || [pattern numberOfMatchesInString:flow options:0 range:NSMakeRange(0, flow.length)] != 1) {
            [controller cancelWebLogin];
            controller.status.stringValue = @"网页登录连接不可用，请使用邮箱和密码登录，或稍后重试。";
            return;
        }
        controller.webFlow = flow;
        controller.webDeadline = [NSDate dateWithTimeIntervalSinceNow:300];
        NSURLComponents *components = [NSURLComponents componentsWithString:@"https://ttys.ddxmu.com/mbs/login"];
        components.fragment = [@"desktop_flow=" stringByAppendingString:flow];
        if (![controller openWebLoginPage:components.URL]) {
            [controller cancelWebLogin];
            controller.status.stringValue = @"无法打开网页登录页面，请稍后重试。";
            return;
        }
        controller.status.stringValue = @"请在网页完成登录，成功后将自动连接到 Mbs Office。";
        controller.webPollTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:controller
                selector:@selector(pollWebLogin:) userInfo:nil repeats:YES];
    }];
    [self.webTask resume];
}

- (BOOL)openWebLoginPage:(NSURL *)url {
    return [[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)pollWebLogin:(id)sender {
    if (self.webDeadline.timeIntervalSinceNow <= 0) {
        [self cancelWebLogin];
        self.status.stringValue = @"网页登录连接已过期，请重新点击“网页登录”或使用邮箱和密码登录。";
        return;
    }
    if (!self.webFlow.length || self.webTask) return;
    NSString *flow = self.webFlow;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://ttys.ddxmu.com/api/mbs/desktop/poll"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:@{@"flow": flow, @"verifier": self.webVerifier} options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    __weak MbsLocalAccountController *weakSelf = self;
    self.webTask = [self.webSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        MbsLocalAccountController *controller = weakSelf;
        if (!controller || ![controller.webFlow isEqualToString:flow]) return;
        controller.webTask = nil;
        if (error) {
            controller.status.stringValue = @"网页登录连接暂时中断，正在重试…";
            return;
        }
        id payload = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSInteger code = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        if (!IsMbsURL(response.URL) || ![payload isKindOfClass:NSDictionary.class] || code != 200 || ![payload[@"ok"] boolValue]) {
            [controller cancelWebLogin];
            controller.status.stringValue = @"网页登录连接已失效，请重新发起登录。";
            return;
        }
        if ([payload[@"status"] isEqual:@"pending"]) return;
        NSString *token = [payload[@"token"] isKindOfClass:NSString.class] ? payload[@"token"] : nil;
        NSDictionary *user = [payload[@"user"] isKindOfClass:NSDictionary.class] ? payload[@"user"] : nil;
        if (![payload[@"status"] isEqual:@"complete"] || token.length < 32 || token.length > 128 ||
            ![user[@"email"] isKindOfClass:NSString.class] || !ValidEmail(user[@"email"])) {
            [controller cancelWebLogin];
            controller.status.stringValue = @"账号服务返回内容不正确，请重新登录。";
            return;
        }
        BOOL saved = YES;
        if (controller.remember.state == NSControlStateValueOn) saved = MbsSaveSession(user[@"email"], token);
        if (controller.remember.state != NSControlStateValueOn || !saved) MbsDeleteSession();
        [controller didSignInWithToken:token user:user notify:YES];
        if (!saved) {
            if (NSApp.isActive) [controller.window makeKeyAndOrderFront:nil];
            controller.status.stringValue = @"登录成功，但无法保存登录状态。请检查本机账户文件夹权限。";
        }
    }];
    [self.webTask resume];
}

- (void)cancelWebLogin {
    [self.webPollTimer invalidate];
    self.webPollTimer = nil;
    [self.webTask cancel];
    self.webTask = nil;
    [self.webSession invalidateAndCancel];
    self.webSession = nil;
    self.webFlow = nil;
    self.webVerifier = nil;
    self.webDeadline = nil;
}

- (void)deferLogin:(id)sender {
    [self cancelWebLogin];
    self.password.stringValue = @"";
    NSString *token = self.deferredSession[@"token"], *email = self.deferredSession[@"email"];
    if (MbsCanRestoreAccountSession(token.UTF8String,email.UTF8String)) {
        self.sessionToken = token;
        self.sessionEmail = email;
        self.membershipLabel = @"已验证的 Mbs 账号 · 待联网同步";
        [self.membershipTimer invalidate];
        self.membershipTimer = [NSTimer scheduledTimerWithTimeInterval:60 target:self
            selector:@selector(membershipTimerFired:) userInfo:nil repeats:YES];
        [self postAccountChange];
        MbsRequestEditorLicense(token.UTF8String,email.UTF8String);
    }
    self.deferredSession = nil;
    [self.window orderOut:nil];
}

- (void)retryConnection:(id)sender { [self startSession]; }

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == self.window) [self cancelWebLogin];
}

- (void)setBusy:(BOOL)busy {
    self.logo.busy = busy;
    self.submit.enabled = !busy;
    self.mode.enabled = !busy;
    self.email.enabled = !busy;
    self.password.enabled = !busy;
    self.remember.enabled = !busy;
    self.retry.enabled = !busy;
    self.webLogin.enabled = !busy;
}

- (void)submit:(id)sender {
    if (self.restoringSession || self.session) return;
    if (self.mode.selectedSegment == 1) {
        NSURL *url = [NSURL URLWithString:MbsRegisterURLString];
        if ([[NSWorkspace sharedWorkspace] openURL:url]) {
            self.status.stringValue = @"已打开注册页面。完成注册后返回这里输入邮箱和密码登录。";
        } else {
            self.status.stringValue = @"无法打开注册页面，请直接访问 ttys.ddxmu.com/mbs/register。";
        }
        return;
    }

    NSString *email = NormalizedEmail(self.email.stringValue);
    NSString *password = self.password.stringValue;
    if (!ValidEmail(email)) {
        self.status.stringValue = @"请输入有效的邮箱地址。";
        return;
    }
    if (!ValidPassword(password)) {
        self.status.stringValue = @"密码至少需要 8 个字符。";
        return;
    }

    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"email": email, @"password": password}
                                                   options:0
                                                     error:nil];
    if (!body) {
        self.status.stringValue = @"登录请求生成失败，请稍后重试。";
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MbsLoginURLString]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    [self cancelWebLogin];
    self.password.stringValue = @"";
    [self setBusy:YES];
    self.status.stringValue = @"正在连接 Mbs Office 账号服务…";
    self.redirectGuard = [MbsRedirectGuard new];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 15.0;
    configuration.timeoutIntervalForResource = 30.0;
    self.session = [NSURLSession sessionWithConfiguration:configuration
                                                  delegate:self.redirectGuard
                                             delegateQueue:[NSOperationQueue mainQueue]];
    __weak MbsLocalAccountController *weakSelf = self;
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        MbsLocalAccountController *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *message = nil;
        NSString *token = nil;
        NSDictionary *user = nil;
        NSInteger statusCode = [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        NSURL *responseURL = response.URL;
        if (error) {
            message = @"无法连接账号服务，请检查网络后重试。";
        } else if (!IsMbsURL(responseURL)) {
            message = @"账号服务地址校验失败，登录未发送到指定服务。";
        } else {
            NSDictionary *payload = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *tokenString = [payload[@"token"] isKindOfClass:NSString.class] ? payload[@"token"] : nil;
            if (statusCode >= 200 && statusCode < 300 && [payload[@"ok"] boolValue] &&
                tokenString.length >= 32 &&
                [payload[@"user"][@"email"] isKindOfClass:NSString.class]) {
                token = tokenString;
                user = payload[@"user"];
            } else {
                message = [payload[@"error"] isKindOfClass:NSString.class] ? payload[@"error"] : @"邮箱或密码不正确。";
            }
        }
        if (token.length && user[@"email"]) {
            BOOL saved = YES;
            if (strongSelf.remember.state == NSControlStateValueOn) {
                saved = MbsSaveSession(user[@"email"], token);
                if (!saved) MbsDeleteSession();
            } else {
                MbsDeleteSession();
            }
            [strongSelf didSignInWithToken:token user:user notify:YES];
            if (!saved) {
                if (NSApp.isActive) [strongSelf.window makeKeyAndOrderFront:nil];
                strongSelf.status.stringValue = @"登录成功，但无法保存登录状态。请检查本机账户文件夹权限。";
            }
        } else {
            strongSelf.status.stringValue = message ?: @"登录失败，请稍后重试。";
        }
        [strongSelf setBusy:NO];
        [strongSelf.session finishTasksAndInvalidate];
        strongSelf.session = nil;
    }];
    [task resume];
}

- (void)logout:(id)sender {
    self.deferredSession = nil;
    MbsResetEditorLicense();
    [self cancelWebLogin];
    MbsDeleteSession();
    NSString *token = self.sessionToken;
    self.sessionToken = nil;
    self.sessionEmail = nil;
    [self.membershipTimer invalidate];
    self.membershipTimer = nil;
    [self.membershipTask cancel];
    self.membershipTask = nil;
    self.vip = NO;
    self.membershipLabel = @"未登录";
    self.password.stringValue = @"";
    self.status.stringValue = @"已退出登录。";
    [self hideStatusPanel];
    [self hideAccountPopover];
    [self postAccountChange];

    if (!token.length) return;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:MbsLogoutURLString]];
    request.HTTPMethod = @"POST";
    [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        [session finishTasksAndInvalidate];
    }] resume];
}

@end

void MbsStartAccountSession(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_async(dispatch_get_main_queue(), ^{ [[MbsLocalAccountController shared] startSession]; });
    });
}

void MbsShowLocalAccount(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp activateIgnoringOtherApps:YES];
        dispatch_async(dispatch_get_main_queue(),^{ [[MbsLocalAccountController shared] show]; });
    });
}

void MbsShowLoginForm(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsLocalAccountController shared] showLoginForm]; });
}

const char *MbsLocalAccountCapabilities(void) {
    return "{\"version\":4,\"localOnly\":false,\"session\":\"https_validated_persistent_token\",\"serverConnected\":true,\"serverBase\":\"https://ttys.ddxmu.com\",\"registration\":\"https://ttys.ddxmu.com/mbs/register\",\"vip\":\"https://ttys.ddxmu.com/mbs/vip\",\"membershipSync\":\"/api/mbs/me\",\"accountRequired\":false,\"allMbsFeaturesAvailable\":true,\"changesWpsPaidEntitlements\":false}";
}

char *MbsCopyLocalAccountState(void) {
    __block NSData *data;
    void (^readState)(void) = ^{
        MbsLocalAccountController *controller = [MbsLocalAccountController shared];
        NSString *email = controller.sessionEmail;
        NSDictionary *state = @{
            @"localOnly": @NO,
            @"serverConnected": @YES,
            @"signedIn": @(email.length > 0),
            @"email": email ?: @"",
            @"isVip": @(controller.vip),
            @"membershipLabel": controller.membershipLabel ?: @"会员状态待同步",
            @"membershipRequired": @NO,
            @"allMbsFeaturesAvailable": @YES,
            @"vendorEntitlementsChanged": @NO
        };
        data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    };
    if (NSThread.isMainThread) readState(); else dispatch_sync(dispatch_get_main_queue(), readState);
    char *result = (char *)calloc(data.length + 1, 1);
    if (result && data.length) memcpy(result, data.bytes, data.length);
    return result;
}

void MbsLocalAccountSignOut(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsLocalAccountController shared] logout:nil]; });
}

const char *MbsCurrentAccountEmail(void) {
    __block NSString *email = nil;
    void (^readEmail)(void) = ^{ email = [[MbsLocalAccountController shared].sessionEmail copy]; };
    if (NSThread.isMainThread) readEmail(); else dispatch_sync(dispatch_get_main_queue(), readEmail);
    return email.length ? strdup(email.UTF8String) : NULL;
}

void MbsAccountHoverAtWindow(void *windowPointer, double x, double y) {
    NSWindow *window = (__bridge NSWindow *)windowPointer;
    dispatch_async(dispatch_get_main_queue(), ^{
        MbsLocalAccountController *controller = [MbsLocalAccountController shared];
        if (!window || window == controller.accountPanel) return;
        if (controller.accountPanel.isVisible && NSPointInRect([NSEvent mouseLocation], controller.accountPanel.frame)) return;
        [controller showAccountPopoverForWindow:window point:NSMakePoint(x, y)];
    });
}

void MbsHideAccountPopover(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        MbsLocalAccountController *controller = [MbsLocalAccountController shared];
        if (controller.accountPanel.isVisible && NSPointInRect(NSEvent.mouseLocation, controller.accountPanel.frame)) return;
        [controller hideAccountPopover];
    });
}
