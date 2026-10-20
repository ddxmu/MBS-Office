#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <dlfcn.h>

static unsigned MbsLegacyKeychainDenials;
extern "C" unsigned MbsLegacyKeychainDeniedCount(void) {
    return __atomic_load_n(&MbsLegacyKeychainDenials,__ATOMIC_RELAXED);
}
static BOOL MbsIsLegacyCipherCaller(NSString *caller, NSString *bundle) {
    return [caller hasPrefix:[bundle stringByAppendingString:@"/"]] &&
        [caller.lastPathComponent isEqualToString:@"Chromium Embedded Framework"];
}
static OSStatus MbsFindGenericPassword(CFTypeRef keychain, UInt32 serviceLength, const char *service,
    UInt32 accountLength, const char *account, UInt32 *passwordLength, void **password, SecKeychainItemRef *item) {
    Dl_info image;
    if (dladdr(__builtin_return_address(0),&image) && image.dli_fname) { @autoreleasepool {
        if ([NSBundle.mainBundle.executablePath.lastPathComponent isEqualToString:@"wpsoffice"] &&
            MbsIsLegacyCipherCaller(@(image.dli_fname),NSBundle.mainBundle.bundlePath)) {
            // Decline the obsolete browser profile's read. Never supply a key,
            // grant access, or change the keychain's encryption or permissions.
            if (passwordLength) *passwordLength = 0;
            if (password) *password = NULL;
            if (item) *item = NULL;
            __atomic_add_fetch(&MbsLegacyKeychainDenials,1,__ATOMIC_RELAXED);
            return errSecInteractionNotAllowed;
        }
    } }
    return SecKeychainFindGenericPassword(keychain,serviceLength,service,accountLength,account,passwordLength,password,item);
}
struct MbsKeychainInterpose { const void *replacement, *original; };
__attribute__((used,section("__DATA,__interpose"))) static const MbsKeychainInterpose legacyRead = {
    (const void *)&MbsFindGenericPassword,(const void *)&SecKeychainFindGenericPassword
};
