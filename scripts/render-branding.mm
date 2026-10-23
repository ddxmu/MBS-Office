#import "../src/MbsBrandAppearance.h"

static NSData *MbsHeaderSVG(void) {
    static NSData *svg;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:372 pixelsHigh:120
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        NSAffineTransform *scale = [NSAffineTransform transform];
        [scale scaleBy:3]; [scale concat];
        MbsDrawBrandRobot(NSMakeRect(0,3,30,34));
        NSFont *font=[NSFont systemFontOfSize:17.5 weight:NSFontWeightBold];
        NSFontDescriptor *rounded=[font.fontDescriptor fontDescriptorWithDesign:NSFontDescriptorSystemDesignRounded];
        if (rounded) font=[NSFont fontWithDescriptor:rounded size:17.5];
        [@"Mbs Office" drawAtPoint:NSMakePoint(32,8.5) withAttributes:@{
            NSFontAttributeName:font,NSForegroundColorAttributeName:MbsBrandInk(),NSKernAttributeName:@0.1}];
        [NSGraphicsContext restoreGraphicsState];
        NSString *png = [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] base64EncodedStringWithOptions:0];
        svg = [[NSString stringWithFormat:@"<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" id=\"mbs-wordmark\" width=\"124\" height=\"40\" viewBox=\"0 0 124 40\"><image width=\"124\" height=\"40\" xlink:href=\"data:image/png;base64,%@\"/></svg>",png] dataUsingEncoding:NSUTF8StringEncoding];
    });
    return svg;
}

int main(int argc,const char **argv) { @autoreleasepool {
    if (argc!=2) return 2;
    [NSApplication sharedApplication];
    return [MbsHeaderSVG() writeToFile:@(argv[1]) atomically:YES] ? 0 : 1;
} }
