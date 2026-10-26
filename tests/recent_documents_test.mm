#include "../src/MbsRecentDocuments.mm"
int main(void) { @autoreleasepool {
    NSString *temporary=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSURL *root=[NSURL fileURLWithPath:temporary];
    [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *history=[root URLByAppendingPathComponent:@"cache/recent.json"];
    NSString *first=[temporary stringByAppendingPathComponent:@"中文 空格.docx"];
    NSString *second=[temporary stringByAppendingPathComponent:@"另一份.pdf"];
    [@"one" writeToFile:first atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"two" writeToFile:second atomically:YES encoding:NSUTF8StringEncoding error:nil];
    MbsRecentDocumentStore *store=[[MbsRecentDocumentStore alloc] initWithURL:history];
    assert([store recordPath:first atDate:[NSDate dateWithTimeIntervalSince1970:100]]);
    assert([store recordPath:second atDate:[NSDate dateWithTimeIntervalSince1970:200]]);
    assert(store.records.count==2 && [store.records[0][@"appName"] isEqual:@"pdf"]);
    [@"saved with longer content" writeToFile:first atomically:YES encoding:NSUTF8StringEncoding error:nil];
    assert([store recordPath:[NSURL fileURLWithPath:first].absoluteString atDate:[NSDate dateWithTimeIntervalSince1970:300]]);
    assert(store.records.count==2 && [store.records[0][@"fileName"] isEqual:@"中文 空格.docx"]);
    assert([store.records[0][@"fileSize"] integerValue]>3 && [store.records[0][@"accessTime"] longLongValue]==300000);
    NSString *otherDirectory=[temporary stringByAppendingPathComponent:@"同名文件目录"];
    [NSFileManager.defaultManager createDirectoryAtPath:otherDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *other=[otherDirectory stringByAppendingPathComponent:first.lastPathComponent];
    [@"different file" writeToFile:other atomically:YES encoding:NSUTF8StringEncoding error:nil];
    assert([store recordPath:other atDate:[NSDate dateWithTimeIntervalSince1970:400]]);
    assert(store.records.count==3); // same name in another folder remains a separate document
    MbsRecentDocumentStore *restored=[[MbsRecentDocumentStore alloc] initWithURL:history];
    assert([restored.records isEqual:store.records]);
    assert(![store recordPath:[temporary stringByAppendingPathComponent:@"未保存.docx"] atDate:NSDate.date]);
    assert(![store recordPath:temporary atDate:NSDate.date]);
    assert(![store recordPath:@"https://example.invalid/document.docx" atDate:NSDate.date]);
    assert(![store recordPath:@"未命名文档" atDate:NSDate.date]);
    NSDictionary *attributes=[NSFileManager.defaultManager attributesOfItemAtPath:history.path error:nil];
    assert(([attributes[NSFilePosixPermissions] integerValue]&0777)==0600);
    // Corrupt/unexpected cache contents do not become native file records.
    [@"not json" writeToURL:history atomically:YES encoding:NSUTF8StringEncoding error:nil];
    assert(![[[MbsRecentDocumentStore alloc] initWithURL:history] records].count);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    puts("PASS: per-file records, save metadata, Unicode file URLs, deduplication, persistence, invalid inputs and private cache");
} return 0; }
