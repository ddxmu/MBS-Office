#import <AppKit/AppKit.h>

// The observed Qt 5 string ABI is one data pointer. Only immutable data is
// returned here; hidden methods cannot replace Qt's real string implementation.
namespace kso_qt {
class __attribute__((visibility("hidden"))) QString {
public:
    const void *data;
    explicit QString(const void *value) : data(value) {}
    ~QString() {}
    __attribute__((visibility("default"))) QString &operator=(const QString &other);
};
}
namespace krt { namespace dirs {
    kso_qt::QString kingsoftHome();
    kso_qt::QString localKingsoftHome();
} }

struct ImmutableStringData {
    int referenceCount, length;
    unsigned allocation, padding;
    long offset;
};
static_assert(sizeof(ImmutableStringData) == 24, "Unexpected string layout");

static const void *profileStringData()
{
    static const void *data;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *base = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                             NSUserDomainMask, YES).firstObject;
        NSString *path = [base stringByAppendingPathComponent:@"Mbs Office/Storage"];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                withIntermediateDirectories:YES attributes:nil error:&error]) {
            fputs("Mbs Office cannot create its independent data directory.\n", stderr);
            abort();
        }
        NSUInteger length = path.length;
        auto *header = static_cast<ImmutableStringData *>(calloc(1, 24+(length+1)*2));
        header->referenceCount = -1; // Immutable Qt literal; storage lasts for this process.
        header->length = static_cast<int>(length);
        header->offset = 24;
        [path getCharacters:reinterpret_cast<unichar *>(header+1)
                      range:NSMakeRange(0,length)];
        data = header;
    });
    return data;
}
static kso_qt::QString independentProfile()
{
    return kso_qt::QString(profileStringData());
}
struct ProfileInterpose { const void *replacement; const void *original; };
__attribute__((used, section("__DATA,__interpose")))
static const ProfileInterpose profilePaths[] = {
    {reinterpret_cast<const void *>(&independentProfile),
     reinterpret_cast<const void *>(&krt::dirs::kingsoftHome)},
    {reinterpret_cast<const void *>(&independentProfile),
     reinterpret_cast<const void *>(&krt::dirs::localKingsoftHome)}
};

// Translate program UI strings only. Document text and internal product keys are not changed.
kso_qt::QString metaTranslateOriginal(const void *, const char *, const char *, int)
    __asm__("__ZNK6kso_qt11QMetaObject2trEPKcS2_i");
namespace kso_qt {
class QCoreApplication {
public:
    static QString translate(const char *, const char *, const char *, int);
};
class QMetaObject {
public:
    QString tr(const char *, const char *, int) const;
    const char *className() const;
};
}
namespace krt { namespace product {
    kso_qt::QString brandLogoString(const kso_qt::QString &);
} }
static NSString *readUiString(const kso_qt::QString &value)
{
    const auto *header = static_cast<const ImmutableStringData *>(value.data);
    if (!header || header->length < 0) return nil;
    const auto *text = reinterpret_cast<const unichar *>(
        reinterpret_cast<const char *>(header)+header->offset);
    return [[NSString alloc] initWithCharacters:text length:header->length];
}
static kso_qt::QString uiString(NSString *text)
{
    static NSMutableDictionary<NSString *, NSValue *> *strings;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ strings = [NSMutableDictionary dictionary]; });
    @synchronized (strings) {
        NSValue *stored = strings[text];
        if (stored) return kso_qt::QString(stored.pointerValue);
        NSUInteger length = text.length;
        auto *header = static_cast<ImmutableStringData *>(calloc(1, 24+(length+1)*2));
        header->referenceCount = -1;
        header->length = static_cast<int>(length);
        header->offset = 24;
        [text getCharacters:reinterpret_cast<unichar *>(header+1) range:NSMakeRange(0,length)];
        strings[text] = [NSValue valueWithPointer:header];
        return kso_qt::QString(header);
    }
}
static bool isLegalText(NSString *text)
{
    NSString *lower = text.lowercaseString;
    for (NSString *word in @[@"copyright", @"license", @"licence", @"privacy", @"eula", @"agreement", @"terms", @"trademark", @"legal", @"服务条款", @"商标", @"©", @"版权所有", @"许可", @"协议", @"隱私", @"隱私權", @"隐私", @"著作権", @"ライセンス"])
        if ([lower containsString:word]) return true;
    return false;
}
static kso_qt::QString rebrandUi(kso_qt::QString &translated, const char *context,
                                const char *source, const char *comment)
{
    NSString *text = readUiString(translated);
    NSString *sourceText = source ? [NSString stringWithUTF8String:source] : @"";
    NSString *contextText = context ? [NSString stringWithUTF8String:context] : @"";
    if ([text containsString:@"免费使用企业版"] && !isLegalText(text)) {
        NSString *updated = [text stringByReplacingOccurrencesOfString:@"免费使用企业版" withString:@"版本升级"];
        translated = uiString(@"");
        return uiString(updated);
    }
    if ([text containsString:@"灵犀"] && !isLegalText(text)) {
        // The legacy assistant entry is removed from Mbs Office. Returning an
        // empty UI string prevents its sidebar/menu label from being shown.
        translated = uiString(@"");
        return uiString(@"");
    }
    if ([text containsString:@"WPS"] && !isLegalText(text) &&
        !isLegalText(sourceText) && !isLegalText(contextText) &&
        !(comment && isLegalText([NSString stringWithUTF8String:comment]))) {
        NSString *updated = [text stringByReplacingOccurrencesOfString:@"WPS AI" withString:@"AI"];
        updated = [updated stringByReplacingOccurrencesOfString:@"WPS" withString:@"Mbs"];
        translated = uiString(@"");
        return uiString(updated);
    }
    return translated;
}
static kso_qt::QString translateUi(const char *context, const char *source,
                                   const char *comment, int plural)
{
    auto translated = kso_qt::QCoreApplication::translate(context,source,comment,plural);
    return rebrandUi(translated,context,source,comment);
}
static kso_qt::QString translateMeta(const kso_qt::QMetaObject *meta, const char *source,
                                    const char *comment, int plural)
{
    auto translated = meta->tr(source,comment,plural);
    return rebrandUi(translated,meta->className(),source,comment);
}
static kso_qt::QString productTitle(const kso_qt::QString &key)
{
    if ([readUiString(key) isEqualToString:@"BrandWPSOffice"])
        return uiString(@"Mbs Office");
    return krt::product::brandLogoString(key);
}
__attribute__((used, section("__DATA,__interpose")))
static const ProfileInterpose uiText[] = {
    {reinterpret_cast<const void *>(&translateUi),
     reinterpret_cast<const void *>(&kso_qt::QCoreApplication::translate)},
    {reinterpret_cast<const void *>(&translateMeta),
     reinterpret_cast<const void *>(&metaTranslateOriginal)},
    {reinterpret_cast<const void *>(&productTitle),
     reinterpret_cast<const void *>(&krt::product::brandLogoString)}
};

// Cocoa reads the localized bundle name for the macOS application menu.
static CFTypeRef applicationDisplayName(CFBundleRef bundle, CFStringRef key)
{
    if (bundle == CFBundleGetMainBundle() && key && CFEqual(key,CFSTR("CFBundleName")))
        return CFSTR("Mbs Office");
    return CFBundleGetValueForInfoDictionaryKey(bundle,key);
}
__attribute__((used, section("__DATA,__interpose")))
static const ProfileInterpose cocoaDisplayName = {
    reinterpret_cast<const void *>(&applicationDisplayName),
    reinterpret_cast<const void *>(&CFBundleGetValueForInfoDictionaryKey)
};
