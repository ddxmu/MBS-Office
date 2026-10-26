#import <Foundation/Foundation.h>
#import "../src/MbsRecentDocuments.mm"
#include <assert.h>

int main(void) { @autoreleasepool {
    int64_t end=1800000000000LL, day=86400000;
    NSDate *now=[NSDate dateWithTimeIntervalSince1970:end/1000.0];
    NSMutableArray *records=[NSMutableArray array];
    for (int i=0;i<20;i++)
        [records addObject:@{@"path":[NSString stringWithFormat:@"/test/%d.docx",i],@"accessTime":@(end-i*1000)}];
    NSArray *home=MbsRecentDocumentRows(records,NO,now);
    assert(home.count==15 && [home isEqualToArray:[records subarrayWithRange:NSMakeRange(0,15)]]);
    assert(MbsRecentDocumentRows(records,YES,now).count==20);
    NSArray *mixed=@[
        @{@"accessTime":@(end-day-1),@"modifiedTime":@(end/1000)},
        @{@"accessTime":@(end-day)}, @{@"accessTime":@(end)},
        @{@"accessTime":@(end+1)}, @{@"accessTime":NSNull.null}];
    NSArray *dayRows=MbsRecentDocumentRows(mixed,YES,now);
    assert(dayRows.count==2 && dayRows[0]==mixed[1] && dayRows[1]==mixed[2]);
    // Home retains old records; the 24-hour page uses opened/saved time.
    assert(MbsRecentDocumentRows(mixed,NO,now).count==mixed.count);
    assert(MbsRecentDocumentRows(@[],YES,now).count==0);
    assert(MbsRecentDocumentRows(@[mixed[0]],YES,now).count==0);
    assert(MbsRecentDocumentRows(records,YES,[now dateByAddingTimeInterval:86401]).count==0);
    puts("PASS: first 15 without time filtering; More shows only last 24 hours, including boundary and over-15 records");
} return 0; }
