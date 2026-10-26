#import "MbsRecentHomeView.h"
#import "MbsRecentDocuments.h"

@interface MbsRecentHomeView : NSView <NSTableViewDataSource,NSTableViewDelegate>
@property NSArray<NSDictionary *> *records;
@property NSTableView *table;
@property NSScrollView *scroll;
@property NSTextField *empty;
@property NSTextField *rangeHint;
@property BOOL recentSelected;
@property BOOL lastDayOnly;
- (void)reload:(id)sender;
@end
@implementation MbsRecentHomeView
- (NSInteger)tag { return 0x4d425352+100; }
- (BOOL)isFlipped { return YES; }
- (instancetype)initWithFrame:(NSRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.recentSelected=YES;
    self.wantsLayer=YES; self.layer.backgroundColor=NSColor.whiteColor.CGColor;
    NSTextField *title=[NSTextField labelWithString:@"最近"];
    title.font=[NSFont boldSystemFontOfSize:23]; title.frame=NSMakeRect(20,22,70,32);
    [self addSubview:title];
    NSButton *refresh=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:@"刷新最近文档"]
        target:self action:@selector(reload:)];
    refresh.bordered=NO; refresh.frame=NSMakeRect(88,24,28,28); refresh.toolTip=@"刷新最近文档";
    [self addSubview:refresh];
    self.rangeHint=[NSTextField labelWithString:@""];
    self.rangeHint.frame=NSMakeRect(132,28,320,24);
    self.rangeHint.font=[NSFont systemFontOfSize:13]; self.rangeHint.textColor=NSColor.secondaryLabelColor;
    [self addSubview:self.rangeHint];
    self.scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(20,90,frame.size.width-40,frame.size.height-110)];
    self.scroll.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    self.scroll.hasVerticalScroller=YES; self.scroll.borderType=NSNoBorder;
    self.table=[[NSTableView alloc] initWithFrame:self.scroll.bounds];
    self.table.backgroundColor=NSColor.whiteColor; self.table.rowHeight=56;
    self.table.intercellSpacing=NSMakeSize(0,1); self.table.gridStyleMask=NSTableViewSolidHorizontalGridLineMask;
    self.table.gridColor=[NSColor colorWithWhite:0.94 alpha:1];
    self.table.delegate=self; self.table.dataSource=self; self.table.allowsMultipleSelection=NO;
    self.table.target=self; self.table.action=@selector(openSelected:);
    self.table.columnAutoresizingStyle=NSTableViewFirstColumnOnlyAutoresizingStyle;
    NSArray *keys=@[@"fileName",@"parentPath",@"modifiedTime",@"fileSize"];
    NSArray *names=@[@"文件名称",@"文件位置",@"最近修改",@"大小"];
    CGFloat widths[]={280,220,150,80};
    for (NSUInteger i=0;i<keys.count;i++) {
        NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:keys[i]];
        column.title=names[i]; column.width=widths[i]; column.minWidth=i==0 ? 180 : 65;
        [self.table addTableColumn:column];
    }
    self.table.accessibilityLabel=@"最近打开的本机文档";
    self.scroll.documentView=self.table; [self addSubview:self.scroll];
    self.empty=[NSTextField labelWithString:@"暂无打开记录\n打开或保存文档后，将在这里显示。"];
    self.empty.alignment=NSTextAlignmentCenter; self.empty.maximumNumberOfLines=2;
    self.empty.textColor=NSColor.secondaryLabelColor; self.empty.font=[NSFont systemFontOfSize:16];
    [self addSubview:self.empty];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reload:)
        name:@"MbsRecentDocumentsDidChange" object:nil];
    [self reload:nil]; return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)layout {
    [super layout];
    self.empty.frame=NSMakeRect(20,MAX(140,NSHeight(self.bounds)*0.45),NSWidth(self.bounds)-40,60);
}
- (void)reload:(id)sender {
    char *json=MbsCopyRecentDocuments();
    NSData *data=json ? [NSData dataWithBytes:json length:strlen(json)] : nil; free(json);
    id records=data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    self.records=MbsRecentDocumentRows([records isKindOfClass:NSArray.class] ? records : @[],self.lastDayOnly,NSDate.date);
    self.rangeHint.stringValue=self.lastDayOnly ? @"近24小时打开或保存的文档" : @"";
    self.empty.stringValue=self.lastDayOnly ? @"近24小时暂无打开或保存记录。" : @"暂无打开记录\n打开或保存文档后，将在这里显示。";
    [self.table reloadData]; self.empty.hidden=self.records.count!=0;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return self.records.count+1; }
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (row==(NSInteger)self.records.count) {
        if (![column.identifier isEqualToString:@"fileName"]) return nil;
        NSTextField *more=[NSTextField labelWithString:self.lastDayOnly ? @"返回最近15条" : @"更多文档"];
        more.textColor=NSColor.systemBlueColor; more.font=[NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
        more.toolTip=self.lastDayOnly ? @"返回不限时间的最近15条记录" : @"查看近24小时打开或保存的文档";
        return more;
    }
    NSDictionary *record=self.records[row]; NSString *key=column.identifier;
    NSTextField *label=[table makeViewWithIdentifier:key owner:self];
    if (!label) {
        label=[NSTextField labelWithString:@""]; label.identifier=key;
        label.lineBreakMode=NSLineBreakByTruncatingMiddle;
        label.font=[NSFont systemFontOfSize:14];
    }
    NSString *text=[record[key] isKindOfClass:NSString.class] ? record[key] : @"";
    if ([key isEqualToString:@"modifiedTime"]) {
        static NSDateFormatter *format; static dispatch_once_t once;
        dispatch_once(&once,^{format=[NSDateFormatter new];format.dateFormat=@"yyyy-MM-dd HH:mm";});
        text=[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[record[key] doubleValue]]];
    } else if ([key isEqualToString:@"fileSize"]) {
        text=[NSByteCountFormatter stringFromByteCount:[record[key] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    }
    label.stringValue=text ?: @""; label.toolTip=record[@"path"];
    label.textColor=[key isEqualToString:@"fileName"] ? NSColor.labelColor : NSColor.secondaryLabelColor;
    return label;
}
- (void)openSelected:(id)sender {
    NSInteger row=self.table.clickedRow;
    if (row==(NSInteger)self.records.count) {
        self.lastDayOnly=!self.lastDayOnly; [self reload:nil];
        [self.table deselectAll:nil]; [self.table scrollRowToVisible:0]; return;
    }
    if (row<0 || row>=(NSInteger)self.records.count) return;
    NSURL *url=[NSURL fileURLWithPath:self.records[row][@"path"]];
    [NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:NSBundle.mainBundle.bundleURL
        configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:^(NSRunningApplication *app,NSError *error) {
            if (!error) return;
            dispatch_async(dispatch_get_main_queue(),^{
                NSAlert *alert=[NSAlert new]; alert.messageText=@"文档未能打开";
                alert.informativeText=error.localizedDescription; [alert runModal];
            });
        }];
}
@end

void MbsUpdateRecentHomeView(NSWindow *window) {
    NSView *content=window.contentView; if (!content) return;
    const NSInteger tag=0x4d425352+100;
    MbsRecentHomeView *existing=(MbsRecentHomeView *)[content viewWithTag:tag];
    BOOL home=[window.title isEqualToString:@"首页"];
    if (!existing && home) {
        NSRect frame=NSMakeRect(345,content.isFlipped ? 104 : 12,
            MAX(0,NSWidth(content.bounds)-357),MAX(0,NSHeight(content.bounds)-116));
        existing=[[MbsRecentHomeView alloc] initWithFrame:frame];
        existing.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        [content addSubview:existing positioned:NSWindowAbove relativeTo:nil];
        // Leave the existing Starred, Shared and local-folder pages available.
        static dispatch_once_t once;
        dispatch_once(&once,^{
            [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
                NSView *root=event.window.contentView;
                MbsRecentHomeView *list=(MbsRecentHomeView *)[root viewWithTag:tag];
                if (list && [event.window.title isEqualToString:@"首页"]) {
                    NSPoint point=[root convertPoint:event.locationInWindow fromView:nil];
                    CGFloat top=root.isFlipped ? point.y : NSHeight(root.bounds)-point.y;
                    if (point.x>=69 && point.x<329 && top>=218) {
                        list.recentSelected=top<255;
                        list.hidden=!list.recentSelected;
                    }
                }
                return event;
            }];
        });
    }
    BOOL visible=home && existing.recentSelected;
    if (visible && existing.hidden) [existing reload:nil];
    if (existing.hidden==visible) existing.hidden=!visible;
}
