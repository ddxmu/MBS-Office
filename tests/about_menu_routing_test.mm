#import "../src/MbsAbout.mm"
#include <assert.h>
static int updates, delegated;
void MbsShowStartupRepair(void) {}
extern "C" void MbsShowUpdates(void) { updates++; }
static BOOL fallback(id self,SEL selector,SEL action,id target,id sender) { delegated++; return NO; }
int main(void) { @autoreleasepool {
    MbsSendActionOriginal=(IMP)fallback;
    for (NSString *title in @[@"软件更新…",@"软件更新...",@"Software Update…"]) {
        NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        assert(MbsSendAction(nil,nullptr,nullptr,nil,item));
    }
    assert(updates==3 && delegated==0);
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:@"其他操作" action:nil keyEquivalent:@""];
    assert(!MbsSendAction(nil,nullptr,nullptr,nil,item) && delegated==1);
    puts("PASS: software update menu variants route to Mbs updater; unrelated actions preserved");
} }
