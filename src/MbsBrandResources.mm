#include <dlfcn.h>
#include <mach-o/getsect.h>
#include <stdint.h>

struct MbsResourceString { const void *data; };
static const struct { int ref,len; unsigned allocation,padding; int64_t offset; unsigned short end; }
    MbsEmptyResourceString={-1,0,0,0,24,0};
bool MbsRegisterQtResource(const unsigned char *,const MbsResourceString &)
    __asm__("__ZN6kso_qt9QResource16registerResourceEPKhRKNS_7QStringE");

static bool MbsRegisterBrandingResource(const unsigned char *bytes) {
    return MbsRegisterQtResource(bytes,{&MbsEmptyResourceString});
}

#ifndef MBS_BRAND_RESOURCE_TEST
// Register our wordmark aliases and AI icons before the external themes load.
// Module-only updates then carry the same artwork as the full local installer.
__attribute__((constructor)) static void MbsInstallBrandingResource(void) {
    Dl_info image; unsigned long size=0;
    if (!dladdr((const void *)MbsInstallBrandingResource,&image)) return;
    const unsigned char *bytes=getsectiondata((const struct mach_header_64 *)image.dli_fbase,
                                            "__TEXT","__mbs_brand",&size);
    if (bytes && size>=20) MbsRegisterBrandingResource(bytes);
}
#endif
