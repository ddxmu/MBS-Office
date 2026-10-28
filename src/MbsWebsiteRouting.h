#import <Foundation/Foundation.h>

static NSString *const MbsWebsiteHome = @"https://mbs.ddxmu.com/";
static NSString *const MbsFeedbackURL = @"https://t.me/+uEp8JOn7Oic0MDdl";

static BOOL MbsIsLegacyWebsiteHost(NSString *host) {
    NSString *value=host.lowercaseString;
    for (NSString *domain in @[@"wps.cn",@"wps.com",@"wps365.com",@"docer.com",@"docer.cn",@"kdocs.cn",@"kingsoft.com"]) {
        if ([value isEqualToString:domain] || [value hasSuffix:[@"." stringByAppendingString:domain]]) return YES;
    }
    return NO;
}

static BOOL MbsIsLegacyWebsiteURL(NSURL *url) {
    NSString *scheme=url.scheme.lowercaseString;
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) &&
        MbsIsLegacyWebsiteHost(url.host);
}
