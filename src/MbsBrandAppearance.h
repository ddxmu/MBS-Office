#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <mach-o/getsect.h>

static NSColor *MbsBrandInk(void) {
    return [NSColor colorWithSRGBRed:0.15 green:0.21 blue:0.40 alpha:1];
}

static NSFont *MbsBrandFont(CGFloat size) {
    return [NSFont systemFontOfSize:size weight:NSFontWeightSemibold];
}

static NSImage *MbsBrandArtwork(void) {
    static NSImage *artwork;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Dl_info image;
        unsigned long size = 0;
        if (dladdr((const void *)MbsBrandArtwork,&image)) {
            const unsigned char *bytes = getsectiondata((const struct mach_header_64 *)image.dli_fbase,"__TEXT","__mbs_art",&size);
            if (bytes && size) artwork = [[NSImage alloc] initWithData:[NSData dataWithBytes:bytes length:size]];
        }
        if (!artwork) artwork = [[NSImage alloc] initWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"MbsStartupAI" ofType:@"png"]];
    });
    return artwork;
}

// Remove the supplied illustration's transparent margin while preserving its proportions.
static NSRect MbsBrandArtworkBounds(NSImage *image) {
    static NSRect bounds;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        NSInteger left=bitmap.pixelsWide, bottom=bitmap.pixelsHigh, right=0, top=0;
        for (NSInteger y=0;y<bitmap.pixelsHigh;++y) {
            for (NSInteger x=0;x<bitmap.pixelsWide;++x) {
                if ([bitmap colorAtX:x y:y].alphaComponent < 0.05) continue;
                left=MIN(left,x); right=MAX(right,x+1); bottom=MIN(bottom,y); top=MAX(top,y+1);
            }
        }
        bounds = right>left && top>bottom
            ? NSMakeRect(left*image.size.width/bitmap.pixelsWide,(bitmap.pixelsHigh-top)*image.size.height/bitmap.pixelsHigh,
                         (right-left)*image.size.width/bitmap.pixelsWide,(top-bottom)*image.size.height/bitmap.pixelsHigh)
            : NSMakeRect(0,0,image.size.width,image.size.height);
    });
    return bounds;
}

static void MbsDrawBrandRobot(NSRect frame) {
    NSImage *image = MbsBrandArtwork();
    if (!image) return;
    NSRect source = MbsBrandArtworkBounds(image);
    CGFloat scale = MIN(frame.size.width/source.size.width,frame.size.height/source.size.height);
    NSRect destination = NSMakeRect(NSMidX(frame)-source.size.width*scale/2,NSMidY(frame)-source.size.height*scale/2,
                                    source.size.width*scale,source.size.height*scale);
    [image drawInRect:destination fromRect:source operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
}
