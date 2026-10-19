#import <AppKit/AppKit.h>
#import <Security/SecRandom.h>
#import <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#import "MbsLocalAccount.h"

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

@interface MbsLocalAccountController : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSSegmentedControl *mode;
@property(nonatomic, strong) NSTextField *email;
@property(nonatomic, strong) NSSecureTextField *password;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSButton *submit;
@property(nonatomic, strong) NSButton *logout;
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
@property(nonatomic, strong) NSTextField *accountPanelEmail;
@property(nonatomic, strong) NSTextField *accountPanelMembership;
@property(nonatomic, strong) NSButton *accountPanelUpgrade;
@property(nonatomic, strong) NSButton *accountPanelLogout;
@property(nonatomic, weak) NSWindow *accountHostWindow;
@property(nonatomic, strong) NSTimer *membershipTimer;
@property(nonatomic, strong) NSURLSessionDataTask *membershipTask;
@property(nonatomic, strong) NSDate *membershipLastRefresh;
@property(nonatomic, assign) BOOL restoringSession;
+ (instancetype)shared;
- (void)show;
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
- (void)postAccountChange;
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
    });
    return controller;
}

- (void)startSession {
    NSDictionary *saved = MbsLoadSession();
    NSString *token = [saved[@"token"] isKindOfClass:NSString.class] ? saved[@"token"] : nil;
    NSString *email = [saved[@"email"] isKindOfClass:NSString.class] ? saved[@"email"] : nil;
    if (token.length < 32 || token.length > 128 || !ValidEmail(email)) {
        MbsDeleteSession();
        [self show];
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
            if (code == 401) {
                MbsDeleteSession();
                [self show];
            }
            self.status.stringValue = code == 401 ? @"登录状态已过期，请重新输入密码。" : @"无法验证登录状态，请检查网络后重新登录。文档仍可离线编辑。";
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
    self.password.stringValue = @"";
    self.status.stringValue = [NSString stringWithFormat:@"已登录：%@", self.sessionEmail];
    [self.window orderOut:nil];
    [self.window resignKeyWindow];
    if (notify) [self showStatusPanel];
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
}

- (void)hideStatusPanel {
    [self.statusDismissTimer invalidate];
    self.statusDismissTimer = nil;
    [self.statusPanel orderOut:nil];
    [self.statusView removeFromSuperview];
    self.statusHostWindow = nil;
}

- (void)showStatusPanel {
    if (!self.sessionEmail.length) {
        [self hideStatusPanel];
        return;
    }
    if (!self.statusPanel) {
        self.statusPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 220, 24)
                                                        styleMask:NSWindowStyleMaskBorderless
                                                          backing:NSBackingStoreBuffered
                                                            defer:NO];
        self.statusPanel.level = NSFloatingWindowLevel;
        self.statusPanel.opaque = NO;
        self.statusPanel.backgroundColor = NSColor.clearColor;
        self.statusPanel.hasShadow = YES;
        self.statusPanel.ignoresMouseEvents = YES;
        self.statusPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                               NSWindowCollectionBehaviorFullScreenAuxiliary;
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
    [self.statusPanel orderFrontRegardless];
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
    self.accountPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 368, 292)
                                                     styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
                                                       backing:NSBackingStoreBuffered
                                                         defer:NO];
    self.accountPanel.releasedWhenClosed = NO;
    self.accountPanel.level = NSFloatingWindowLevel;
    self.accountPanel.opaque = NO;
    self.accountPanel.backgroundColor = NSColor.clearColor;
    self.accountPanel.hasShadow = YES;
    self.accountPanel.hidesOnDeactivate = NO;
    self.accountPanel.ignoresMouseEvents = NO;
    self.accountPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                            NSWindowCollectionBehaviorFullScreenAuxiliary;

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
    title.frame = NSMakeRect(24, 246, 320, 24);
    [self.accountPanel.contentView addSubview:title];

    self.accountPanelEmail = [NSTextField labelWithString:@""];
    self.accountPanelEmail.font = [NSFont systemFontOfSize:15.0 weight:NSFontWeightMedium];
    self.accountPanelEmail.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.accountPanelEmail.frame = NSMakeRect(24, 211, 320, 22);
    [self.accountPanel.contentView addSubview:self.accountPanelEmail];

    self.accountPanelMembership = [NSTextField labelWithString:@""];
    self.accountPanelMembership.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightRegular];
    self.accountPanelMembership.textColor = NSColor.secondaryLabelColor;
    self.accountPanelMembership.frame = NSMakeRect(24, 176, 320, 22);
    [self.accountPanel.contentView addSubview:self.accountPanelMembership];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(24, 157, 320, 1)];
    separator.boxType = NSBoxSeparator;
    [self.accountPanel.contentView addSubview:separator];

    self.accountPanelUpgrade = [NSButton buttonWithTitle:@"立即升级" target:self action:@selector(openVip:)];
    self.accountPanelUpgrade.frame = NSMakeRect(24, 101, 320, 38);
    self.accountPanelUpgrade.bezelStyle = NSBezelStyleRounded;
    [self.accountPanel.contentView addSubview:self.accountPanelUpgrade];

    self.accountPanelLogout = [NSButton buttonWithTitle:@"退出登录" target:self action:@selector(logout:)];
    self.accountPanelLogout.frame = NSMakeRect(24, 52, 320, 30);
    self.accountPanelLogout.bezelStyle = NSBezelStyleTexturedRounded;
    [self.accountPanel.contentView addSubview:self.accountPanelLogout];

    NSTextField *hint = [NSTextField labelWithString:@"会员状态由账号服务同步。"];
    hint.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightRegular];
    hint.textColor = NSColor.tertiaryLabelColor;
    hint.frame = NSMakeRect(24, 20, 320, 18);
    [self.accountPanel.contentView addSubview:hint];
}

- (void)showAccountPopoverForWindow:(NSWindow *)window point:(NSPoint)point {
    if (!self.sessionEmail.length || !window) {
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
    [self.accountPanel orderFrontRegardless];
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
        } else if (statusCode == 401) {
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
    [self refreshMembership:NO];
}

- (void)show {
    // A successful login is already reflected in the main window. Opening the
    // account entry again must not bring the login form back over the editor.
    if (self.sessionEmail.length) {
        [self postAccountChange];
        [self.window orderOut:nil];
        [self.window resignKeyWindow];
        [self showStatusPanel];
        return;
    }
    [self prepareWindow];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)prepareWindow {
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 570, 440)
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        self.window.title = @"Mbs Office 账号";
        self.window.releasedWhenClosed = NO;
        self.window.delegate = self;
        self.window.level = NSFloatingWindowLevel;
        self.window.hidesOnDeactivate = YES;
        [self.window center];

        NSView *view = self.window.contentView;
        AccountLabel(view, @"使用 Mbs Office 账号登录，注册会打开 ttys.ddxmu.com 网页。", NSMakeRect(24, 396, 522, 24));
        AccountLabel(view, @"登录成功后此窗口自动关闭，并同步账号与会员状态。", NSMakeRect(24, 350, 522, 42));

        self.mode = [NSSegmentedControl segmentedControlWithLabels:@[@"登录", @"注册"]
                                                       trackingMode:NSSegmentSwitchTrackingSelectOne
                                                             target:self
                                                             action:@selector(changeMode:)];
        self.mode.frame = NSMakeRect(24, 309, 522, 30);
        self.mode.selectedSegment = 0;
        [view addSubview:self.mode];

        AccountLabel(view, @"邮箱", NSMakeRect(24, 269, 90, 24));
        self.email = [[NSTextField alloc] initWithFrame:NSMakeRect(121, 265, 425, 28)];
        self.email.placeholderString = @"name@example.com";
        [view addSubview:self.email];

        AccountLabel(view, @"密码", NSMakeRect(24, 226, 90, 24));
        self.password = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(121, 222, 425, 28)];
        self.password.placeholderString = @"至少 8 个字符";
        [view addSubview:self.password];

        self.remember = [NSButton checkboxWithTitle:@"保持登录状态（30 天）" target:nil action:nil];
        self.remember.frame = NSMakeRect(121, 182, 180, 24);
        self.remember.state = NSControlStateValueOn;
        [view addSubview:self.remember];

        AccountLabel(view, @"仅保存登录会话，不保存密码。", NSMakeRect(121, 155, 425, 24));

        self.status = AccountLabel(view, @"未登录。登录只连接 Mbs Office 账号服务。", NSMakeRect(24, 75, 522, 67));

        self.submit = [NSButton buttonWithTitle:@"登录" target:self action:@selector(submit:)];
        self.submit.frame = NSMakeRect(422, 24, 124, 32);
        self.submit.bezelStyle = NSBezelStyleRounded;
        [view addSubview:self.submit];

        NSButton *webLogin = [NSButton buttonWithTitle:@"网页登录" target:self action:@selector(openWebLogin:)];
        webLogin.frame = NSMakeRect(152, 24, 112, 32);
        webLogin.bezelStyle = NSBezelStyleRounded;
        [view addSubview:webLogin];

        NSButton *later = [NSButton buttonWithTitle:@"稍后登录" target:self action:@selector(deferLogin:)];
        later.frame = NSMakeRect(282, 24, 124, 32);
        later.bezelStyle = NSBezelStyleRounded;
        [view addSubview:later];
        self.submit.keyEquivalent = @"\r";

        self.logout = [NSButton buttonWithTitle:@"退出登录" target:self action:@selector(logout:)];
        self.logout.frame = NSMakeRect(24, 24, 124, 32);
        self.logout.bezelStyle = NSBezelStyleRounded;
        self.logout.enabled = self.sessionEmail.length > 0;
        [view addSubview:self.logout];
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
            [controller.window makeKeyAndOrderFront:nil];
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
    [self.window orderOut:nil];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == self.window) [self cancelWebLogin];
}

- (void)setBusy:(BOOL)busy {
    self.submit.enabled = !busy;
    self.mode.enabled = !busy;
    self.email.enabled = !busy;
    self.password.enabled = !busy;
    self.logout.enabled = !busy && self.sessionEmail.length > 0;
    self.remember.enabled = !busy;
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
                [strongSelf.window makeKeyAndOrderFront:nil];
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
    self.logout.enabled = NO;
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
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsLocalAccountController shared] show]; });
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
    dispatch_async(dispatch_get_main_queue(), ^{
        MbsLocalAccountController *controller = [MbsLocalAccountController shared];
        NSWindow *window = (__bridge NSWindow *)windowPointer;
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
