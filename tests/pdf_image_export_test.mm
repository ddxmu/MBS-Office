#import "../src/MbsPdfConvert.mm"
extern "C" char *MbsCopyRecentDocuments(void) { return nullptr; }
static void check(BOOL ok, NSString *message) { if (!ok) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); } }
static void waitForExport(MbsPdfConvertWindow *c) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:30];
    while (c.busy && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    check(!c.busy,@"export timed out"); check([c.statusLabel.stringValue hasPrefix:@"已保存 1 张图片："],c.statusLabel.stringValue);
}
int main(int argc,const char **argv) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSString *folder=[NSString stringWithUTF8String:argv[1]];
    NSURL *source=[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"sample.pdf"]];
    CGRect bounds=CGRectMake(0,0,144,72);
    CGContextRef pdf=CGPDFContextCreateWithURL((__bridge CFURLRef)source,&bounds,NULL);
    CGPDFContextBeginPage(pdf,NULL); CGContextSetRGBFillColor(pdf,1,0,0,1); CGContextFillRect(pdf,CGRectMake(0,0,72,72)); CGPDFContextEndPage(pdf); CGPDFContextClose(pdf); CGContextRelease(pdf);
    MbsPdfConvertWindow *c=[MbsPdfConvertWindow new]; [c.format selectItemAtIndex:4]; [c loadFile:source];
    check([c.window.title isEqualToString:@"Mbs 输出为图片"],@"image window title"); check(c.format.hidden && !c.imageFormat.hidden,@"image options");
    for (NSButton *b in c.navigation) if (b.tag!=4) check(b.hidden,@"conversion navigation hidden");
    [c.imageDpi selectItemAtIndex:0]; [c startConversion:nil]; waitForExport(c);
    NSString *png=[folder stringByAppendingPathComponent:@"sample.png"];
    NSData *original=[NSData dataWithContentsOfFile:png]; check(original.length>0,@"PNG saved");
    NSBitmapImageRep *bitmap=[NSBitmapImageRep imageRepWithData:original]; check(bitmap.pixelsWide==144 && bitmap.pixelsHigh==72,@"PNG dimensions");
    NSColor *pixel=[[bitmap colorAtX:36 y:36] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace]; fprintf(stdout,"color=%f,%f,%f size=%ldx%ld\n",pixel.redComponent,pixel.greenComponent,pixel.blueComponent,(long)bitmap.pixelsWide,(long)bitmap.pixelsHigh); check(pixel.redComponent>0.7 && pixel.greenComponent<0.3,@"rendered PDF content");
    [c startConversion:nil]; waitForExport(c); check([[NSData dataWithContentsOfFile:png] isEqual:original],@"existing file preserved"); check([[NSFileManager defaultManager] fileExistsAtPath:[folder stringByAppendingPathComponent:@"sample (1).png"]],@"collision suffix");
    [c.imageFormat selectItemAtIndex:1]; [c.imageDpi selectItemAtIndex:4]; [c startConversion:nil]; waitForExport(c);
    bitmap=[NSBitmapImageRep imageRepWithData:[NSData dataWithContentsOfFile:[folder stringByAppendingPathComponent:@"sample.jpg"]]]; check(bitmap.pixelsWide==600 && bitmap.pixelsHigh==300,@"JPEG resolution"); pixel=[[bitmap colorAtX:100 y:150] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace]; check(pixel.redComponent>0.7 && pixel.greenComponent<0.3,@"JPEG content scales with DPI");
    [c.format selectItemAtIndex:0]; [c updateStart:nil]; check([c.window.title isEqualToString:@"Mbs PDF转换"] && c.imageFormat.hidden,@"Word mode restored");
    if (argc>2) {
        [c.format selectItemAtIndex:4]; [c.imageFormat selectItemAtIndex:0]; [c.imageDpi selectItemAtIndex:2];
        [c loadFile:[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]]];
        c.outputDirectory=[NSURL fileURLWithPath:folder isDirectory:YES];
        c.startPage.stringValue=@"1"; c.endPage.stringValue=@"1";
        [c startConversion:nil]; waitForExport(c);
    }
    fprintf(stdout,"PASS: image UI, PNG content, JPEG DPI, no overwrite, mode switching\n");
} }
