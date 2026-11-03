#import <AppKit/AppKit.h>
#import <PDFKit/PDFKit.h>
#import "MbsRecentDocuments.h"

@interface MbsPdfConvertWindow : NSWindowController
@property NSTextField *fileLabel;
@property NSTextField *statusLabel;
@property NSTextField *fileInfo;
@property NSTextField *startPage;
@property NSTextField *endPage;
@property NSTextField *outputPath;
@property NSButton *removeButton;
@property NSButton *fileSelected;
@property NSButton *startButton;
@property NSURL *inputURL;
@property NSURL *outputDirectory;
@property BOOL busy;
@property NSPopUpButton *format;
@property NSTextField *heading;
@property NSTextField *modeLabel;
@property NSPopUpButton *pageMode;
@property NSPopUpButton *imageFormat;
@property NSPopUpButton *imageDpi;
@property NSTextField *dpiLabel;
@property NSArray<NSButton *> *navigation;
@end

@implementation MbsPdfConvertWindow
- (instancetype)init {
    NSWindow *w=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,1120,760) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    if (!(self=[super initWithWindow:w])) return nil;
    w.title=@"Mbs PDF转换"; w.minSize=NSMakeSize(1000,700); w.releasedWhenClosed=NO; [w center];
    NSView *v=w.contentView;
    v.wantsLayer=YES; v.layer.backgroundColor=[NSColor colorWithCalibratedWhite:0.96 alpha:1].CGColor;
    NSTextField *heading=[NSTextField labelWithString:@"PDF转换"];
    self.heading=heading;
    heading.font=[NSFont boldSystemFontOfSize:17]; heading.frame=NSMakeRect(28,677,150,28); heading.autoresizingMask=NSViewMinYMargin; [v addSubview:heading];
    NSArray *names=@[@"转为 Word",@"转为 Excel",@"转为 PPT",@"转为 TXT",@"输出为图片"];
    NSMutableArray *navigation=[NSMutableArray array];
    for (NSUInteger i=0;i<names.count;i++) {
        NSButton *b=[NSButton buttonWithTitle:names[i] target:self action:@selector(selectFormat:)];
        b.tag=i; b.frame=NSMakeRect(22,620-i*46,155,36); b.autoresizingMask=NSViewMinYMargin; [v addSubview:b]; [navigation addObject:b];
    }
    self.navigation=navigation;
    NSBox *box=[[NSBox alloc] initWithFrame:NSMakeRect(200,275,895,438)];
    box.boxType=NSBoxCustom; box.fillColor=NSColor.whiteColor; box.borderColor=[NSColor colorWithCalibratedWhite:0.86 alpha:1]; box.cornerRadius=9;
    box.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; [v addSubview:box];
    NSArray *headers=@[@"名称",@"输出范围",@"转换模式",@"操作"]; CGFloat positions[]={225,630,770,1018};
    for (int i=0;i<4;i++) {
        NSTextField *label=[NSTextField labelWithString:headers[i]]; label.font=[NSFont systemFontOfSize:15]; label.frame=NSMakeRect(positions[i],675,100,24);
        label.autoresizingMask=NSViewMinYMargin|(i?NSViewMinXMargin:0); [v addSubview:label];
        if (i==2) self.modeLabel=label;
    }
    NSBox *line=[[NSBox alloc] initWithFrame:NSMakeRect(222,659,852,1)]; line.boxType=NSBoxSeparator; line.autoresizingMask=NSViewMinYMargin|NSViewWidthSizable; [v addSubview:line];
    self.fileSelected=[NSButton checkboxWithTitle:@"" target:self action:@selector(updateStart:)]; self.fileSelected.frame=NSMakeRect(224,607,22,24); self.fileSelected.state=NSControlStateValueOn; self.fileSelected.hidden=YES; self.fileSelected.autoresizingMask=NSViewMinYMargin; [v addSubview:self.fileSelected];
    self.fileLabel=[NSTextField labelWithString:@"请添加 PDF 文件"]; self.fileLabel.font=[NSFont systemFontOfSize:15];
    self.fileLabel.frame=NSMakeRect(253,608,365,26); self.fileLabel.lineBreakMode=NSLineBreakByTruncatingMiddle; self.fileLabel.autoresizingMask=NSViewMinYMargin|NSViewWidthSizable; [v addSubview:self.fileLabel];
    self.fileInfo=[NSTextField labelWithString:@""]; self.fileInfo.frame=NSMakeRect(253,582,365,22); self.fileInfo.textColor=NSColor.secondaryLabelColor; self.fileInfo.autoresizingMask=NSViewMinYMargin; [v addSubview:self.fileInfo];
    self.startPage=[[NSTextField alloc] initWithFrame:NSMakeRect(630,608,46,26)]; self.startPage.stringValue=@"1"; self.startPage.enabled=NO; self.startPage.autoresizingMask=NSViewMinYMargin|NSViewMinXMargin; [v addSubview:self.startPage];
    NSTextField *dash=[NSTextField labelWithString:@"—"]; dash.frame=NSMakeRect(680,608,22,25); dash.autoresizingMask=NSViewMinYMargin|NSViewMinXMargin; [v addSubview:dash];
    self.endPage=[[NSTextField alloc] initWithFrame:NSMakeRect(702,608,46,26)]; self.endPage.enabled=NO; self.endPage.autoresizingMask=NSViewMinYMargin|NSViewMinXMargin; [v addSubview:self.endPage];
    NSPopUpButton *mode=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(770,607,145,28)]; [mode addItemWithTitle:@"标准件转换"]; mode.enabled=NO; mode.autoresizingMask=NSViewMinYMargin|NSViewMinXMargin; [v addSubview:mode];
    self.pageMode=mode;
    self.removeButton=[NSButton buttonWithTitle:@"移除" target:self action:@selector(removeFile:)]; self.removeButton.frame=NSMakeRect(1010,607,64,28); self.removeButton.hidden=YES; self.removeButton.autoresizingMask=NSViewMinYMargin|NSViewMinXMargin; [v addSubview:self.removeButton];
    NSButton *add=[NSButton buttonWithTitle:@"＋ 添加文件" target:self action:@selector(addFile:)]; add.frame=NSMakeRect(223,290,120,32); [v addSubview:add];
    NSTextField *directory=[NSTextField labelWithString:@"输出目录"]; directory.frame=NSMakeRect(200,218,130,24); [v addSubview:directory];
    self.outputPath=[NSTextField labelWithString:@"PDF 相同目录"]; self.outputPath.frame=NSMakeRect(200,183,330,24); self.outputPath.textColor=NSColor.secondaryLabelColor; self.outputPath.lineBreakMode=NSLineBreakByTruncatingMiddle; [v addSubview:self.outputPath];
    NSButton *choose=[NSButton buttonWithTitle:@"选择目录" target:self action:@selector(chooseDirectory:)]; choose.frame=NSMakeRect(200,145,100,30); [v addSubview:choose];
    NSTextField *formatLabel=[NSTextField labelWithString:@"输出格式"]; formatLabel.frame=NSMakeRect(550,218,120,24); [v addSubview:formatLabel];
    self.format=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(550,178,180,30)]; [self.format addItemsWithTitles:@[@"Word (.docx)",@"Excel (.xlsx)",@"PPT (.pptx)",@"文本 (.txt)",@"图片"]]; self.format.enabled=NO; [v addSubview:self.format];
    self.imageFormat=[[NSPopUpButton alloc] initWithFrame:self.format.frame]; [self.imageFormat addItemsWithTitles:@[@"PNG (.png)",@"JPEG (.jpg)"]]; self.imageFormat.hidden=YES; [v addSubview:self.imageFormat];
    self.dpiLabel=[NSTextField labelWithString:@"图片分辨率"]; self.dpiLabel.frame=NSMakeRect(770,218,140,24); self.dpiLabel.hidden=YES; [v addSubview:self.dpiLabel];
    self.imageDpi=[[NSPopUpButton alloc] initWithFrame:NSMakeRect(770,178,150,30)]; [self.imageDpi addItemsWithTitles:@[@"72 DPI",@"96 DPI",@"150 DPI",@"200 DPI",@"300 DPI",@"600 DPI"]]; [self.imageDpi selectItemAtIndex:2]; self.imageDpi.hidden=YES; [v addSubview:self.imageDpi];
    self.statusLabel=[NSTextField labelWithString:@"请选择 PDF 文件"];
    self.statusLabel.textColor=NSColor.secondaryLabelColor; self.statusLabel.frame=NSMakeRect(200,105,620,25); [v addSubview:self.statusLabel];
    self.startButton=[NSButton buttonWithTitle:@"开始转换" target:self action:@selector(startConversion:)]; self.startButton.enabled=NO; self.startButton.frame=NSMakeRect(925,65,170,44); self.startButton.autoresizingMask=NSViewMinXMargin; [v addSubview:self.startButton];
    return self;
}
- (void)updateStart:(id)sender {
    BOOL images=self.format.indexOfSelectedItem==4;
    self.window.title=images ? @"Mbs 输出为图片" : @"Mbs PDF转换";
    self.heading.stringValue=images ? @"输出为图片" : @"PDF转换";
    for (NSButton *button in self.navigation) {
        button.hidden=images && button.tag!=4;
        if (button.tag==4) button.frame=NSMakeRect(22,images ? 620 : 436,155,36);
    }
    self.modeLabel.stringValue=images ? @"输出方式" : @"转换模式";
    [self.pageMode removeAllItems]; [self.pageMode addItemWithTitle:images ? @"每页一张" : @"标准件转换"];
    self.format.hidden=images; self.imageFormat.hidden=!images; self.imageDpi.hidden=!images; self.dpiLabel.hidden=!images;
    self.startButton.title=images ? @"开始导出" : @"开始转换";
    BOOL supported=self.format.indexOfSelectedItem==0 || self.format.indexOfSelectedItem==1 || self.format.indexOfSelectedItem==4;
    const char *python=getenv("MBS_PDF_TEST_PYTHON");
    NSString *script=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"MbsPdfConvertTest.py"];
    NSString *engine=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"MbsPdfEngine/MbsPdfEngine"];
    BOOL packaged=[NSFileManager.defaultManager isExecutableFileAtPath:engine];
    BOOL available=images || packaged || (python && python[0] && [NSFileManager.defaultManager isExecutableFileAtPath:[NSString stringWithUTF8String:python]] && [NSFileManager.defaultManager fileExistsAtPath:script]);
    self.startButton.enabled=!self.busy && self.inputURL && self.outputDirectory && self.fileSelected.state==NSControlStateValueOn && supported && available;
    if (!self.busy) self.statusLabel.stringValue=images ? @"按所选页码导出图片，原 PDF 保持不变" : (available ? (supported ? @"转换后请核对版面" : @"该格式暂不可用") : @"转换引擎未安装");
}
- (void)selectFormat:(NSButton *)sender { if (self.busy) return; [self.format selectItemAtIndex:sender.tag]; [self updateStart:nil]; }
- (void)chooseDirectory:(id)sender {
    if (self.busy) return;
    NSOpenPanel *panel=[NSOpenPanel openPanel]; panel.canChooseDirectories=YES; panel.canChooseFiles=NO; panel.allowsMultipleSelection=NO;
    if ([panel runModal]!=NSModalResponseOK) return;
    self.outputDirectory=panel.URL; self.outputPath.stringValue=panel.URL.path; [self updateStart:nil];
}
- (void)loadFile:(NSURL *)url {
    if (self.busy || !url.isFileURL) return;
    PDFDocument *doc=[[PDFDocument alloc] initWithURL:url];
    if (!doc || doc.isLocked || !doc.pageCount) { self.statusLabel.stringValue=@"无法打开此 PDF，请检查文件或密码"; return; }
    self.inputURL=url; NSNumber *size=nil; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    self.fileLabel.stringValue=url.lastPathComponent; self.fileInfo.stringValue=[NSString stringWithFormat:@"%lu 页   |   %@",(unsigned long)doc.pageCount,[NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile]];
    self.endPage.stringValue=[NSString stringWithFormat:@"%lu",(unsigned long)doc.pageCount]; self.startPage.stringValue=@"1"; self.startPage.enabled=YES; self.endPage.enabled=YES;
    self.fileSelected.hidden=NO; self.fileSelected.state=NSControlStateValueOn; self.removeButton.hidden=NO;
    self.outputDirectory=url.URLByDeletingLastPathComponent; self.outputPath.stringValue=self.outputDirectory.path; [self updateStart:nil];
}
- (void)addFile:(id)sender {
    if (self.busy) return;
    NSOpenPanel *p=[NSOpenPanel openPanel]; p.allowedFileTypes=@[@"pdf"]; p.allowsMultipleSelection=NO;
    if ([p runModal]==NSModalResponseOK) [self loadFile:p.URL];
}
- (void)removeFile:(id)sender { if (self.busy) return; self.inputURL=nil; self.outputDirectory=nil; self.fileLabel.stringValue=@"请添加 PDF 文件"; self.fileInfo.stringValue=@""; self.fileSelected.hidden=YES; self.removeButton.hidden=YES; self.startPage.enabled=NO; self.endPage.enabled=NO; self.endPage.stringValue=@""; self.outputPath.stringValue=@"PDF 相同目录"; [self updateStart:nil]; }
- (void)startConversion:(id)sender {
    if (self.busy || !self.inputURL || !self.outputDirectory) return;
    int first=0,last=0; NSScanner *a=[NSScanner scannerWithString:self.startPage.stringValue], *b=[NSScanner scannerWithString:self.endPage.stringValue];
    PDFDocument *pdf=[[PDFDocument alloc] initWithURL:self.inputURL];
    if (![a scanInt:&first] || !a.isAtEnd || ![b scanInt:&last] || !b.isAtEnd || first<1 || last<first || last>(int)pdf.pageCount) { self.statusLabel.stringValue=@"页码范围无效，请检查"; return; }
    if (self.format.indexOfSelectedItem==4) { [self exportImagesFrom:first to:last]; return; }
    const char *python=getenv("MBS_PDF_TEST_PYTHON");
    NSString *script=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"MbsPdfConvertTest.py"];
    NSString *engine=[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"MbsPdfEngine/MbsPdfEngine"];
    BOOL packaged=[NSFileManager.defaultManager isExecutableFileAtPath:engine];
    if (!packaged && (!python || !python[0])) { [self updateStart:nil]; return; }
    NSInteger index=self.format.indexOfSelectedItem; if (index!=0 && index!=1 && index!=4) return;
    NSTask *task=[NSTask new]; task.executableURL=[NSURL fileURLWithPath:packaged ? engine : [NSString stringWithUTF8String:python]];
    NSArray *arguments=@[index==0?@"word":index==1?@"excel":@"image",self.inputURL.path,self.outputDirectory.path,self.startPage.stringValue,self.endPage.stringValue];
    task.arguments=packaged ? arguments : [@[script] arrayByAddingObjectsFromArray:arguments];
    NSPipe *output=[NSPipe pipe]; task.standardOutput=output; task.standardError=NSFileHandle.fileHandleWithNullDevice;
    self.busy=YES; self.startButton.enabled=NO; self.statusLabel.stringValue=@"正在转换，请稍候…";
    task.terminationHandler=^(NSTask *finished) {
        NSData *data=[output.fileHandleForReading readDataToEndOfFile];
        NSString *result=[[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy=NO; [self updateStart:nil];
            if (finished.terminationStatus==0 && result.length && [NSFileManager.defaultManager fileExistsAtPath:result]) self.statusLabel.stringValue=[@"已生成：" stringByAppendingString:result];
            else self.statusLabel.stringValue=@"转换失败，请检查文件和输出目录权限";
        });
    };
    NSError *error=nil; if (![task launchAndReturnError:&error]) { self.busy=NO; [self updateStart:nil]; self.statusLabel.stringValue=@"无法启动转换引擎"; }
}
- (void)exportImagesFrom:(int)first to:(int)last {
    NSURL *input=self.inputURL, *directory=self.outputDirectory;
    BOOL jpeg=self.imageFormat.indexOfSelectedItem==1;
    NSInteger dpi=[@[@72,@96,@150,@200,@300,@600][self.imageDpi.indexOfSelectedItem] integerValue];
    self.busy=YES; self.startButton.enabled=NO; self.statusLabel.stringValue=@"正在导出图片…";
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        CGPDFDocumentRef document=CGPDFDocumentCreateWithURL((__bridge CFURLRef)input);
        __block NSString *failure=nil; NSInteger saved=0;
        if (!document || CGPDFDocumentIsEncrypted(document)) failure=@"无法读取 PDF，或文件已加密";
        for (int pageNumber=first; !failure && pageNumber<=last; ++pageNumber) { @autoreleasepool {
            CGPDFPageRef page=CGPDFDocumentGetPage(document,pageNumber);
            if (!page) { failure=@"无法读取指定页面"; break; }
            CGRect box=CGPDFPageGetBoxRect(page,kCGPDFCropBox);
            int rotation=abs(CGPDFPageGetRotationAngle(page))%180;
            double w=(rotation ? box.size.height : box.size.width)*dpi/72.0;
            double h=(rotation ? box.size.width : box.size.height)*dpi/72.0;
            if (!isfinite(w) || !isfinite(h) || w<1 || h<1 || w*h>50000000) { failure=@"页面过大，请降低图片分辨率后重试"; break; }
            size_t width=(size_t)ceil(w), height=(size_t)ceil(h);
            CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
            CGContextRef context=CGBitmapContextCreate(NULL,width,height,8,0,color,kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(color);
            if (!context) { failure=@"无法创建图片，请降低分辨率后重试"; break; }
            CGContextSetRGBFillColor(context,1,1,1,1); CGContextFillRect(context,CGRectMake(0,0,width,height));
            CGFloat scale=dpi/72.0;
            CGContextScaleCTM(context,scale,scale);
            CGContextConcatCTM(context,CGPDFPageGetDrawingTransform(page,kCGPDFCropBox,CGRectMake(0,0,rotation ? box.size.height : box.size.width,rotation ? box.size.width : box.size.height),0,true));
            CGContextDrawPDFPage(context,page);
            CGImageRef image=CGBitmapContextCreateImage(context); CGContextRelease(context);
            NSBitmapImageRep *bitmap=image ? [[NSBitmapImageRep alloc] initWithCGImage:image] : nil;
            if (image) CGImageRelease(image);
            bitmap.size=NSMakeSize(width*72.0/dpi,height*72.0/dpi);
            NSData *data=[bitmap representationUsingType:jpeg ? NSBitmapImageFileTypeJPEG : NSBitmapImageFileTypePNG properties:jpeg ? @{NSImageCompressionFactor:@0.92} : @{}];
            if (!data) { failure=@"图片编码失败"; break; }
            NSString *base=input.lastPathComponent.stringByDeletingPathExtension;
            if (first!=last) base=[base stringByAppendingFormat:@"_%02d",pageNumber];
            BOOL written=NO;
            for (int number=0;number<10000;++number) {
                NSString *name=[NSString stringWithFormat:@"%@%@.%@",base,number ? [NSString stringWithFormat:@" (%d)",number] : @"",jpeg ? @"jpg" : @"png"];
                NSError *error=nil;
                if ([data writeToURL:[directory URLByAppendingPathComponent:name] options:NSDataWritingWithoutOverwriting error:&error]) { written=YES; break; }
                if (![error.domain isEqualToString:NSCocoaErrorDomain] || error.code!=NSFileWriteFileExistsError) { failure=error.localizedDescription ?: @"无法保存图片"; break; }
            }
            if (!written) { if (!failure) failure=@"同名图片过多，请选择其他目录"; break; }
            ++saved;
        }}
        if (document) CGPDFDocumentRelease(document);
        dispatch_async(dispatch_get_main_queue(), ^{
            self.busy=NO; [self updateStart:nil];
            self.statusLabel.stringValue=failure ? [NSString stringWithFormat:@"已保存 %ld 张，导出中止：%@",(long)saved,failure] : [NSString stringWithFormat:@"已保存 %ld 张图片：%@",(long)saved,directory.path];
        });
    });
}
@end

void MbsShowPdfConvert(int format, NSString *activePath) {
    static MbsPdfConvertWindow *controller;
    NSWindow *source=NSApp.mainWindow;
    NSURL *url=activePath.isAbsolutePath ? [NSURL fileURLWithPath:activePath] : source.representedURL;
    NSString *title=source.title;
    if (!url.isFileURL && [title.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
        char *json=MbsCopyRecentDocuments();
        NSData *data=json ? [NSData dataWithBytes:json length:strlen(json)] : nil;
        free(json);
        NSArray *records=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSMutableSet *matches=[NSMutableSet set];
        if ([records isKindOfClass:NSArray.class]) for (id record in records) {
            if (![record isKindOfClass:NSDictionary.class]) continue;
            NSString *path=record[@"path"];
            if ([path isKindOfClass:NSString.class] && [path.lastPathComponent isEqualToString:title] && [NSFileManager.defaultManager fileExistsAtPath:path]) [matches addObject:path];
        }
        if (matches.count==1) url=[NSURL fileURLWithPath:matches.anyObject];
    }
    if (![url.pathExtension.lowercaseString isEqualToString:@"pdf"]) url=nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!controller) controller=[MbsPdfConvertWindow new];
        if (format>=0 && format<5) [controller.format selectItemAtIndex:format];
        NSURL *selected=url;
        if (selected) [controller loadFile:selected]; else if (!controller.busy) [controller removeFile:nil];
        [controller updateStart:nil]; [controller showWindow:nil]; [controller.window makeKeyAndOrderFront:nil];
    });
}
