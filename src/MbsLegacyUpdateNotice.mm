#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <dlfcn.h>

static NSString *MbsCompactNotice(NSString *text) {
    return [[text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        componentsJoinedByString:@""];
}

static BOOL MbsIsLegacyUpdateNotice(NSAlert *alert, NSString *image, NSString *bundle) {
    if (![image hasPrefix:[bundle stringByAppendingString:@"/"]] ||
        ![image hasSuffix:@"/office6/kprometheus.framework/Versions/A/kprometheus"] ||
        alert.buttons.count != 1) return NO;
    NSString *title=MbsCompactNotice(alert.messageText);
    BOOL oldTitle=[@[@"MbsOffice正在更新",@"WPSOffice正在更新",@"MbsOfficeisupdating",@"WPSOfficeisupdating"] containsObject:title];
    if (!oldTitle) return NO;
    NSString *detail=MbsCompactNotice(alert.informativeText);
    return [detail isEqual:MbsCompactNotice(@"软件更新中，此功能暂时无法使用。你可在 App Store查看更新进度，并重启应用以完成更新。")] ||
        [detail isEqual:MbsCompactNotice(@"The software is updating, so this feature is temporarily unavailable. You can check the update progress in the App Store and restart the app to complete the update.")];
}

static IMP MbsOriginalAlertRunModal;
static NSModalResponse MbsRunAlert(id alert, SEL action) {
    Dl_info caller={};
    if (dladdr(__builtin_return_address(0),&caller) && caller.dli_fname &&
        MbsIsLegacyUpdateNotice(alert,@(caller.dli_fname),NSBundle.mainBundle.bundlePath)) {
        // This obsolete App Store notice has one acknowledgement button.
        // Mbs updates are handled by MbsUpdates and its signed installer.
        return NSAlertFirstButtonReturn;
    }
    return ((NSModalResponse (*)(id,SEL))MbsOriginalAlertRunModal)(alert,action);
}

#ifndef MBS_LEGACY_UPDATE_NOTICE_TEST
__attribute__((constructor)) static void MbsInstallLegacyUpdateNoticeRouting(void) {
    Method method=class_getInstanceMethod(NSAlert.class,@selector(runModal));
    MbsOriginalAlertRunModal=method_setImplementation(method,(IMP)MbsRunAlert);
}
#endif
