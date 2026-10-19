#import <AppKit/AppKit.h>

namespace kso_qt {
class __attribute__((visibility("hidden"))) QString {
public:
    const void *data;
    explicit QString(const void *value):data(value) {}
    ~QString() {}
    __attribute__((visibility("default"))) QString &operator=(const QString &);
};
class QLibrary {
public:
    bool load();
    QString fileName() const;
    void setFileName(const QString &);
};
}
namespace kpluginconfig { kso_qt::QString getPluginPath(const kso_qt::QString &, const kso_qt::QString &); }
namespace krt { namespace pluginconfig {
kso_qt::QString getPluginPath(const kso_qt::QString &, const kso_qt::QString &);
kso_qt::QString getPluginResourcePath(const kso_qt::QString &, const kso_qt::QString &);
} }
bool libraryLoadOriginal(void *) __asm__("__ZN6kso_qt8QLibrary4loadEv");
struct StringData { int ref, length; unsigned allocation,padding; long offset; };
static NSString *stringValue(const kso_qt::QString &value) {
    const auto *header=(const StringData *)value.data;
    if (!header || header->length<0) return nil;
    return [[NSString alloc] initWithCharacters:(const unichar *)((const char*)header+header->offset) length:header->length];
}
static kso_qt::QString literal(NSString *value) {
    static NSMutableDictionary<NSString*,NSValue*> *values;
    static dispatch_once_t once;dispatch_once(&once,^{values=[NSMutableDictionary dictionary];});
    @synchronized(values) {
        if (!values[value]) {
            auto *data=(StringData*)calloc(1,24+(value.length+1)*2);
            data->ref=-1;data->length=(int)value.length;data->offset=24;
            [value getCharacters:(unichar*)(data+1) range:NSMakeRange(0,value.length)];
            values[value]=[NSValue valueWithPointer:data];
        }
        return kso_qt::QString(values[value].pointerValue);
    }
}
static NSString *bundledAddon(NSString *value) {
    // The copied bundle's plugin registry sometimes omits the install root.
    // Resolve only existing vendor addons within this bundle; never search the host.
    if (![value hasPrefix:@"/addons/"]) return nil;
    NSString *lower = value.lowercaseString;
    if ([lower hasPrefix:@"/addons/knewdocs/"] ||
        [lower hasPrefix:@"/addons/kpromeaccountpanel/"] ||
        [lower hasPrefix:@"/addons/klingxidockpanel/"]) {
        // Mbs owns the start page and account flow. Keep the editor core intact,
        // but prevent legacy remote pages and the old robot assistant panel from loading.
        return @"/__mbs_disabled_remote_addon__";
    }
    NSString *base=[NSBundle.mainBundle.privateFrameworksPath stringByAppendingPathComponent:@"office6"];
    NSString *candidate=[[base stringByAppendingString:value] stringByStandardizingPath];
    if (![candidate hasPrefix:[base stringByAppendingString:@"/"]] ||
        ![NSFileManager.defaultManager fileExistsAtPath:candidate]) return nil;
    return candidate;
}
static NSString *bundledResource(NSString *value) {
    if (![value hasPrefix:@"/addons/"]) return nil;
    NSString *lower = value.lowercaseString;
    if ([lower hasPrefix:@"/addons/knewdocs/"] ||
        [lower hasPrefix:@"/addons/kpromeaccountpanel/"] ||
        [lower hasPrefix:@"/addons/klingxidockpanel/"]) {
        return @"/__mbs_disabled_remote_addon__";
    }
    NSString *base=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"office6"];
    NSString *candidate=[[base stringByAppendingString:value] stringByStandardizingPath];
    if (![candidate hasPrefix:[base stringByAppendingString:@"/"]] ||
        ![NSFileManager.defaultManager fileExistsAtPath:candidate]) return nil;
    return candidate;
}
static void tracePluginPath(NSString *source, NSString *name, NSString *host, NSString *path, NSString *corrected) {
    if (!getenv("MBS_PLUGIN_TRACE")) return;
    NSString *line=[NSString stringWithFormat:@"%@ name=%@ host=%@ path=%@ corrected=%@\n",
                    source ?: @"?", name ?: @"", host ?: @"", path ?: @"", corrected ?: @"-"];
    int fd=open("/tmp/mbs-plugin-paths.log", O_WRONLY|O_CREAT|O_APPEND, 0600);
    if (fd>=0) { write(fd, line.UTF8String, [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding]); close(fd); }
}
static kso_qt::QString pluginPath(const kso_qt::QString &name,const kso_qt::QString &host) {
    auto path=kpluginconfig::getPluginPath(name,host);
    NSString *raw=stringValue(path);
    NSString *corrected=bundledAddon(raw);
    tracePluginPath(@"kpluginconfig",stringValue(name),stringValue(host),raw,corrected);
    if (!corrected) return path;
    path=literal(@"");
    return literal(corrected);
}
static kso_qt::QString krtPluginPath(const kso_qt::QString &name,const kso_qt::QString &host) {
    auto path=krt::pluginconfig::getPluginPath(name,host);
    NSString *raw=stringValue(path);
    NSString *corrected=bundledAddon(raw);
    tracePluginPath(@"krt",stringValue(name),stringValue(host),raw,corrected);
    if (!corrected) return path;
    path=literal(@"");
    return literal(corrected);
}
static kso_qt::QString krtPluginResourcePath(const kso_qt::QString &name,const kso_qt::QString &host) {
    auto path=krt::pluginconfig::getPluginResourcePath(name,host);
    NSString *raw=stringValue(path);
    NSString *corrected=bundledResource(raw);
    tracePluginPath(@"krt-resource",stringValue(name),stringValue(host),raw,corrected);
    if (!corrected) return path;
    path=literal(@"");
    return literal(corrected);
}
static bool loadBundledLibrary(kso_qt::QLibrary *library) {
    auto path=library->fileName();
    NSString *corrected=bundledAddon(stringValue(path));
    path=literal(@"");
    if (corrected) library->setFileName(literal(corrected));
    return library->load();
}
struct Interpose { const void *replacement; const void *original; };
__attribute__((used,section("__DATA,__interpose"))) static const Interpose paths[]={
    {(const void*)&pluginPath,(const void*)&kpluginconfig::getPluginPath},
    {(const void*)&krtPluginPath,(const void*)&krt::pluginconfig::getPluginPath},
    {(const void*)&krtPluginResourcePath,(const void*)&krt::pluginconfig::getPluginResourcePath},
    {(const void*)&loadBundledLibrary,(const void*)&libraryLoadOriginal}
};
