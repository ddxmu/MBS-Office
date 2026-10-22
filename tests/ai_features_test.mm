#import <AppKit/AppKit.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#include <assert.h>
static NSMutableDictionary *testKeys;
static OSStatus TestCopy(CFDictionaryRef query,CFTypeRef *result) {
    NSData *data=testKeys[((__bridge NSDictionary *)query)[(__bridge id)kSecAttrAccount]];
    if (!data) return errSecItemNotFound;
    *result=CFBridgingRetain(data); return errSecSuccess;
}
static OSStatus TestUpdate(CFDictionaryRef query,CFDictionaryRef values) {
    NSString *account=((__bridge NSDictionary *)query)[(__bridge id)kSecAttrAccount];
    if (!testKeys[account]) return errSecItemNotFound;
    testKeys[account]=((__bridge NSDictionary *)values)[(__bridge id)kSecValueData]; return errSecSuccess;
}
static OSStatus TestAdd(CFDictionaryRef attributes,CFTypeRef *) {
    NSDictionary *value=(__bridge NSDictionary *)attributes;
    testKeys[value[(__bridge id)kSecAttrAccount]]=value[(__bridge id)kSecValueData]; return errSecSuccess;
}
#define SecItemCopyMatching TestCopy
#define SecItemUpdate TestUpdate
#define SecItemAdd TestAdd
#define MBS_AI_TEST 1
#import "../src/MbsAiPanel.mm"
#import "../src/MbsAbout.mm"
static NSUInteger requests, imageRequests;
static NSString *testEndpoint=@"https://ai.example.invalid/v1";
static NSString *responseText=@"模拟文本结果";
static NSInteger responseStatus=200;
@interface AiProtocol : NSURLProtocol
@end
@implementation AiProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    requests++;
    assert([self.request.URL.absoluteString hasPrefix:testEndpoint]);
    assert([[self.request valueForHTTPHeaderField:@"Authorization"] isEqualToString:@"Bearer synthetic-key"]);
    NSData *data=self.request.HTTPBody;
    if (!data && self.request.HTTPBodyStream) {
        NSInputStream *stream=self.request.HTTPBodyStream; [stream open]; NSMutableData *body=[NSMutableData data];
        unsigned char bytes[1024]; NSInteger count;
        while ((count=[stream read:bytes maxLength:sizeof(bytes)])>0) [body appendBytes:bytes length:count];
        [stream close]; data=body;
    }
    NSDictionary *body=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    NSDictionary *value;
    if ([self.request.URL.path hasSuffix:@"/models"]) value=@{@"data":@[@{@"id":@"synthetic-model"},@{@"id":@"other-model"}]};
    else {
        assert([body[@"model"] isEqualToString:@"synthetic-model"]);
        if ([self.request.URL.path hasSuffix:@"/images/generations"]) {
            imageRequests++; assert([body[@"prompt"] isEqualToString:@"测试主题"]);
            NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:8 pixelsHigh:8 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:32 bitsPerPixel:32];
            memset(bitmap.bitmapData,255,256);
            NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            value=@{@"data":@[@{@"b64_json":[png base64EncodedStringWithOptions:0]}]};
        } else { assert([self.request.URL.path hasSuffix:@"/chat/completions"]); value=@{@"choices":@[@{@"message":@{@"content":responseText}}]}; }
    }
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:responseStatus HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[NSJSONSerialization dataWithJSONObject:value options:0 error:nil]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
static void Wait(BOOL (^done)(void)) {
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:8];
    while (!done() && limit.timeIntervalSinceNow>0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(done());
}
int main(int argc,const char **argv) { @autoreleasepool {
    assert(argc==2 && getenv("MBS_AI_TEST_HOME")); testKeys=[NSMutableDictionary dictionary];
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    Method method=class_getClassMethod(NSURLSessionConfiguration.class,@selector(ephemeralSessionConfiguration));
    IMP original=method_getImplementation(method);
    method_setImplementation(method,imp_implementationWithBlock(^NSURLSessionConfiguration *(id receiver) {
        NSURLSessionConfiguration *config=((NSURLSessionConfiguration *(*)(id,SEL))original)(receiver,@selector(ephemeralSessionConfiguration));
        config.protocolClasses=@[AiProtocol.class]; return config;
    }));
    MbsAiPanelController *c=MbsAiPanelController.shared; [c showSettings];
    c.endpointField.stringValue=testEndpoint; c.keyField.stringValue=@"synthetic-key"; c.models.stringValue=@"synthetic-model";
    [c saveSettings:nil];
    assert(requests==0 && [ConfigValue(ReadConfig(),@"model") isEqualToString:@"synthetic-model"]);
    assert(![ReadConfig().description containsString:@"synthetic-key"]);
    puts("PASS configuration saved without fetching or transmitting; secrets excluded from JSON");
    [c fetchModels:nil]; Wait(^BOOL{ return c.fetchButton.enabled; });
    assert(c.models.numberOfItems==2 && [c.models.stringValue isEqualToString:@"synthetic-model"]);
    puts("PASS model discovery uses shared endpoint and preserves selection");
    for (NSString *operation in @[@"write",@"rewrite",@"expand",@"shorten",@"polish",@"proofread",@"translate",@"ask",@"summarize"]) {
        [c showAssistant:operation text:@"测试主题"]; [c run:nil]; Wait(^BOOL{ return c.runButton.enabled; });
        assert([c.output.string isEqualToString:responseText] && c.exportButton.enabled);
    }
    assert([[OperationPrompt(@"expand") lowercaseString] containsString:@"扩写"] && ![OperationPrompt(@"expand") isEqualToString:OperationPrompt(@"shorten")]);
    puts("PASS nine text operations use one saved model and distinct prompts");
    NSString *singleSlide=@"{\"slides\":[{\"title\":\"测试 & <标题>\",\"bullets\":[\"事实一\",\"事实二\"]}]}";
    for (NSString *operation in @[@"ppt",@"document-ppt",@"outline-ppt",@"slides",@"slide"]) {
        BOOL multi=[operation isEqualToString:@"slides"];
        if (multi) {
            responseText=singleSlide; [c showAssistant:operation text:@"测试主题"]; [c run:nil];
            Wait(^BOOL{ return c.runButton.enabled; });
            assert(!c.generatedSlides && !c.exportButton.enabled);
        }
        responseText=multi?@"{\"slides\":[{\"title\":\"测试 & <标题>\",\"bullets\":[\"事实二\"]},{\"title\":\"总结\",\"bullets\":[]}]}":singleSlide;
        [c showAssistant:operation text:@"测试主题"]; [c run:nil]; Wait(^BOOL{ return c.runButton.enabled; });
        assert(c.generatedSlides.count==(multi?2:1) && c.exportButton.enabled && [c.output.string containsString:@"事实二"]);
    }
    NSError *error=nil; NSURL *file=[NSURL fileURLWithPath:@(argv[1])];
    assert(MbsAiWritePresentation(c.generatedSlides,file,&error) && !error);
    assert(!MbsAiSlides(@"{}",NO,nil));
    assert(!MbsAiSlides(@"{\"slides\":[{\"title\":\"一\",\"bullets\":[]},{\"title\":\"二\",\"bullets\":[]}]}",YES,nil));
    puts("PASS five presentation actions, editable PPTX export, malformed response and single-page bounds");
    NSUInteger before=requests; NSMenuItem *history=[NSMenuItem new]; history.representedObject=[c history].firstObject;
    [c restoreHistory:history]; assert(requests==before && c.generatedSlides.count==1);
    puts("PASS local history restore sends no request and retains editable slides");
    [c showAssistant:@"image" text:@"测试主题"]; [c run:nil]; Wait(^BOOL{ return c.runButton.enabled; });
    assert(imageRequests==1 && c.imageData.length && !c.imageView.hidden && c.exportButton.enabled);
    responseStatus=400; [c run:nil]; Wait(^BOOL{ return c.runButton.enabled; });
    assert([c.assistantStatus.stringValue containsString:@"/images/generations"] && !c.exportButton.enabled);
    [c finishImage:nil generation:c.chatGeneration];
    assert(!c.exportButton.enabled && [c.assistantStatus.stringValue containsString:@"可用图片"]);
    puts("PASS image generation through shared configuration and unsupported-model error");
    [c.settingsWindow orderOut:nil]; [c showSettings];
    assert([c.models.stringValue isEqualToString:@"synthetic-model"] && [c.keyField.stringValue isEqualToString:@"synthetic-key"]);
    puts("PASS settings restoration uses saved configuration");
    NSMenuItem *about=[[NSMenuItem alloc] initWithTitle:@"关于 Mbs Office" action:nil keyEquivalent:@""];
    assert([NSApp sendAction:@selector(orderFrontStandardAboutPanel:) to:nil from:about]);
    Wait(^BOOL{ return MbsAboutController.shared.window.isVisible; });
    assert([MbsAboutController.shared.window.title isEqualToString:@"关于 Mbs Office"]);
    puts("PASS native About menu opens the version and repository information window");
    for (NSWindow *window in NSApp.windows) [window orderOut:nil];
    return 0;
} }
