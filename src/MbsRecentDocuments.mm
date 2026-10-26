#import <Foundation/Foundation.h>
#import "MbsRecentDocuments.h"

static NSString *MbsRecentAppName(NSString *path) {
    NSString *suffix=path.pathExtension.lowercaseString;
    if ([@[@"xls",@"xlsx",@"xlsm",@"xlsb",@"xlt",@"xltx",@"csv",@"ods",@"et",@"ett"] containsObject:suffix]) return @"et";
    if ([@[@"ppt",@"pptx",@"pptm",@"pps",@"ppsx",@"pot",@"potx",@"odp",@"dps",@"dpt"] containsObject:suffix]) return @"wpp";
    if ([suffix isEqualToString:@"pdf"]) return @"pdf";
    if ([suffix isEqualToString:@"ofd"]) return @"ofd";
    return @"wps";
}
static NSString *MbsRecentLocalPath(NSString *value) {
    if (![value isKindOfClass:NSString.class] || !value.length || value.length>32768) return nil;
    if ([value hasPrefix:@"file:"]) {
        NSURL *url=[NSURL URLWithString:value];
        if (!url.isFileURL || (url.host.length && ![url.host isEqualToString:@"localhost"])) return nil;
        value=url.path;
    }
    if (!value.isAbsolutePath) return nil;
    return value.stringByStandardizingPath.stringByResolvingSymlinksInPath;
}

@interface MbsRecentDocumentStore : NSObject
@property NSURL *url;
@property NSArray<NSDictionary *> *records;
- (instancetype)initWithURL:(NSURL *)url;
- (BOOL)recordPath:(NSString *)path atDate:(NSDate *)date;
@end
@implementation MbsRecentDocumentStore
- (instancetype)initWithURL:(NSURL *)url {
    if (!(self=[super init])) return nil;
    self.url=url; self.records=@[];
    NSNumber *size=nil; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    NSData *data=size.unsignedLongLongValue<=1024*1024 ? [NSData dataWithContentsOfURL:url] : nil;
    id saved=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![saved isKindOfClass:NSArray.class]) return self;
    NSMutableArray *records=[NSMutableArray array]; NSMutableSet *paths=[NSMutableSet set];
    for (id item in saved) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *path=MbsRecentLocalPath(item[@"path"]);
        if (!path || [paths containsObject:path] || ![item[@"accessTime"] isKindOfClass:NSNumber.class]) continue;
        NSMutableDictionary *entry=[item mutableCopy]; entry[@"path"]=path;
        entry[@"appName"]=MbsRecentAppName(path);
        [records addObject:entry]; [paths addObject:path];
        if (records.count==100) break;
    }
    self.records=records;
    return self;
}
- (BOOL)recordPath:(NSString *)value atDate:(NSDate *)date {
    NSString *path=MbsRecentLocalPath(value);
    if (!path) return NO;
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) return NO;
    NSDictionary *entry=@{@"path":path,@"fileName":path.lastPathComponent,@"parentPath":path.stringByDeletingLastPathComponent,
        @"appName":MbsRecentAppName(path),@"accessTime":@((int64_t)(date.timeIntervalSince1970*1000)),
        @"modifiedTime":@([attributes[NSFileModificationDate] timeIntervalSince1970]),
        @"fileSize":attributes[NSFileSize] ?: @0};
    NSMutableArray *next=[NSMutableArray arrayWithObject:entry];
    for (NSDictionary *old in self.records) {
        if (![old[@"path"] isEqualToString:path]) [next addObject:old];
        if (next.count==100) break;
    }
    if ([next isEqualToArray:self.records]) return NO;
    if (![NSFileManager.defaultManager createDirectoryAtURL:self.url.URLByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    NSData *data=[NSJSONSerialization dataWithJSONObject:next options:0 error:nil];
    if (!data || ![data writeToURL:self.url options:NSDataWritingAtomic error:nil]) return NO;
    [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:self.url.path error:nil];
    self.records=next;
    return YES;
}
@end

static dispatch_queue_t MbsRecentQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once,^{ queue=dispatch_queue_create("com.mbs.office.recent-documents",
        dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0)); });
    return queue;
}
static MbsRecentDocumentStore *MbsRecentStore(void) {
    static MbsRecentDocumentStore *store; static dispatch_once_t once;
    dispatch_once(&once,^{
        NSURL *base=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        store=[[MbsRecentDocumentStore alloc] initWithURL:[base URLByAppendingPathComponent:@"Mbs Office/Recent/recent-documents.json"]];
    });
    return store;
}
void MbsRecordRecentDocumentPath(const char *value) {
    NSString *path=value ? [NSString stringWithUTF8String:value] : nil;
    if (!path.length) return;
    NSDate *date=NSDate.date;
    dispatch_async(MbsRecentQueue(),^{ @autoreleasepool {
        if ([MbsRecentStore() recordPath:path atDate:date]) dispatch_async(dispatch_get_main_queue(),^{
            [NSNotificationCenter.defaultCenter postNotificationName:@"MbsRecentDocumentsDidChange" object:nil];
        });
    }});
}
char *MbsCopyRecentDocuments(void) {
    __block NSData *data;
    dispatch_sync(MbsRecentQueue(),^{ data=[NSJSONSerialization dataWithJSONObject:MbsRecentStore().records options:0 error:nil]; });
    return data ? strndup((const char *)data.bytes,data.length) : nullptr;
}
