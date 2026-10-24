#define MBS_LEGACY_UPDATE_NOTICE_TEST
#import "../src/MbsLegacyUpdateNotice.mm"
#include <assert.h>

int main(void) { @autoreleasepool {
    NSString *bundle=@"/Applications/Mbs Office.app/Contents/Resources/MbsEngine.app";
    NSString *image=[bundle stringByAppendingString:@"/Contents/Frameworks/office6/kprometheus.framework/Versions/A/kprometheus"];
    NSAlert *alert=[NSAlert new];
    alert.messageText=@"Mbs Office 正在更新";
    alert.informativeText=@"软件更新中，此功能暂时无法使用。\n你可在 App Store查看更新进度，并重启应用以完成更新。";
    [alert addButtonWithTitle:@"我知道了"];
    assert(MbsIsLegacyUpdateNotice(alert,image,bundle));
    assert(!MbsIsLegacyUpdateNotice(alert,@"/System/Library/AppKit",bundle));
    assert(!MbsIsLegacyUpdateNotice(alert,[@"/other" stringByAppendingString:image],bundle));
    alert.messageText=@"Mbs Office 版本升级";
    assert(!MbsIsLegacyUpdateNotice(alert,image,bundle));
    alert.messageText=@"Mbs Office 正在更新";
    alert.informativeText=@"安装包校验失败，请重新下载。";
    assert(!MbsIsLegacyUpdateNotice(alert,image,bundle));
    alert.messageText=@"WPS Office is updating";
    alert.informativeText=@"The software is updating, so this feature is temporarily unavailable. You can check the update progress in the App Store and restart the app to complete the update.";
    assert(MbsIsLegacyUpdateNotice(alert,image,bundle));
    [alert addButtonWithTitle:@"取消"];
    assert(!MbsIsLegacyUpdateNotice(alert,image,bundle));
    puts("PASS: exact bundled legacy notice only; Mbs updates, other callers, other errors and multi-button alerts preserved");
} }
