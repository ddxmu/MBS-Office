#include <stdint.h>
#include <string.h>
#include "MbsEditorAuthorization.h"

namespace kso_qt { class QStringList; }
bool nativePdfPrivilege(const void *, const kso_qt::QStringList &)
    __asm__("__ZNK11KMemberUser14checkPrivilegeERKN6kso_qt11QStringListE");

// QtKso 5.12.12 / editor 12.1.25867: QList<QString> stores pointer-sized
// QString values in its node array. Do not modify the list or its refcounts.
static bool pdfEditingPrivileges(const kso_qt::QStringList &privileges)
{
    const int32_t *list = *reinterpret_cast<const int32_t *const *>(&privileges);
    const int32_t begin = list[2], end = list[3];
    if (begin < 0 || end <= begin || end > list[1]) return false;
    const auto *items = reinterpret_cast<const unsigned char *const *>(list + 4);
    for (int32_t i = begin; i < end; ++i) {
        const unsigned char *data = items[i];
        int32_t length = *reinterpret_cast<const int32_t *>(data + 4);
        intptr_t offset = *reinterpret_cast<const intptr_t *>(data + 16);
        const uint16_t *text = reinterpret_cast<const uint16_t *>(data + offset);
        bool matched = false;
        // pdfmain maps edit-content operations to these exact privilege IDs.
        const char *keys[] = {"pdf_edit", "pdf_text_edit", "pdf_pic_edit"};
        for (const char *key : keys) {
            if (length != static_cast<int32_t>(strlen(key))) continue;
            int32_t j = 0;
            while (j < length && text[j] == static_cast<unsigned char>(key[j])) ++j;
            if (j == length) { matched = true; break; }
        }
        if (!matched) return false;
    }
    return true;
}

static bool mbsPdfPrivilege(const void *user, const kso_qt::QStringList &privileges)
{
    if (pdfEditingPrivileges(privileges) && MbsHasVerifiedEditorLicense()) return true;
    return nativePdfPrivilege(user, privileges);
}

struct PdfInterpose { const void *replacement; const void *original; };
__attribute__((used, section("__DATA,__interpose")))
static const PdfInterpose pdfEditing = {
    reinterpret_cast<const void *>(&mbsPdfPrivilege),
    reinterpret_cast<const void *>(&nativePdfPrivilege)
};
