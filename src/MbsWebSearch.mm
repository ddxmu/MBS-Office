#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import "MbsWebSearch.h"

@interface MbsWebSearchWindow : NSWindowController <WKUIDelegate>
@property WKWebView *web;
@end
@implementation MbsWebSearchWindow
- (instancetype)init {
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,960,720)
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    if (!(self=[super initWithWindow:window])) return nil;
    window.title=@"Mbs 搜索"; window.minSize=NSMakeSize(600,420); window.releasedWhenClosed=NO; [window center];
    NSView *content=window.contentView;
    NSArray *titles=@[@"‹",@"›",@"刷新",@"搜索首页"];
    SEL actions[]={@selector(back:),@selector(forward:),@selector(reload:),@selector(home:)};
    CGFloat x=12;
    for (NSUInteger i=0;i<titles.count;i++) {
        CGFloat width=i<2?34:(i==2?52:78);
        NSButton *button=[NSButton buttonWithTitle:titles[i] target:self action:actions[i]];
        button.frame=NSMakeRect(x,NSHeight(content.bounds)-39,width,27);
        button.autoresizingMask=NSViewMinYMargin; [content addSubview:button]; x+=width+6;
    }
    WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
    configuration.websiteDataStore=WKWebsiteDataStore.nonPersistentDataStore;
    self.web=[[WKWebView alloc] initWithFrame:NSMakeRect(0,0,NSWidth(content.bounds),NSHeight(content.bounds)-45) configuration:configuration];
    self.web.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.web.UIDelegate=self; [content addSubview:self.web];
    return self;
}
- (void)back:(id)sender { [self.web goBack]; }
- (void)forward:(id)sender { [self.web goForward]; }
- (void)reload:(id)sender { [self.web reload]; }
- (void)home:(id)sender { [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://mbs.ddxmu.com/sousuo/"]]]; }
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
  forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    if (!action.targetFrame) [webView loadRequest:action.request];
    return nil;
}
@end

void MbsOpenWebSearch(void) {
    static MbsWebSearchWindow *controller;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!controller) controller=[MbsWebSearchWindow new];
        [controller home:nil];
        [controller showWindow:nil]; [controller.window makeKeyAndOrderFront:nil];
    });
}
