#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import "MbsAiPanel.h"
#import "MbsAiPresentation.h"

static NSString *const MbsAiService = @"com.mbs.office.ai";
static MbsAiInsertCallback insertCallback;
typedef void (^MbsAiResult)(NSString *, NSString *);

static NSString *String(const char *value) {
    return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
}
static NSURL *ConfigURL(void) {
#ifdef MBS_AI_TEST
    return [NSURL fileURLWithPath:[@(getenv("MBS_AI_TEST_HOME")) stringByAppendingPathComponent:@"ai-config.json"]];
#endif
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
    if ([@[@"ppt",@"document-ppt",@"outline-ppt",@"slide",@"slides",@"AI 生成 PPT",@"文档生成 PPT",@"大纲生成 PPT",@"AI 生成单页",@"AI 生成多页"] containsObject:operation]) {
        BOOL single=[@[@"slide",@"AI 生成单页"] containsObject:operation];
        return [NSString stringWithFormat:@"根据用户提供的主题、文档或大纲生成可编辑演示文稿的内容。%@ 保留给定事实，未知数据不编造。只返回 JSON 对象，格式为 {\"slides\":[{\"title\":\"标题\",\"bullets\":[\"要点\"]}]}，不要代码围栏或解释。每页标题不超过 40 字、最多 6 条要点，每条不超过 80 字。",single?@"必须只生成一页。":@"生成 6 至 12 页，覆盖封面、主要内容和总结；总计不超过 30 页。"];
    }
    if ([@[@"write",@"帮我写"] containsObject:operation]) return @"按用户主题与要求撰写文字，结构清晰，未知事实不要编造。只返回正文。";
    if ([@[@"rewrite",@"帮我改"] containsObject:operation]) return @"改写并优化用户文字的结构和表达，保留原意、事实和数字。只返回改写结果。";
    if ([@[@"expand",@"扩写"] containsObject:operation]) return @"扩写用户文字，补充解释和衔接，不编造事实、案例或数字。只返回扩写结果。";
    if ([@[@"shorten",@"缩写"] containsObject:operation]) return @"精简用户文字，保留关键事实、结论和数字。只返回精简结果。";
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
@property(nonatomic, strong) NSComboBox *models;
@property(nonatomic, strong) NSPopUpButton *operations;
@property(nonatomic, strong) NSTextView *input, *output;
@property(nonatomic, strong) NSButton *fetchButton, *runButton, *insertButton, *exportButton;
@property(nonatomic, strong) NSImageView *imageView;
@property(nonatomic, strong) NSData *imageData;
@property(nonatomic, strong) NSArray<NSDictionary *> *generatedSlides;
@property(nonatomic, strong) NSURLSessionDataTask *modelsTask, *chatTask, *imageDownloadTask;
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
        self.models = [[NSComboBox alloc] initWithFrame:NSMakeRect(130, 135, 454, 30)];
        self.models.placeholderString = @"拉取后选择，或输入服务支持的模型名";
        [view addSubview:self.models];
        self.settingsStatus = Label(view, @"所有 AI 功能共用此配置。密钥保存在本机钥匙串；图片生成需要服务及所选模型支持图片接口。", NSMakeRect(24, 64, 560, 58));
        Button(view, @"取消请求", NSMakeRect(24, 20, 105, 32), self, @selector(cancelModels:));
        Button(view, @"保存", NSMakeRect(470, 20, 114, 32), self, @selector(saveSettings:));
    }
    if (!self.settingsWindow.visible) {
        NSDictionary *config = ReadConfig();
        self.endpointField.stringValue = ConfigValue(config, @"endpoint");
        self.keyField.stringValue = ReadKey(self.endpointField.stringValue);
        [self.models removeAllItems];
        NSString *model = ConfigValue(config, @"model");
        if (model.length) [self.models addItemWithObjectValue:model];
        self.models.stringValue = model;
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
        NSString *previous = self.models.stringValue;
        [self.models removeAllItems];
        NSArray *sorted = [[names allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        [self.models addItemsWithObjectValues:sorted];
        self.models.stringValue = [names containsObject:previous] ? previous : sorted.firstObject;
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
    NSString *model = [self.models.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!endpoint || !key.length || !model.length || model.length>256 || [key rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound) {
        self.settingsStatus.stringValue = @"请填写有效的 API 地址、密钥和模型；可以拉取选择或手动输入模型名。";
        return;
    }
    if (!WriteKey(endpoint, key)) { self.settingsStatus.stringValue = @"密钥未能保存到钥匙串，请解锁钥匙串后重试。"; return; }
    NSURL *url = ConfigURL();
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:&error];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version":@1, @"endpoint":endpoint, @"model":model} options:NSJSONWritingPrettyPrinted error:&error];
    if (error || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) { self.settingsStatus.stringValue = @"配置保存失败，请检查本机文件权限。"; return; }
    self.settingsStatus.stringValue = @"已保存，所有 AI 功能将使用此配置。保存不会发送请求。";
    if (self.assistantStatus) self.assistantStatus.stringValue = [@"当前模型：" stringByAppendingString:model];
}
- (void)showAssistant:(NSString *)operation text:(NSString *)text {
    if (!self.assistantWindow) {
        self.assistantWindow = Window(@"AI", NSMakeSize(690, 660));
        self.assistantWindow.delegate = self;
        NSView *view = self.assistantWindow.contentView;
        self.operations = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(24, 610, 215, 30) pullsDown:NO];
        [self.operations addItemsWithTitles:@[@"AI 生成 PPT",@"文档生成 PPT",@"大纲生成 PPT",@"AI 生成单页",@"AI 生成多页",@"AI 生成图片",@"帮我写",@"帮我改",@"扩写",@"缩写",@"润色", @"拼写检查", @"翻译", @"问答", @"总结"]];
        self.operations.target=self; self.operations.action=@selector(operationChanged:);
        [view addSubview:self.operations];
        Button(view, @"导入文档", NSMakeRect(255,610,108,32), self, @selector(importDocument:));
        Button(view, @"历史会话", NSMakeRect(374,610,108,32), self, @selector(showHistory:));
        Button(view, @"设置", NSMakeRect(558, 610, 108, 32), self, @selector(settings:));
        Label(view, @"待处理文字 / 问题（点击运行后发送到你配置的服务）", NSMakeRect(24, 573, 642, 25));
        self.input = Editor(view, NSMakeRect(24, 370, 642, 200), YES);
        self.runButton = Button(view, @"运行 AI", NSMakeRect(24, 327, 114, 32), self, @selector(run:));
        Button(view, @"取消请求", NSMakeRect(151, 327, 114, 32), self, @selector(cancelChat:));
        Label(view, @"结果（请核对后使用）", NSMakeRect(24, 292, 642, 25));
        self.output = Editor(view, NSMakeRect(24, 95, 642, 193), NO);
        self.imageView = [[NSImageView alloc] initWithFrame:NSMakeRect(24,95,642,193)];
        self.imageView.imageScaling=NSImageScaleProportionallyUpOrDown; self.imageView.hidden=YES;
        [view addSubview:self.imageView];
        self.assistantStatus = Label(view, @"", NSMakeRect(24, 47, 642, 43));
        Button(view, @"复制结果", NSMakeRect(24, 10, 114, 32), self, @selector(copyResult:));
        self.insertButton = Button(view, @"写入文档", NSMakeRect(548, 10, 118, 32), self, @selector(insertResult:));
        self.exportButton = Button(view, @"保存结果…", NSMakeRect(158,10,130,32),self,@selector(exportResult:));
        self.exportButton.enabled=NO;
    }
    NSDictionary *aliases = @{@"polish":@"润色", @"proofread":@"拼写检查", @"translate":@"翻译", @"ask":@"问答", @"summarize":@"总结",@"ppt":@"AI 生成 PPT",@"document-ppt":@"文档生成 PPT",@"outline-ppt":@"大纲生成 PPT",@"slide":@"AI 生成单页",@"slides":@"AI 生成多页",@"image":@"AI 生成图片",@"write":@"帮我写",@"rewrite":@"帮我改",@"expand":@"扩写",@"shorten":@"缩写"};
    NSString *title = aliases[operation] ?: operation;
    if ([self.operations itemWithTitle:title]) [self.operations selectItemWithTitle:title];
    if (self.chatTask) [self cancelChat:nil];
    self.input.string = text;
    self.output.string = @"";
    self.generatedSlides=nil;
    self.imageData=nil; self.imageView.hidden=YES; self.output.enclosingScrollView.hidden=NO;
    self.exportButton.enabled=NO;
    self.insertButton.enabled = insertCallback != NULL && ![title isEqualToString:@"AI 生成图片"];
    NSString *model = ConfigValue(ReadConfig(), @"model");
    self.assistantStatus.stringValue = model.length ? [@"当前模型：" stringByAppendingString:model] : @"请先在设置中配置 API、拉取模型并保存。";
    [NSApp activateIgnoringOtherApps:YES];
    [self.assistantWindow makeKeyAndOrderFront:nil];
    if ([operation isEqualToString:@"history"]) [self showHistory:nil];
}
- (void)operationChanged:(id)sender {
    [self cancelChat:nil]; self.output.string=@""; self.imageData=nil;
    self.generatedSlides=nil;
    self.imageView.hidden=YES; self.output.enclosingScrollView.hidden=NO; self.exportButton.enabled=NO;
}
- (void)settings:(id)sender { [self showSettings]; }
- (void)run:(id)sender {
    NSDictionary *config = ReadConfig();
    NSString *endpoint = ConfigValue(config, @"endpoint"), *model = ConfigValue(config, @"model");
    NSString *key = ReadKey(endpoint);
    if (!Endpoint(endpoint) || !key.length || !model.length) { self.assistantStatus.stringValue = @"请先在设置中配置 API、拉取模型并保存。"; [self showSettings]; return; }
    if (!self.input.string.length) { self.assistantStatus.stringValue = @"请输入需要处理的文字或问题。"; return; }
    if (self.input.string.length>50000) { self.assistantStatus.stringValue=@"输入超过 5 万字，请选取需要处理的段落后重试。"; return; }
    [self.chatTask cancel];
    NSUInteger generation = ++self.chatGeneration;
    self.runButton.enabled = NO;
    self.output.string = @"";
    self.generatedSlides=nil;
    self.exportButton.enabled=NO; self.imageData=nil;
    self.imageView.hidden=YES; self.output.enclosingScrollView.hidden=NO;
    self.assistantStatus.stringValue = @"正在处理…";
    if ([self.operations.titleOfSelectedItem isEqualToString:@"AI 生成图片"]) {
        self.chatTask=[[MbsAIClient shared] request:@"/images/generations" endpoint:endpoint key:key
            body:@{@"model":model,@"prompt":self.input.string,@"n":@1,@"size":@"1024x1024",@"response_format":@"b64_json"}
            completion:^(NSString *json,NSString *error) {
                if (generation!=self.chatGeneration) return;
                if (error) { self.runButton.enabled=YES; self.assistantStatus.stringValue=[error stringByAppendingString:@" 图片生成需要服务和当前模型支持 /images/generations。"]; return; }
                NSDictionary *value=[NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                NSArray *items=[value[@"data"] isKindOfClass:NSArray.class]?value[@"data"]:nil;
                NSDictionary *item=[items.firstObject isKindOfClass:NSDictionary.class]?items.firstObject:nil;
                NSString *base64=[item[@"b64_json"] isKindOfClass:NSString.class]?item[@"b64_json"]:nil;
                if (base64.length) { [self finishImage:[[NSData alloc] initWithBase64EncodedString:base64 options:0] generation:generation]; return; }
                NSURL *url=[item[@"url"] isKindOfClass:NSString.class]?[NSURL URLWithString:item[@"url"]]:nil;
                if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length || url.user || url.password) { [self finishImage:nil generation:generation]; return; }
                // Image downloads use no API Authorization header or shared credentials.
                self.imageDownloadTask=[[MbsAIClient shared].session dataTaskWithURL:url completionHandler:^(NSData *data,NSURLResponse *response,NSError *downloadError) {
                    NSInteger status=[(NSHTTPURLResponse *)response statusCode];
                    dispatch_async(dispatch_get_main_queue(), ^{ [self finishImage:!downloadError && status==200?data:nil generation:generation]; });
                }];
                [self.imageDownloadTask resume];
            }];
        return;
    }
    self.chatTask = [[MbsAIClient shared] chat:self.input.string operation:self.operations.titleOfSelectedItem endpoint:endpoint key:key model:model completion:^(NSString *result, NSString *error) {
        if (generation != self.chatGeneration) return;
        self.chatTask = nil;
        self.runButton.enabled = YES;
        if (error) self.assistantStatus.stringValue = error;
        else {
            BOOL presentation=[@[@"AI 生成 PPT",@"文档生成 PPT",@"大纲生成 PPT",@"AI 生成单页",@"AI 生成多页"] containsObject:self.operations.titleOfSelectedItem];
            if (presentation) {
                NSError *parseError=nil;
                self.generatedSlides=MbsAiSlides(result,[self.operations.titleOfSelectedItem isEqualToString:@"AI 生成单页"],&parseError);
                if (!self.generatedSlides) { self.output.string=result; self.assistantStatus.stringValue=parseError.localizedDescription; return; }
                NSMutableString *preview=[NSMutableString string]; NSUInteger i=0;
                for (NSDictionary *slide in self.generatedSlides) {
                    [preview appendFormat:@"%lu. %@\n",(unsigned long)++i,slide[@"title"]];
                    for (NSString *bullet in slide[@"bullets"]) [preview appendFormat:@"  • %@\n",bullet];
                    [preview appendString:@"\n"];
                }
                self.output.string=preview;
            } else self.output.string = result;
            self.exportButton.enabled=YES;
            self.assistantStatus.stringValue = @"已完成。请核对结果；演示内容可保存为可编辑 PPTX，文字可复制或保存。";
            [self saveHistory];
        }
    }];
}
- (void)finishImage:(NSData *)data generation:(NSUInteger)generation {
    if (generation!=self.chatGeneration) return;
    self.chatTask=nil; self.imageDownloadTask=nil; self.runButton.enabled=YES;
    NSImage *image=data.length>0 && data.length<=12*1024*1024?[[NSImage alloc] initWithData:data]:nil;
    if (!image || image.size.width>4096 || image.size.height>4096) {
        self.assistantStatus.stringValue=@"服务未返回可用图片，请确认所选模型支持图片生成。"; return;
    }
    NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
    self.imageData=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!self.imageData) { self.assistantStatus.stringValue=@"图片解析失败，请重试。"; return; }
    self.imageView.image=image; self.imageView.hidden=NO; self.output.enclosingScrollView.hidden=YES;
    self.exportButton.enabled=YES; self.insertButton.enabled=NO;
    self.assistantStatus.stringValue=@"图片已生成，点击“保存结果…”保存 PNG。";
}
- (void)importDocument:(id)sender {
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.allowedFileTypes=@[@"txt",@"md",@"docx",@"rtf"];
    panel.allowsMultipleSelection=NO; panel.canChooseDirectories=NO;
    [panel beginSheetModalForWindow:self.assistantWindow completionHandler:^(NSModalResponse response) {
        if (response!=NSModalResponseOK) return;
        NSNumber *size=nil; [panel.URL getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        if (size.unsignedLongLongValue>10*1024*1024) { self.assistantStatus.stringValue=@"文档超过 10 MB，请复制所需段落到输入框。"; return; }
        NSString *suffix=panel.URL.pathExtension.lowercaseString; NSError *error=nil; NSString *text=nil;
        if ([@[@"docx",@"rtf"] containsObject:suffix]) {
            NSAttributedString *document=[[NSAttributedString alloc] initWithURL:panel.URL options:@{} documentAttributes:nil error:&error]; text=document.string;
        } else text=[NSString stringWithContentsOfURL:panel.URL encoding:NSUTF8StringEncoding error:&error];
        if (!text.length || text.length>50000) { self.assistantStatus.stringValue=@"无法读取正文或正文超过 5 万字，请复制所需段落到输入框。"; return; }
        [self operationChanged:nil]; [self.operations selectItemWithTitle:@"文档生成 PPT"];
        self.input.string=text; self.assistantStatus.stringValue=@"正文已导入；点击“运行 AI”后才会发送到所配置的服务。";
    }];
}
- (void)exportResult:(id)sender {
    if (!self.exportButton.enabled) return;
    NSSavePanel *panel=[NSSavePanel savePanel];
    NSString *type=self.imageData?@"png":(self.generatedSlides?@"pptx":@"txt");
    panel.allowedFileTypes=@[type]; panel.nameFieldStringValue=[@"Mbs AI 结果." stringByAppendingString:type];
    [panel beginSheetModalForWindow:self.assistantWindow completionHandler:^(NSModalResponse response) {
        if (response!=NSModalResponseOK) return;
        NSError *error=nil; BOOL ok;
        if (self.imageData) ok=[self.imageData writeToURL:panel.URL options:NSDataWritingAtomic error:&error];
        else if (self.generatedSlides) ok=MbsAiWritePresentation(self.generatedSlides,panel.URL,&error);
        else ok=[self.output.string writeToURL:panel.URL atomically:YES encoding:NSUTF8StringEncoding error:&error];
        self.assistantStatus.stringValue=ok?@"结果已保存。":(error.localizedDescription?:@"保存失败，请重试。");
    }];
}
- (NSURL *)historyURL { return [[ConfigURL() URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"ai-history.json"]; }
- (NSArray *)history {
    NSData *data=[NSData dataWithContentsOfURL:self.historyURL];
    if (data.length>4*1024*1024) return @[];
    id entries=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    return [entries isKindOfClass:NSArray.class]?entries:@[];
}
- (void)saveHistory {
    NSMutableArray *entries=[[self history] mutableCopy];
    [entries insertObject:@{@"operation":self.operations.titleOfSelectedItem,@"input":self.input.string,@"output":self.output.string,
        @"slides":self.generatedSlides?:@[],@"date":[NSDateFormatter localizedStringFromDate:NSDate.date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]} atIndex:0];
    while (entries.count>30) [entries removeLastObject];
    NSData *data=[NSJSONSerialization dataWithJSONObject:entries options:0 error:nil];
    while (data.length>4*1024*1024 && entries.count) { [entries removeLastObject]; data=[NSJSONSerialization dataWithJSONObject:entries options:0 error:nil]; }
    [NSFileManager.defaultManager createDirectoryAtURL:self.historyURL.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToURL:self.historyURL options:NSDataWritingAtomic error:nil];
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self.historyURL.path error:nil];
}
- (void)showHistory:(id)sender {
    NSMenu *menu=[[NSMenu alloc] initWithTitle:@"本机历史会话（最近 30 条）"];
    for (id entry in [self history]) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"operation"] isKindOfClass:NSString.class] ||
            ![entry[@"input"] isKindOfClass:NSString.class] || ![entry[@"output"] isKindOfClass:NSString.class]) continue;
        NSString *input=entry[@"input"], *preview=[input substringToIndex:MIN((NSUInteger)24,input.length)];
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@  %@  %@",entry[@"date"]?:@"",entry[@"operation"],preview] action:@selector(restoreHistory:) keyEquivalent:@""];
        item.target=self; item.representedObject=entry; [menu addItem:item];
    }
    if (!menu.numberOfItems) { NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"暂无历史会话" action:nil keyEquivalent:@""]; [menu addItem:item]; }
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(374,610) inView:self.assistantWindow.contentView];
}
- (void)restoreHistory:(NSMenuItem *)item {
    NSDictionary *entry=item.representedObject; [self operationChanged:nil];
    [self.operations selectItemWithTitle:entry[@"operation"]]; self.input.string=entry[@"input"]; self.output.string=entry[@"output"];
    if ([entry[@"slides"] isKindOfClass:NSArray.class] && [entry[@"slides"] count]) {
        NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"slides":entry[@"slides"]} options:0 error:nil];
        self.generatedSlides=MbsAiSlides([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding],NO,nil);
    }
    self.exportButton.enabled=self.output.string.length>0;
    self.assistantStatus.stringValue=@"已恢复本机历史会话，没有发送请求。";
}
- (void)cancelChat:(id)sender {
    ++self.chatGeneration;
    [self.chatTask cancel];
    [self.imageDownloadTask cancel]; self.imageDownloadTask=nil;
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
