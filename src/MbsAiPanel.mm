#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import "MbsAiPanel.h"

static NSString *const MbsAiService = @"com.mbs.office.ai";
static MbsAiInsertCallback insertCallback;
typedef void (^MbsAiResult)(NSString *, NSString *);

static NSString *String(const char *value) {
    return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
}
static NSURL *ConfigURL(void) {
    NSURL *directory = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
    return [[directory URLByAppendingPathComponent:@"Mbs Office" isDirectory:YES] URLByAppendingPathComponent:@"ai-config.json"];
}
static NSDictionary *ReadConfig(void) {
    NSData *data = [NSData dataWithContentsOfURL:ConfigURL()];
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [object isKindOfClass:NSDictionary.class] ? object : @{};
}
static NSString *ConfigValue(NSDictionary *config, NSString *key) {
    return [config[key] isKindOfClass:NSString.class] ? config[key] : @"";
}
static NSString *Endpoint(NSString *value) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURLComponents *parts = [NSURLComponents componentsWithString:trimmed];
    NSString *scheme = parts.scheme.lowercaseString, *host = parts.host.lowercaseString;
    BOOL local = [@[@"localhost", @"127.0.0.1", @"::1", @"[::1]"] containsObject:host ?: @""];
    if (!parts.URL || !host.length || parts.user || parts.password || parts.query || parts.fragment ||
        !([scheme isEqualToString:@"https"] || ([scheme isEqualToString:@"http"] && local))) return nil;
    trimmed = parts.URL.absoluteString;
    while ([trimmed hasSuffix:@"/"]) trimmed = [trimmed substringToIndex:trimmed.length - 1];
    return trimmed;
}
static NSMutableDictionary *KeyQuery(NSString *endpoint) {
    return [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService:MbsAiService,
              (__bridge id)kSecAttrAccount:endpoint} mutableCopy];
}
static NSString *ReadKey(NSString *endpoint) {
    if (!endpoint.length) return @"";
    NSMutableDictionary *query = KeyQuery(endpoint);
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) return @"";
    NSData *data = CFBridgingRelease(result);
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}
static BOOL WriteKey(NSString *endpoint, NSString *key) {
    NSMutableDictionary *query = KeyQuery(endpoint);
    NSData *data = [key dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                   (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (status == errSecItemNotFound) {
        query[(__bridge id)kSecValueData] = data;
        query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly;
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }
    return status == errSecSuccess;
}
static NSString *OperationPrompt(NSString *operation) {
    if ([operation isEqualToString:@"polish"] || [operation isEqualToString:@"润色"])
        return @"润色用户提供的文字，保留原意、事实、数字和语言。只返回润色结果。";
    if ([operation isEqualToString:@"proofread"] || [operation isEqualToString:@"拼写检查"])
        return @"修正用户文字中的拼写、错别字和语法，保留原意和格式。只返回修正后的文字。";
    if ([operation isEqualToString:@"translate"] || [operation isEqualToString:@"翻译"])
        return @"将用户文字在中文和英文之间翻译：中文译为英文，其他语言译为简体中文。保留段落和数字，只返回译文。";
    if ([operation isEqualToString:@"summarize"] || [operation isEqualToString:@"总结"])
        return @"用与用户原文相同的语言总结所提供文字，准确提炼要点，不添加原文没有的事实。";
    return @"根据用户提供的文字和问题作答。若材料不足以回答，请明确说明，不编造事实。";
}

@interface MbsAIClient : NSObject <NSURLSessionTaskDelegate>
@property(nonatomic, strong) NSURLSession *session;
+ (instancetype)shared;
- (NSURLSessionDataTask *)request:(NSString *)path endpoint:(NSString *)endpoint key:(NSString *)key body:(NSDictionary *)body completion:(MbsAiResult)completion;
- (NSURLSessionDataTask *)chat:(NSString *)text operation:(NSString *)operation endpoint:(NSString *)endpoint key:(NSString *)key model:(NSString *)model completion:(MbsAiResult)completion;
@end

@implementation MbsAIClient
+ (instancetype)shared {
    static MbsAIClient *client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        client = [MbsAIClient new];
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = 60;
        config.timeoutIntervalForResource = 120;
        config.HTTPCookieStorage = nil;
        config.URLCredentialStorage = nil;
        config.URLCache = nil;
        client.session = [NSURLSession sessionWithConfiguration:config delegate:client delegateQueue:nil];
    });
    return client;
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler {
    // Never forward a key through a redirect, including redirects to another origin.
    completionHandler(nil);
}
- (NSURLSessionDataTask *)request:(NSString *)path endpoint:(NSString *)endpoint key:(NSString *)key body:(NSDictionary *)body completion:(MbsAiResult)completion {
    NSString *base = Endpoint(endpoint);
    if (!base || !key.length || [key rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, @"请先填写有效的 API 地址和密钥。"); });
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[base stringByAppendingString:path]]];
    [request setValue:[@"Bearer " stringByAppendingString:key] forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (body) {
        request.HTTPMethod = @"POST";
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    }
    NSURLSessionDataTask *task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *message = nil, *json = nil;
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        if (error) message = error.code == NSURLErrorCancelled ? @"请求已取消。" : (error.code == NSURLErrorTimedOut ? @"请求超时，请重试。" : @"连接失败，请检查 API 地址、网络和服务器证书。");
        else if (status < 200 || status >= 300) message = [NSString stringWithFormat:@"服务器返回 HTTP %ld，请检查接口、密钥和服务权限。", (long)status];
        else if (data.length > 8 * 1024 * 1024) message = @"服务器响应过大，请缩短输入后重试。";
        else {
            id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (![object isKindOfClass:NSDictionary.class]) message = @"服务器没有返回兼容的 JSON 数据。";
            else json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(json, message); });
    }];
    [task resume];
    return task;
}
- (NSURLSessionDataTask *)chat:(NSString *)text operation:(NSString *)operation endpoint:(NSString *)endpoint key:(NSString *)key model:(NSString *)model completion:(MbsAiResult)completion {
    if (!text.length || !model.length) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, @"请先保存模型配置，并提供要处理的文字。"); });
        return nil;
    }
    NSDictionary *body = @{@"model":model, @"stream":@NO, @"messages":@[
        @{@"role":@"system", @"content":OperationPrompt(operation)},
        @{@"role":@"user", @"content":text}]};
    return [self request:@"/chat/completions" endpoint:endpoint key:key body:body completion:^(NSString *json, NSString *error) {
        if (error) { completion(nil, error); return; }
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSArray *choices = [object[@"choices"] isKindOfClass:NSArray.class] ? object[@"choices"] : nil;
        NSDictionary *choice = [choices.firstObject isKindOfClass:NSDictionary.class] ? choices.firstObject : nil;
        NSDictionary *message = [choice[@"message"] isKindOfClass:NSDictionary.class] ? choice[@"message"] : nil;
        NSString *result = [message[@"content"] isKindOfClass:NSString.class] ? message[@"content"] : nil;
        completion(result.length ? result : nil, result.length ? nil : @"模型没有返回文字结果，请选择支持聊天的模型。");
    }];
}
@end

static NSTextField *Label(NSView *view, NSString *text, NSRect frame) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.frame = frame;
    [view addSubview:label];
    return label;
}
static NSButton *Button(NSView *view, NSString *title, NSRect frame, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.frame = frame;
    button.bezelStyle = NSBezelStyleRounded;
    [view addSubview:button];
    return button;
}
static NSTextView *Editor(NSView *view, NSRect frame, BOOL editable) {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextView *editor = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    editor.editable = editable;
    editor.richText = NO;
    editor.font = [NSFont systemFontOfSize:14];
    editor.textContainerInset = NSMakeSize(8, 8);
    editor.autoresizingMask = NSViewWidthSizable;
    scroll.documentView = editor;
    [view addSubview:scroll];
    return editor;
}
static NSWindow *Window(NSString *title, NSSize size) {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, size.width, size.height) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable backing:NSBackingStoreBuffered defer:NO];
    window.title = title;
    window.releasedWhenClosed = NO;
    [window center];
    return window;
}

@interface MbsAiPanelController : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *settingsWindow, *assistantWindow;
@property(nonatomic, strong) NSTextField *endpointField, *settingsStatus, *assistantStatus;
@property(nonatomic, strong) NSSecureTextField *keyField;
@property(nonatomic, strong) NSPopUpButton *models, *operations;
@property(nonatomic, strong) NSTextView *input, *output;
@property(nonatomic, strong) NSButton *fetchButton, *runButton, *insertButton;
@property(nonatomic, strong) NSURLSessionDataTask *modelsTask, *chatTask;
@property(nonatomic, copy) NSString *loadedEndpoint, *loadedKey;
@property(nonatomic) NSUInteger modelsGeneration, chatGeneration;
+ (instancetype)shared;
- (void)showSettings;
- (void)showAssistant:(NSString *)operation text:(NSString *)text;
@end

@implementation MbsAiPanelController
+ (instancetype)shared {
    static MbsAiPanelController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [MbsAiPanelController new]; });
    return controller;
}
- (void)showSettings {
    if (!self.settingsWindow) {
        self.settingsWindow = Window(@"AI 设置", NSMakeSize(610, 350));
        self.settingsWindow.delegate = self;
        NSView *view = self.settingsWindow.contentView;
        Label(view, @"连接你自己的 OpenAI 兼容服务", NSMakeRect(24, 310, 560, 24));
        Label(view, @"API 地址（含 /v1 等接口路径）", NSMakeRect(24, 275, 560, 22));
        self.endpointField = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 242, 560, 28)];
        self.endpointField.placeholderString = @"https://你的服务器/v1";
        [view addSubview:self.endpointField];
        Label(view, @"API 密钥", NSMakeRect(24, 208, 100, 22));
        self.keyField = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(24, 175, 415, 28)];
        [view addSubview:self.keyField];
        self.fetchButton = Button(view, @"拉取模型", NSMakeRect(450, 173, 134, 32), self, @selector(fetchModels:));
        Label(view, @"选择模型", NSMakeRect(24, 139, 100, 22));
        self.models = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(130, 135, 454, 30) pullsDown:NO];
        [view addSubview:self.models];
        self.settingsStatus = Label(view, @"密钥保存在本机钥匙串。仅在拉取模型或运行 AI 时连接此服务。", NSMakeRect(24, 64, 560, 58));
        Button(view, @"取消请求", NSMakeRect(24, 20, 105, 32), self, @selector(cancelModels:));
        Button(view, @"保存", NSMakeRect(470, 20, 114, 32), self, @selector(saveSettings:));
    }
    if (!self.settingsWindow.visible) {
        NSDictionary *config = ReadConfig();
        self.endpointField.stringValue = ConfigValue(config, @"endpoint");
        self.keyField.stringValue = ReadKey(self.endpointField.stringValue);
        self.loadedEndpoint = self.endpointField.stringValue;
        self.loadedKey = self.keyField.stringValue;
        [self.models removeAllItems];
        NSString *model = ConfigValue(config, @"model");
        if (model.length) [self.models addItemWithTitle:model];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self.settingsWindow makeKeyAndOrderFront:nil];
}
- (void)fetchModels:(id)sender {
    NSString *endpoint = Endpoint(self.endpointField.stringValue);
    NSString *key = self.keyField.stringValue;
    if (!endpoint || !key.length) { self.settingsStatus.stringValue = @"请输入 HTTPS API 地址和密钥；本机 localhost 测试可使用 HTTP。"; return; }
    [self.modelsTask cancel];
    NSUInteger generation = ++self.modelsGeneration;
    self.fetchButton.enabled = NO;
    self.settingsStatus.stringValue = @"正在拉取模型…";
    self.modelsTask = [[MbsAIClient shared] request:@"/models" endpoint:endpoint key:key body:nil completion:^(NSString *json, NSString *error) {
        if (generation != self.modelsGeneration) return;
        self.modelsTask = nil;
        self.fetchButton.enabled = YES;
        if (error) { self.settingsStatus.stringValue = error; return; }
        NSDictionary *object = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSArray *data = [object[@"data"] isKindOfClass:NSArray.class] ? object[@"data"] : nil;
        NSMutableSet *names = [NSMutableSet set];
        for (id item in data) {
            id model = [item isKindOfClass:NSDictionary.class] ? item[@"id"] : nil;
            if ([model isKindOfClass:NSString.class] && [model length]) [names addObject:model];
        }
        if (!names.count) { self.settingsStatus.stringValue = @"服务没有返回可选模型，请确认 /models 接口兼容。"; return; }
        NSString *previous = self.models.titleOfSelectedItem;
        [self.models removeAllItems];
        [self.models addItemsWithTitles:[[names allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]];
        if (previous && [names containsObject:previous]) [self.models selectItemWithTitle:previous];
        self.loadedEndpoint = endpoint;
        self.loadedKey = key;
        self.settingsStatus.stringValue = @"模型已拉取。选择支持聊天的模型，然后保存。";
    }];
}
- (void)cancelModels:(id)sender {
    ++self.modelsGeneration;
    [self.modelsTask cancel];
    self.modelsTask = nil;
    self.fetchButton.enabled = YES;
    self.settingsStatus.stringValue = @"请求已取消。";
}
- (void)saveSettings:(id)sender {
    NSString *endpoint = Endpoint(self.endpointField.stringValue), *key = self.keyField.stringValue;
    NSString *model = self.models.titleOfSelectedItem;
    if (!endpoint || !key.length || !model.length || ![endpoint isEqualToString:self.loadedEndpoint] || ![key isEqualToString:self.loadedKey]) {
        self.settingsStatus.stringValue = @"请使用当前 API 地址和密钥拉取模型，并选择模型后再保存。";
        return;
    }
    if (!WriteKey(endpoint, key)) { self.settingsStatus.stringValue = @"密钥未能保存到钥匙串，请解锁钥匙串后重试。"; return; }
    NSURL *url = ConfigURL();
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version":@1, @"endpoint":endpoint, @"model":model} options:NSJSONWritingPrettyPrinted error:&error];
    if (error || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) { self.settingsStatus.stringValue = @"配置保存失败，请检查本机文件权限。"; return; }
    self.settingsStatus.stringValue = @"已保存。保存设置不会发送请求。";
    if (self.assistantStatus) self.assistantStatus.stringValue = [@"当前模型：" stringByAppendingString:model];
}
- (void)showAssistant:(NSString *)operation text:(NSString *)text {
    if (!self.assistantWindow) {
        self.assistantWindow = Window(@"AI", NSMakeSize(690, 660));
        self.assistantWindow.delegate = self;
        NSView *view = self.assistantWindow.contentView;
        self.operations = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 610, 215, 30) pullsDown:NO];
        [self.operations addItemsWithTitles:@[@"润色", @"拼写检查", @"翻译", @"问答", @"总结"]];
        [view addSubview:self.operations];
        Button(view, @"设置", NSMakeRect(558, 610, 108, 32), self, @selector(settings:));
        Label(view, @"待处理文字 / 问题（点击运行后发送到你配置的服务）", NSMakeRect(24, 573, 642, 25));
        self.input = Editor(view, NSMakeRect(24, 370, 642, 200), YES);
        self.runButton = Button(view, @"运行 AI", NSMakeRect(24, 327, 114, 32), self, @selector(run:));
        Button(view, @"取消请求", NSMakeRect(151, 327, 114, 32), self, @selector(cancelChat:));
        Label(view, @"结果（请核对后使用）", NSMakeRect(24, 292, 642, 25));
        self.output = Editor(view, NSMakeRect(24, 95, 642, 193), NO);
        self.assistantStatus = Label(view, @"", NSMakeRect(24, 47, 642, 43));
        Button(view, @"复制结果", NSMakeRect(24, 10, 114, 32), self, @selector(copyResult:));
        self.insertButton = Button(view, @"写入文档", NSMakeRect(548, 10, 118, 32), self, @selector(insertResult:));
    }
    NSDictionary *aliases = @{@"polish":@"润色", @"proofread":@"拼写检查", @"translate":@"翻译", @"ask":@"问答", @"summarize":@"总结"};
    NSString *title = aliases[operation] ?: operation;
    if ([self.operations itemWithTitle:title]) [self.operations selectItemWithTitle:title];
    if (self.chatTask) [self cancelChat:nil];
    self.input.string = text;
    self.output.string = @"";
    self.insertButton.enabled = insertCallback != NULL;
    NSString *model = ConfigValue(ReadConfig(), @"model");
    self.assistantStatus.stringValue = model.length ? [@"当前模型：" stringByAppendingString:model] : @"请先在设置中配置 API、拉取模型并保存。";
    [NSApp activateIgnoringOtherApps:YES];
    [self.assistantWindow makeKeyAndOrderFront:nil];
}
- (void)settings:(id)sender { [self showSettings]; }
- (void)run:(id)sender {
    NSDictionary *config = ReadConfig();
    NSString *endpoint = ConfigValue(config, @"endpoint"), *model = ConfigValue(config, @"model");
    NSString *key = ReadKey(endpoint);
    if (!Endpoint(endpoint) || !key.length || !model.length) { self.assistantStatus.stringValue = @"请先在设置中配置 API、拉取模型并保存。"; [self showSettings]; return; }
    if (!self.input.string.length) { self.assistantStatus.stringValue = @"请输入需要处理的文字或问题。"; return; }
    [self.chatTask cancel];
    NSUInteger generation = ++self.chatGeneration;
    self.runButton.enabled = NO;
    self.output.string = @"";
    self.assistantStatus.stringValue = @"正在处理…";
    self.chatTask = [[MbsAIClient shared] chat:self.input.string operation:self.operations.titleOfSelectedItem endpoint:endpoint key:key model:model completion:^(NSString *result, NSString *error) {
        if (generation != self.chatGeneration) return;
        self.chatTask = nil;
        self.runButton.enabled = YES;
        if (error) self.assistantStatus.stringValue = error;
        else { self.output.string = result; self.assistantStatus.stringValue = @"已完成。请核对结果；可复制，或使用已连接的文档写入接口。"; }
    }];
}
- (void)cancelChat:(id)sender {
    ++self.chatGeneration;
    [self.chatTask cancel];
    self.chatTask = nil;
    self.runButton.enabled = YES;
    self.assistantStatus.stringValue = @"请求已取消。";
}
- (void)copyResult:(id)sender {
    if (!self.output.string.length) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setString:self.output.string forType:NSPasteboardTypeString];
    self.assistantStatus.stringValue = @"结果已复制到剪贴板。";
}
- (void)insertResult:(id)sender {
    if (!self.output.string.length || !insertCallback) return;
    insertCallback(self.output.string.UTF8String);
    self.assistantStatus.stringValue = @"结果已交给文档写入接口，请在文档中确认。";
}
- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == self.settingsWindow) [self cancelModels:nil];
    if (notification.object == self.assistantWindow) [self cancelChat:nil];
}
@end

void MbsShowAiSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsAiPanelController shared] showSettings]; });
}
void MbsShowAiAssistant(const char *operation, const char *text) {
    NSString *op = String(operation), *input = String(text);
    dispatch_async(dispatch_get_main_queue(), ^{ [[MbsAiPanelController shared] showAssistant:op text:input]; });
}
void MbsSetAiInsertCallback(MbsAiInsertCallback callback) {
    dispatch_async(dispatch_get_main_queue(), ^{
        insertCallback = callback;
        [MbsAiPanelController shared].insertButton.enabled = callback != NULL;
    });
}
void MbsAiRequestAsync(const char *operation, const char *text, MbsAiCompletion completion) {
    if (!completion) return;
    NSString *op = String(operation), *input = String(text);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *config = ReadConfig();
        NSString *endpoint = ConfigValue(config, @"endpoint");
        [[MbsAIClient shared] chat:input operation:op endpoint:endpoint key:ReadKey(endpoint) model:ConfigValue(config, @"model") completion:^(NSString *result, NSString *error) {
            completion(result.UTF8String, error.UTF8String);
        }];
    });
}
