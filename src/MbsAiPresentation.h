#import <Foundation/Foundation.h>
NSArray<NSDictionary *> *MbsAiSlides(NSString *text, BOOL single, NSError **error);
BOOL MbsAiWritePresentation(NSArray<NSDictionary *> *slides, NSURL *url, NSError **error);
