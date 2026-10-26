#import <Foundation/Foundation.h>
#define MBS_BRAND_RESOURCE_TEST
#include "../src/MbsBrandResources.mm"

bool registerFile(const MbsResourceString &,const MbsResourceString &) __asm__("__ZN6kso_qt9QResource16registerResourceERKNS_7QStringES3_");
void localeCtor(void *) __asm__("__ZN6kso_qt7QLocaleC1Ev");
void resourceCtor(void *,const MbsResourceString &,const void *) __asm__("__ZN6kso_qt9QResourceC1ERKNS_7QStringERKNS_7QLocaleE");
void resourceDtor(void *) __asm__("__ZN6kso_qt9QResourceD1Ev");
bool resourceValid(const void *) __asm__("__ZNK6kso_qt9QResource7isValidEv");
long long resourceSize(const void *) __asm__("__ZNK6kso_qt9QResource4sizeEv");
const unsigned char *resourceData(const void *) __asm__("__ZNK6kso_qt9QResource4dataEv");

static MbsResourceString string(NSString *value) {
    auto *data=(unsigned char *)calloc(1,24+value.length*2+2);
    *(int *)data=-1; *(int *)(data+4)=(int)value.length; *(int64_t *)(data+16)=24;
    [value getCharacters:(unichar *)(data+24) range:NSMakeRange(0,value.length)];
    return {data};
}
static void check(NSString *path,NSData *expected) {
    alignas(8) unsigned char locale[64]={},resource[256]={};
    localeCtor(locale); resourceCtor(resource,string(path),locale);
    assert(resourceValid(resource));
    assert(resourceSize(resource)==(long long)expected.length);
    assert(memcmp(resourceData(resource),expected.bytes,expected.length)==0);
    resourceDtor(resource);
}
int main(int argc,char **argv) { @autoreleasepool {
    assert(argc==10);
    NSData *rcc=nil;
    if ([@(argv[1]) hasSuffix:@".dylib"]) assert(dlopen(argv[1],RTLD_NOW|RTLD_LOCAL));
    else { rcc=[NSData dataWithContentsOfFile:@(argv[1])]; assert(MbsRegisterBrandingResource((const unsigned char *)rcc.bytes)); }
    // Original archives register after the embedded wordmark, exactly as at startup.
    for (int i=4;i<8;++i) assert(registerFile(string(@(argv[i])),{&MbsEmptyResourceString}));
    NSDictionary *spec=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[3])] options:0 error:nil];
    NSData *art=[NSData dataWithContentsOfFile:@(argv[2])];
    for (NSString *path in spec[@"paths"]) check([@":" stringByAppendingString:path],art);
    NSString *icons=[@(argv[2]).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"mbs-ai-icons"];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:icons error:nil]) {
        if (![name.pathExtension isEqualToString:@"svg"]) continue;
        NSData *icon=[NSData dataWithContentsOfFile:[icons stringByAppendingPathComponent:name]];
        for (NSNumber *size in @[@16,@24,@32])
            check([NSString stringWithFormat:@":/icons_svg/%@x%@/%@",size,size,name],icon);
    }
    check([@":" stringByAppendingString:@(argv[8])],[NSData dataWithContentsOfFile:@(argv[9])]);
    puts("PASS embedded wordmark aliases and AI icons at all sizes; unrelated original resource unchanged");
} }
