#include <assert.h>
#include <stdio.h>
#include "../src/MbsPdfPrivileges.cpp"

namespace kso_qt { class QStringList { public: const void *data; }; }
static bool active, nativeResult;
static int nativeCalls;
extern "C" bool MbsHasVerifiedEditorLicense() { return active; }
bool nativePdfPrivilege(const void *, const kso_qt::QStringList &) {
    ++nativeCalls; return nativeResult;
}
struct StringData {
    int32_t ref = -1, length = 0, allocation = 0, padding = 0;
    intptr_t offset = 24;
    uint16_t text[64] = {};
    explicit StringData(const char *key) {
        length = (int32_t)strlen(key);
        assert(length < 64);
        for (int i=0; i<length; ++i) text[i] = key[i];
    }
};
struct ListData { int32_t ref = -1, allocation = 4, begin = 0, end = 1; const void *items[4]; };
int main() {
    StringData edit("pdf_edit"), text("pdf_text_edit"), picture("pdf_pic_edit"), stamp("pdf_stamp"), other("pdf_ocr");
    ListData data; data.items[0] = &text;
    kso_qt::QStringList list{&data};
    active = true;
    assert(mbsPdfPrivilege(nullptr,list) && nativeCalls == 0);
    data.items[0] = &edit; assert(mbsPdfPrivilege(nullptr,list));
    data.items[0] = &picture; assert(mbsPdfPrivilege(nullptr,list));
    data.items[0] = &stamp; assert(mbsPdfPrivilege(nullptr,list));
    active = false; nativeResult = true;
    assert(!mbsPdfPrivilege(nullptr,list) && nativeCalls == 0);
    nativeResult = false;
    active = true; nativeCalls = 0;
    data.begin = 1; data.end = 3; data.items[1] = &edit; data.items[2] = &text;
    assert(mbsPdfPrivilege(nullptr,list));
    data.items[1] = &stamp; assert(mbsPdfPrivilege(nullptr,list));
    data.items[2] = &other;
    assert(!mbsPdfPrivilege(nullptr,list) && nativeCalls == 1);
    nativeResult = true;
    assert(mbsPdfPrivilege(nullptr,list) && nativeCalls == 2);
    nativeResult = false; active = false; data.items[2] = &text;
    assert(!mbsPdfPrivilege(nullptr,list) && nativeCalls == 2);
    active = true; data.end = data.begin;
    assert(!mbsPdfPrivilege(nullptr,list) && nativeCalls == 3);
    puts("PASS: PDF editing and stamps use only Mbs authorization, inactive Mbs cannot fall back to native rights, unrelated permissions unchanged");
}
