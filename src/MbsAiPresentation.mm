#import "MbsAiPresentation.h"

static NSError *PresentationError(NSString *message) {
    return [NSError errorWithDomain:@"MbsAiPresentation" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
NSArray<NSDictionary *> *MbsAiSlides(NSString *text, BOOL single, NSError **error) {
    NSString *json = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([json hasPrefix:@"```"]) {
        NSRange line = [json rangeOfString:@"\n"];
        if (line.location!=NSNotFound && [json hasSuffix:@"```"])
            json = [json substringWithRange:NSMakeRange(NSMaxRange(line),json.length-NSMaxRange(line)-3)];
    }
    id value = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    id slides = [value isKindOfClass:NSDictionary.class] ? value[@"slides"] : nil;
    BOOL valid = [slides isKindOfClass:NSArray.class] && [slides count]>0 && [slides count]<=30 && (!single || [slides count]==1);
    if (valid) for (id slide in slides) {
        if (![slide isKindOfClass:NSDictionary.class] || ![slide[@"title"] isKindOfClass:NSString.class] ||
            ![slide[@"title"] length] || [slide[@"title"] length]>160 ||
            ![slide[@"bullets"] isKindOfClass:NSArray.class] || [slide[@"bullets"] count]>6) { valid=NO; break; }
        for (id bullet in slide[@"bullets"]) if (![bullet isKindOfClass:NSString.class] || [bullet length]>300) valid=NO;
    }
    if (!valid) { if (error) *error=PresentationError(@"模型未返回有效幻灯片内容，请重新生成（每页标题及最多 6 条要点，单页模式仅一页）。"); return nil; }
    return slides;
}
static NSString *XML(NSString *value) {
    NSMutableString *text = [value mutableCopy];
    [text replaceOccurrencesOfString:@"[\\x00-\\x08\\x0B\\x0C\\x0E-\\x1F]" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0,text.length)];
    for (NSArray *pair in @[@[@"&",@"&amp;"],@[@"<",@"&lt;"],@[@">",@"&gt;"],@[@"\"",@"&quot;"],@[@"'",@"&apos;"]])
        [text replaceOccurrencesOfString:pair[0] withString:pair[1] options:0 range:NSMakeRange(0,text.length)];
    return text;
}
static NSString *Paragraph(NSString *text, BOOL title) {
    return [NSString stringWithFormat:@"<a:p><a:r><a:rPr lang=\"zh-CN\" sz=\"%d\" b=\"%d\"><a:solidFill><a:srgbClr val=\"%@\"/></a:solidFill><a:latin typeface=\"Aptos\"/><a:ea typeface=\"PingFang SC\"/></a:rPr><a:t>%@</a:t></a:r></a:p>",title?3200:2000,title?1:0,title?@"263566":@"334155",XML(text)];
}
static NSString *Shape(NSString *name, int identifier, long y, long height, NSString *paragraphs) {
    return [NSString stringWithFormat:@"<p:sp><p:nvSpPr><p:cNvPr id=\"%d\" name=\"%@\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"640000\" y=\"%ld\"/><a:ext cx=\"10900000\" cy=\"%ld\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"square\"/><a:lstStyle/>%@</p:txBody></p:sp>",identifier,name,y,height,paragraphs];
}
BOOL MbsAiWritePresentation(NSArray<NSDictionary *> *slides, NSURL *url, NSError **error) {
    // A complete editable OOXML package; no installed Python or Office automation is required.
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [fm.temporaryDirectory URLByAppendingPathComponent:[@"MbsAiSlides-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSURL *archive = [root URLByAppendingPathExtension:@"pptx"];
    NSMutableDictionary<NSString *,NSString *> *files = [NSMutableDictionary dictionary];
    NSString *pns=@"http://schemas.openxmlformats.org/presentationml/2006/main", *ans=@"http://schemas.openxmlformats.org/drawingml/2006/main";
    NSString *rns=@"http://schemas.openxmlformats.org/officeDocument/2006/relationships", *pkg=@"http://schemas.openxmlformats.org/package/2006/relationships";
    NSString *group=@"<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>";
    NSMutableString *ids=[NSMutableString string], *rels=[NSMutableString stringWithFormat:@"<Relationships xmlns=\"%@\"><Relationship Id=\"rMaster\" Type=\"%@/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>",pkg,rns];
    NSMutableString *types=[NSMutableString stringWithString:@"<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/><Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml\"/><Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/>"];
    NSUInteger n=0;
    for (NSDictionary *slide in slides) {
        ++n; NSMutableString *body=[NSMutableString string];
        for (NSString *bullet in slide[@"bullets"]) [body appendString:Paragraph([@"•  " stringByAppendingString:bullet],NO)];
        if (!body.length) [body appendString:@"<a:p/>"];
        files[[NSString stringWithFormat:@"ppt/slides/slide%lu.xml",(unsigned long)n]]=[NSString stringWithFormat:@"<p:sld xmlns:p=\"%@\" xmlns:a=\"%@\"><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val=\"F8FAFF\"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>%@%@%@</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>",pns,ans,group,Shape(@"Title",2,450000,1000000,Paragraph(slide[@"title"],YES)),Shape(@"Content",3,1650000,4500000,body)];
        files[[NSString stringWithFormat:@"ppt/slides/_rels/slide%lu.xml.rels",(unsigned long)n]]=[NSString stringWithFormat:@"<Relationships xmlns=\"%@\"><Relationship Id=\"rLayout\" Type=\"%@/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/></Relationships>",pkg,rns];
        [ids appendFormat:@"<p:sldId id=\"%lu\" r:id=\"r%lu\"/>",(unsigned long)(255+n),(unsigned long)n];
        [rels appendFormat:@"<Relationship Id=\"r%lu\" Type=\"%@/slide\" Target=\"slides/slide%lu.xml\"/>",(unsigned long)n,rns,(unsigned long)n];
        [types appendFormat:@"<Override PartName=\"/ppt/slides/slide%lu.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>",(unsigned long)n];
    }
    [types appendString:@"<Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/>"];
    files[@"[Content_Types].xml"]=[types stringByAppendingString:@"</Types>"];
    files[@"_rels/.rels"]=[NSString stringWithFormat:@"<Relationships xmlns=\"%@\"><Relationship Id=\"rOffice\" Type=\"%@/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>",pkg,rns];
    files[@"ppt/presentation.xml"]=[NSString stringWithFormat:@"<p:presentation xmlns:p=\"%@\" xmlns:r=\"%@\"><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"rMaster\"/></p:sldMasterIdLst><p:sldIdLst>%@</p:sldIdLst><p:sldSz cx=\"12192000\" cy=\"6858000\" type=\"screen16x9\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>",pns,rns,ids];
    files[@"ppt/_rels/presentation.xml.rels"]=[rels stringByAppendingString:@"</Relationships>"];
    files[@"ppt/slideMasters/slideMaster1.xml"]=[NSString stringWithFormat:@"<p:sldMaster xmlns:p=\"%@\" xmlns:a=\"%@\" xmlns:r=\"%@\"><p:cSld><p:spTree>%@</p:spTree></p:cSld><p:clrMap accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" bg1=\"lt1\" bg2=\"lt2\" folHlink=\"folHlink\" hlink=\"hlink\" tx1=\"dk1\" tx2=\"dk2\"/><p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"rLayout\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>",pns,ans,rns,group];
    files[@"ppt/slideMasters/_rels/slideMaster1.xml.rels"]=[NSString stringWithFormat:@"<Relationships xmlns=\"%@\"><Relationship Id=\"rLayout\" Type=\"%@/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rTheme\" Type=\"%@/theme\" Target=\"../theme/theme1.xml\"/></Relationships>",pkg,rns,rns];
    files[@"ppt/slideLayouts/slideLayout1.xml"]=[NSString stringWithFormat:@"<p:sldLayout xmlns:p=\"%@\" xmlns:a=\"%@\" type=\"blank\" preserve=\"1\"><p:cSld name=\"Mbs Office\"><p:spTree>%@</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>",pns,ans,group];
    files[@"ppt/slideLayouts/_rels/slideLayout1.xml.rels"]=[NSString stringWithFormat:@"<Relationships xmlns=\"%@\"><Relationship Id=\"rMaster\" Type=\"%@/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/></Relationships>",pkg,rns];
    NSMutableString *colors=[NSMutableString string];
    NSArray *colorNames=@[@"dk1",@"lt1",@"dk2",@"lt2",@"accent1",@"accent2",@"accent3",@"accent4",@"accent5",@"accent6",@"hlink",@"folHlink"];
    NSArray *colorValues=@[@"172033",@"FFFFFF",@"263566",@"F8FAFF",@"2563EB",@"795CFF",@"06B6D4",@"14B8A6",@"F59E0B",@"E879F9",@"2563EB",@"795CFF"];
    for (NSUInteger i=0;i<colorNames.count;i++) [colors appendFormat:@"<a:%@><a:srgbClr val=\"%@\"/></a:%@>",colorNames[i],colorValues[i],colorNames[i]];
    NSString *fill=@"<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>";
    NSString *line=[NSString stringWithFormat:@"<a:ln w=\"12700\">%@<a:prstDash val=\"solid\"/></a:ln>",fill];
    NSString *effect=@"<a:effectStyle><a:effectLst/></a:effectStyle>";
    NSString *font=@"<a:latin typeface=\"Aptos\"/><a:ea typeface=\"PingFang SC\"/><a:cs typeface=\"Arial\"/>";
    files[@"ppt/theme/theme1.xml"]=[NSString stringWithFormat:@"<a:theme xmlns:a=\"%@\" name=\"Mbs Office\"><a:themeElements><a:clrScheme name=\"Mbs\">%@</a:clrScheme><a:fontScheme name=\"Mbs\"><a:majorFont>%@</a:majorFont><a:minorFont>%@</a:minorFont></a:fontScheme><a:fmtScheme name=\"Mbs\"><a:fillStyleLst>%@%@%@</a:fillStyleLst><a:lnStyleLst>%@%@%@</a:lnStyleLst><a:effectStyleLst>%@%@%@</a:effectStyleLst><a:bgFillStyleLst>%@%@%@</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>",ans,colors,font,font,fill,fill,fill,line,line,line,effect,effect,effect,fill,fill,fill];
    BOOL ok=YES;
    for (NSString *path in files) {
        NSURL *file=[root URLByAppendingPathComponent:path];
        if (![fm createDirectoryAtURL:file.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error] ||
            ![files[path] writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:error]) { ok=NO; break; }
    }
    if (ok) {
        NSTask *zip=[NSTask new]; zip.executableURL=[NSURL fileURLWithPath:@"/usr/bin/ditto"];
        zip.arguments=@[@"-c",@"-k",@"--norsrc",@"--noextattr",root.path,archive.path];
        ok=[zip launchAndReturnError:error]; if (ok) { [zip waitUntilExit]; ok=zip.terminationStatus==0; }
        if (ok) ok=[[NSData dataWithContentsOfURL:archive] writeToURL:url options:NSDataWritingAtomic error:error];
        else if (error && !*error) *error=PresentationError(@"演示文稿打包失败。");
    }
    [fm removeItemAtURL:root error:nil]; [fm removeItemAtURL:archive error:nil]; return ok;
}
