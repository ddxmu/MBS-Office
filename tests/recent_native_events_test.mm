#define MBS_RECENT_NATIVE_EVENTS_TEST 1
#include "../src/MbsRecentNativeEvents.mm"
#include <assert.h>
#include <stdlib.h>

struct RecentTestString {
    int reference,length; unsigned allocation,padding; intptr_t offset;
    unichar characters[256];
};
struct RecentTestSender { alignas(8) unsigned char bytes[0xe8]; };
static NSMutableArray<NSString *> *MbsRecentTestRecords;
static unsigned MbsRecentTestOriginalCalls;
static const void *MbsRecentTestLastMeta;
static int MbsRecentTestLastSignal;
static void **MbsRecentTestLastArguments;
static NSString *MbsRecentTestExpectedBeforeOriginal;
static bool MbsRecentTestDestroyOriginal,MbsRecentTestReenter;
static const void *MbsRecentTestMeta;
static RecentTestSender *MbsRecentTestActiveSender;

static RecentTestString *MbsRecentTestString(NSString *path) {
    assert(path.length<256);
    auto *data=(RecentTestString *)calloc(1,sizeof(RecentTestString));
    data->reference=-1; data->length=(int)path.length; data->offset=24;
    [path getCharacters:data->characters range:NSMakeRange(0,path.length)];
    return data;
}
static RecentTestSender *MbsRecentTestSender(NSString *path,int64_t handle,bool loading) {
    auto *sender=(RecentTestSender *)calloc(1,sizeof(RecentTestSender));
    auto *data=MbsRecentTestString(path);
    memcpy(sender->bytes+0x78,&handle,sizeof(handle));
    memcpy(sender->bytes+0x90,&data,sizeof(data));
    sender->bytes[0xe5]=loading;
    return sender;
}
static void MbsRecentTestFree(RecentTestSender *sender) {
    RecentTestString *data; memcpy(&data,sender->bytes+0x90,sizeof(data));
    free(data); free(sender);
}
extern "C" void MbsRecordRecentDocumentPath(const char *path) {
    [MbsRecentTestRecords addObject:[NSString stringWithUTF8String:path]];
    if (MbsRecentTestReenter) {
        MbsRecentTestReenter=false;
        MbsRecentNativeEventsTestActivate(MbsRecentTestActiveSender,MbsRecentTestMeta,3,nullptr);
    }
}
void MbsRecentOriginalActivate(void *sender,const void *meta,int signal,void **arguments) {
    ++MbsRecentTestOriginalCalls;
    MbsRecentTestLastMeta=meta;
    MbsRecentTestLastSignal=signal; MbsRecentTestLastArguments=arguments;
    if (MbsRecentTestExpectedBeforeOriginal)
        assert([MbsRecentTestRecords.lastObject isEqualToString:MbsRecentTestExpectedBeforeOriginal]);
    if (MbsRecentTestDestroyOriginal) {
        MbsRecentTestDestroyOriginal=false;
        MbsRecentTestFree((RecentTestSender *)sender);
    }
}

static NSMutableData *MbsRecentTestImage(void) {
    NSMutableData *image=[NSMutableData dataWithLength:0x900000];
    auto *header=(mach_header_64 *)image.mutableBytes;
    header->magic=MH_MAGIC_64; header->cputype=CPU_TYPE_ARM64;
    header->ncmds=3; header->sizeofcmds=2*sizeof(segment_command_64)+sizeof(uuid_command);
    auto *text=(segment_command_64 *)(header+1);
    text->cmd=LC_SEGMENT_64; text->cmdsize=sizeof(*text); strcpy(text->segname,"__TEXT");
    text->vmsize=0x8f4000; text->initprot=VM_PROT_READ|VM_PROT_EXECUTE;
    auto *data=text+1;
    data->cmd=LC_SEGMENT_64; data->cmdsize=sizeof(*data); strcpy(data->segname,"__DATA_CONST");
    data->vmaddr=0x8f4000; data->vmsize=0x4000; data->initprot=VM_PROT_READ;
    auto *uuid=(uuid_command *)(data+1);
    uuid->cmd=LC_UUID; uuid->cmdsize=sizeof(*uuid);
    memcpy(uuid->uuid,MbsRecentImageUUID,sizeof(uuid->uuid));
    memcpy((unsigned char *)header+MbsRecentPathGetterRVA,MbsRecentPathGetterCode,sizeof(MbsRecentPathGetterCode));
    return image;
}
int main(void) { @autoreleasepool {
    MbsRecentTestRecords=[NSMutableArray array];
    unsigned char meta,otherMeta;
    MbsRecentTestMeta=&meta; MbsRecentNativeEventsTestBind(&meta);
    auto *sender=MbsRecentTestSender(@"/fixture/打开文档.docx",42,false);
    MbsRecentTestActiveSender=sender;
    void *arguments[]={nullptr,(void *)0x1234};
    MbsRecentTestExpectedBeforeOriginal=@"/fixture/打开文档.docx";
    MbsRecentNativeEventsTestActivate(sender,&meta,3,arguments);
    assert(MbsRecentTestRecords.count==1 && MbsRecentTestOriginalCalls==1);
    assert(MbsRecentTestLastMeta==&meta && MbsRecentTestLastSignal==3 && MbsRecentTestLastArguments==arguments);
    MbsRecentTestExpectedBeforeOriginal=nil;
    auto *failed=MbsRecentTestSender(@"/fixture/failed.pdf",0,false);
    auto *loading=MbsRecentTestSender(@"/fixture/loading.xlsx",7,true);
    MbsRecentNativeEventsTestActivate(failed,&meta,3,nullptr);
    MbsRecentNativeEventsTestActivate(loading,&meta,4,nullptr);
    MbsRecentNativeEventsTestActivate((void *)1,&otherMeta,3,arguments);
    MbsRecentNativeEventsTestActivate((void *)1,&meta,1,arguments);
    MbsRecentNativeEventsTestActivate(nullptr,&meta,3,arguments);
    assert(MbsRecentTestRecords.count==1 && MbsRecentTestOriginalCalls==6);
    MbsRecentNativeEventsTestActivate(sender,&meta,4,nullptr);
    assert(MbsRecentTestRecords.count==2);

    // Native afterSave passes the OLD path as an argument. The current sender
    // path is the saved destination and must be copied before listeners run.
    auto *saveAs=MbsRecentTestSender(@"/fixture/新文件.pdf",0,true);
    bool changed=true; void *saveArguments[]={nullptr,&changed,(void *)0x1234};
    MbsRecentTestExpectedBeforeOriginal=@"/fixture/新文件.pdf";
    MbsRecentTestDestroyOriginal=true;
    MbsRecentNativeEventsTestActivate(saveAs,&meta,5,saveArguments);
    assert([MbsRecentTestRecords.lastObject isEqualToString:@"/fixture/新文件.pdf"]);
    assert(MbsRecentTestLastSignal==5 && MbsRecentTestLastArguments==saveArguments);
    MbsRecentTestExpectedBeforeOriginal=nil;

    MbsRecentTestReenter=true;
    unsigned before=MbsRecentTestOriginalCalls;
    MbsRecentNativeEventsTestActivate(sender,&meta,3,nullptr);
    assert(MbsRecentTestRecords.count==4 && MbsRecentTestOriginalCalls==before+2);
    auto *empty=MbsRecentTestSender(@"",1,false);
    MbsRecentNativeEventsTestActivate(empty,&meta,3,nullptr);
    RecentTestString *emptyData; memcpy(&emptyData,empty->bytes+0x90,sizeof(emptyData));
    emptyData->length=32769;
    MbsRecentNativeEventsTestActivate(empty,&meta,3,nullptr);
    emptyData->length=2; emptyData->characters[0]='a'; emptyData->characters[1]=0;
    MbsRecentNativeEventsTestActivate(empty,&meta,3,nullptr);
    assert(MbsRecentTestRecords.count==4);
    MbsRecentNativeEventsTestBind(nullptr);
    MbsRecentNativeEventsTestActivate((void *)1,&meta,3,nullptr);
    assert(MbsRecentTestRecords.count==4);

    NSMutableData *image=MbsRecentTestImage();
    auto *header=(mach_header_64 *)image.mutableBytes;
    const char *path="/fixture/kprometheus.framework/Versions/A/kprometheus";
    assert(!MbsRecentNativeEventsTestBindImage(header,"/fixture/unrelated.framework/kprometheus"));
    auto *uuid=(uuid_command *)((segment_command_64 *)(header+1)+2);
    uuid->uuid[0]^=1;
    assert(!MbsRecentNativeEventsTestBindImage(header,path)); uuid->uuid[0]^=1;
    ((unsigned char *)header)[MbsRecentPathGetterRVA]^=1;
    assert(!MbsRecentNativeEventsTestBindImage(header,path));
    ((unsigned char *)header)[MbsRecentPathGetterRVA]^=1;
    auto *text=(segment_command_64 *)(header+1); uint32_t size=text->cmdsize;
    text->cmdsize=0; assert(!MbsRecentNativeEventsTestBindImage(header,path)); text->cmdsize=size;
    assert(MbsRecentNativeEventsTestBindImage(header,path));
    const void *imageMeta=(const unsigned char *)header+MbsRecentMetaRVA;
    MbsRecentNativeEventsTestActivate(sender,imageMeta,3,nullptr);
    assert(MbsRecentTestRecords.count==5);
    MbsRecentNativeEventsTestRemoveImage(header);
    MbsRecentNativeEventsTestActivate((void *)1,imageMeta,3,nullptr);
    assert(MbsRecentTestRecords.count==5);
    MbsRecentTestFree(sender); MbsRecentTestFree(failed); MbsRecentTestFree(loading); MbsRecentTestFree(empty);
    puts("PASS: guarded native image binding, successful open/recover, failed/loading opens ignored, current SaveAs path copied before sender destruction, unrelated signals preserved and original activation called once");
} return 0; }
