#include "../src/MbsLegacyKeychain.mm"
int main() { @autoreleasepool {
    NSString *bundle=@"/Applications/Mbs Office.app/Contents/Resources/MbsEngine.app";
    assert(MbsIsLegacyCipherCaller([bundle stringByAppendingPathComponent:@"Contents/Frameworks/office6/Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework"],bundle));
    assert(!MbsIsLegacyCipherCaller(@"/Applications/Other.app/Chromium Embedded Framework",bundle));
    assert(!MbsIsLegacyCipherCaller([bundle stringByAppendingPathComponent:@"Contents/MacOS/MbsOfflineFlags.dylib"],bundle));
    assert(!MbsIsLegacyCipherCaller(@"/System/Library/Frameworks/Security.framework/Security",bundle));
    puts("PASS: only this bundled legacy browser is declined; other callers remain unchanged");
} return 0; }
