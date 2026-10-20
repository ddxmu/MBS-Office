// Mbs-owned authorization is verified independently of vendor subscriptions.
#include <string.h>
#include <stdint.h>
#include "MbsEditorAuthorization.h"

namespace kso_qt { class QString; }
namespace krt { namespace kcmc {
bool enable(const char *name);
bool support(const char *name);
bool support(const kso_qt::QString &name);
bool enable(const kso_qt::QString &name);
} }

static bool localFeatureEnabled(const char *name)
{
    if (name && strcmp(name, "CloudDocs") == 0)
        return false;
    return krt::kcmc::enable(name);
}

// Loaded by the main application only; helper programs remain unchanged.
// Helpers remain unchanged; the editor adapter queries one Mbs-specific key.
struct Interpose { const void *replacement; const void *original; };
__attribute__((used, section("__DATA,__interpose")))
static const Interpose offlineFeatures = {
    reinterpret_cast<const void *>(&localFeatureEnabled),
    reinterpret_cast<const void *>(static_cast<bool(*)(const char*)>(&krt::kcmc::enable))
};

static const char *disabledSupport[] = {
    "BrandWPSOfficeTitle", "WpsCloudDiskTab", "CloudFilePageVisible",
    "PdfStartPageFileListShowCloudUDisk", "PdfStartPageFileListMenuOpenCloudDisk",
    "PromeDocerTabButton", "CommonTouchBarDocer", "PrefsWidgetShowDocer",
    "DocercoreLoadInApp", "DocerresourceShopLoadTaskPane", "DocerEntrance",
    "DocerMall", "RbDocerMall", "DocerShop", "NewFromDocerTemplate"
};
static bool localBrandSupported(const char *name)
{
    if (name) {
        if (strcmp(name, "MbsEditorLicenseVerified") == 0) return MbsHasVerifiedEditorLicense();
        if (strcmp(name, "WppNewSlideNoDocer") == 0) return true;
        for (const char *key : disabledSupport) if (strcmp(name,key) == 0) return false;
    }
    return krt::kcmc::support(name);
}
__attribute__((used, section("__DATA,__interpose")))
static const Interpose localBrand = {
    reinterpret_cast<const void *>(&localBrandSupported),
    reinterpret_cast<const void *>(static_cast<bool(*)(const char*)>(&krt::kcmc::support))
};

// QString overloads use the same feature decisions. Read-only ABI confirmed
// against the exact WPS/Qt build; the document cores are not changed.
static bool sameFeature(const kso_qt::QString &value, const char *key)
{
    const unsigned char *data = *reinterpret_cast<const unsigned char *const *>(&value);
    int length = *reinterpret_cast<const int *>(data+4);
    if (length != static_cast<int>(strlen(key))) return false;
    intptr_t offset = *reinterpret_cast<const intptr_t *>(data+16);
    const uint16_t *text = reinterpret_cast<const uint16_t *>(data+offset);
    for (int i=0; i<length; ++i) if (text[i] != static_cast<unsigned char>(key[i])) return false;
    return true;
}
static bool localStringEnabled(const kso_qt::QString &name)
{
    if (sameFeature(name, "CloudDocs")) return false;
    return krt::kcmc::enable(name);
}
static bool localStringSupported(const kso_qt::QString &name)
{
    if (sameFeature(name, "MbsEditorLicenseVerified")) return MbsHasVerifiedEditorLicense();
    if (sameFeature(name, "WppNewSlideNoDocer")) return true;
    for (const char *key : disabledSupport) if (sameFeature(name,key)) return false;
    return krt::kcmc::support(name);
}
__attribute__((used, section("__DATA,__interpose")))
static const Interpose stringFeatures[] = {
    {reinterpret_cast<const void *>(&localStringEnabled),
     reinterpret_cast<const void *>(static_cast<bool(*)(const kso_qt::QString&)>(&krt::kcmc::enable))},
    {reinterpret_cast<const void *>(&localStringSupported),
     reinterpret_cast<const void *>(static_cast<bool(*)(const kso_qt::QString&)>(&krt::kcmc::support))}
};
