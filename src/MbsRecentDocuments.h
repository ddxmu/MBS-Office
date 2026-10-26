#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Called only for completed native document events. Paths remain on this Mac.
void MbsRecordRecentDocumentPath(const char *path);
// JSON array; caller must free the returned buffer. accessTime is Unix milliseconds.
char *MbsCopyRecentDocuments(void);
#ifdef __cplusplus
}
#endif
#ifdef __OBJC__
#import <Foundation/Foundation.h>
NSArray<NSDictionary *> *MbsRecentDocumentRows(NSArray<NSDictionary *> *records, BOOL lastDayOnly, NSDate *now);
#endif
