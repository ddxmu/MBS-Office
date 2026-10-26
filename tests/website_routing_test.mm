#import "../src/MbsWebsiteRouting.h"
#include <assert.h>
int main() { @autoreleasepool {
    for (NSString *address in @[@"http://www.docer.com/?from=wps_func_wppsp",@"https://help.wps.cn/help",@"https://plus.wps.cn/",@"https://WPS.COM/",@"https://www.kdocs.cn/",@"https://www.wps365.com/"]) {
        assert(MbsIsLegacyWebsiteURL([NSURL URLWithString:address]));
    }
    for (NSString *address in @[@"https://mbs.ddxmu.com/",@"https://ttys.ddxmu.com/api/mbs",@"https://notwps.cn/",@"https://wps.cn.example.org/",@"file:///tmp/wps.cn",@"https://example.org/?url=https://wps.cn/"]) {
        assert(!MbsIsLegacyWebsiteURL([NSURL URLWithString:address]));
    }
    assert(!MbsIsLegacyWebsiteURL(nil));
    puts("PASS built-in website host boundaries; Mbs services, local files and unrelated domains preserved");
} }
