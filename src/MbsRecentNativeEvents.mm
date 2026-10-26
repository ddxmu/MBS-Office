#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/vm_prot.h>
#include <stdint.h>
#include <string.h>
#import "MbsRecentNativeEvents.h"

extern "C" void MbsRecordRecentDocumentPath(const char *path);
void MbsRecentOriginalActivate(void *,const void *,int,void **)
    __asm__("__ZN6kso_qt11QMetaObject8activateEPNS_7QObjectEPKS0_iPPv");

static const void *MbsRecentNativeMeta;
static const void *MbsRecentNativeImage;
static thread_local bool MbsRecentRecording;
static const unsigned char MbsRecentImageUUID[]={
    0x2a,0xa8,0x8e,0x20,0x1f,0xea,0x3d,0xb9,0xaf,0xdc,0x78,0x61,0x1b,0x56,0xd4,0x3e};
static const unsigned char MbsRecentPathGetterCode[]={
    0x09,0x48,0x40,0xf9,0x09,0x01,0x00,0xf9,0x28,0x01,0x40,0xb9,
    0x08,0x05,0x00,0x51,0x1f,0x0d,0x00,0x31,0x68,0x00,0x00,0x54,
    0x28,0x00,0x80,0x52,0x28,0x01,0xe8,0xb8,0xc0,0x03,0x5f,0xd6};
static const uintptr_t MbsRecentMetaRVA=0x8f4058, MbsRecentPathGetterRVA=0x14cfb4;

static bool MbsRecentSegmentContains(const segment_command_64 *segment,uintptr_t address,
    size_t size,int protection) {
    return (segment->initprot&protection)==protection && address>=segment->vmaddr &&
        size<=segment->vmsize && address-segment->vmaddr<=segment->vmsize-size;
}
static bool MbsBindRecentNativeImage(const mach_header *image,const char *path) {
    if (!image || !path) return false;
    const char *framework=strstr(path,"/kprometheus.framework/");
    const char *name=strrchr(path,'/');
    if (!framework || !name || strcmp(name+1,"kprometheus")) return false;
    const auto *header=(const mach_header_64 *)image;
    if (header->magic!=MH_MAGIC_64 || header->cputype!=CPU_TYPE_ARM64 ||
        !header->ncmds || header->ncmds>128 || header->sizeofcmds>65536 ||
        header->sizeofcmds<header->ncmds*sizeof(load_command)) return false;
    const auto *cursor=(const unsigned char *)(header+1);
    const auto *end=cursor+header->sizeofcmds;
    bool uuid=false, text=false, getter=false, meta=false;
    for (uint32_t index=0;index<header->ncmds;++index) {
        if ((size_t)(end-cursor)<sizeof(load_command)) return false;
        const auto *command=(const load_command *)cursor;
        if (command->cmdsize<sizeof(load_command) || command->cmdsize>(size_t)(end-cursor)) return false;
        if (command->cmd==LC_UUID) {
            if (command->cmdsize<sizeof(uuid_command)) return false;
            uuid=!memcmp(((const uuid_command *)command)->uuid,MbsRecentImageUUID,sizeof(MbsRecentImageUUID));
        }
        if (command->cmd==LC_SEGMENT_64) {
            if (command->cmdsize<sizeof(segment_command_64)) return false;
            const auto *segment=(const segment_command_64 *)command;
            if (!strncmp(segment->segname,"__TEXT",16) && segment->vmaddr==0) text=true;
            getter=getter || MbsRecentSegmentContains(segment,MbsRecentPathGetterRVA,
                sizeof(MbsRecentPathGetterCode),VM_PROT_READ|VM_PROT_EXECUTE);
            meta=meta || MbsRecentSegmentContains(segment,MbsRecentMetaRVA,sizeof(void *),VM_PROT_READ);
        }
        cursor+=command->cmdsize;
    }
    if (!uuid || !text || !getter || !meta || memcmp((const unsigned char *)image+
        MbsRecentPathGetterRVA,MbsRecentPathGetterCode,sizeof(MbsRecentPathGetterCode))) return false;
    __atomic_store_n(&MbsRecentNativeImage,(const void *)image,__ATOMIC_RELEASE);
    __atomic_store_n(&MbsRecentNativeMeta,(const unsigned char *)image+MbsRecentMetaRVA,__ATOMIC_RELEASE);
    return true;
}
static void MbsRemoveRecentNativeImage(const mach_header *image,intptr_t) {
    if (__atomic_load_n(&MbsRecentNativeImage,__ATOMIC_ACQUIRE)!=(const void *)image) return;
    __atomic_store_n(&MbsRecentNativeMeta,(const void *)nullptr,__ATOMIC_RELEASE);
    __atomic_store_n(&MbsRecentNativeImage,(const void *)nullptr,__ATOMIC_RELEASE);
}
static void MbsAddRecentNativeImage(const mach_header *image,intptr_t) {
    Dl_info info;
    if (dladdr(image,&info)) MbsBindRecentNativeImage(image,info.dli_fname);
}

static void MbsCaptureRecentNativeEvent(void *sender,int signal) {
    const auto *object=(const unsigned char *)sender;
    // The native completion signal also fires on failed opens with no real
    // subwindow. A generated documentID is not a successful-open indicator.
    if (signal!=5 && (!*(const int64_t *)(object+0x78) || object[0xe5])) return;
    struct Data { int reference,length; unsigned allocation,padding; intptr_t offset; };
    const auto *data=*(const Data *const *)(object+0x90);
    if (!data || data->length<=0 || data->length>32768) return;
    const auto *characters=(const unichar *)((const unsigned char *)data+data->offset);
    for (int index=0;index<data->length;++index) if (!characters[index]) return;
    @autoreleasepool {
        NSString *path=[[NSString alloc] initWithCharacters:characters length:data->length];
        const char *value=path.UTF8String;
        // The store copies this string immediately and validates local paths.
        if (value && value[0]) MbsRecordRecentDocumentPath(value);
    }
}
static void MbsRecentNativeActivate(void *sender,const void *meta,int signal,void **arguments) {
    const void *bound=__atomic_load_n(&MbsRecentNativeMeta,__ATOMIC_ACQUIRE);
    if (sender && bound && meta==bound && (signal==3 || signal==4 || signal==5) && !MbsRecentRecording) {
        MbsRecentRecording=true;
        // Copy before native listeners run: a listener can close the document
        // and destroy its sender or change the current path during activation.
        MbsCaptureRecentNativeEvent(sender,signal);
        MbsRecentRecording=false;
    }
    MbsRecentOriginalActivate(sender,meta,signal,arguments);
}

#ifdef MBS_RECENT_NATIVE_EVENTS_TEST
bool MbsRecentNativeEventsTestBindImage(const void *image,const char *path) {
    return MbsBindRecentNativeImage((const mach_header *)image,path);
}
void MbsRecentNativeEventsTestRemoveImage(const void *image) { MbsRemoveRecentNativeImage((const mach_header *)image,0); }
void MbsRecentNativeEventsTestBind(const void *meta) {
    __atomic_store_n(&MbsRecentNativeMeta,meta,__ATOMIC_RELEASE);
    __atomic_store_n(&MbsRecentNativeImage,(const void *)nullptr,__ATOMIC_RELEASE);
}
void MbsRecentNativeEventsTestActivate(void *sender,const void *meta,int signal,void **arguments) {
    MbsRecentNativeActivate(sender,meta,signal,arguments);
}
#else
struct MbsRecentEventInterpose { const void *replacement,*original; };
__attribute__((used,section("__DATA,__interpose")))
static const MbsRecentEventInterpose MbsRecentEventRoute={
    (const void *)&MbsRecentNativeActivate,(const void *)&MbsRecentOriginalActivate};
__attribute__((constructor)) static void MbsRegisterRecentNativeEvents(void) {
    _dyld_register_func_for_add_image(MbsAddRecentNativeImage);
    _dyld_register_func_for_remove_image(MbsRemoveRecentNativeImage);
}
#endif
