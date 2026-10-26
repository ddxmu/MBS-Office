#import <AppKit/AppKit.h>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#include <sys/stat.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

// Qt can exit normally without posting NSApplicationWillTerminate. This
// C-only exit hook removes only the session marker inode created by this run.
static char MbsRecoveryExitMarker[PATH_MAX];
static dev_t MbsRecoveryExitDevice;
static ino_t MbsRecoveryExitInode;
static void MbsRecoveryNormalExit(void) {
    struct stat value;
    if (MbsRecoveryExitMarker[0] && lstat(MbsRecoveryExitMarker,&value)==0 &&
        value.st_dev==MbsRecoveryExitDevice && value.st_ino==MbsRecoveryExitInode && S_ISREG(value.st_mode))
        unlink(MbsRecoveryExitMarker);
}
static void MbsRecoveryArmExitCleanup(const char *path) {
    struct stat value;
    if (!path || strlen(path)>=sizeof(MbsRecoveryExitMarker) || lstat(path,&value)!=0 || !S_ISREG(value.st_mode)) return;
    static bool registered=false;
    if (!registered && atexit(MbsRecoveryNormalExit)!=0) return;
    registered=true;
    strcpy(MbsRecoveryExitMarker,path);
    MbsRecoveryExitDevice=value.st_dev; MbsRecoveryExitInode=value.st_ino;
}

// Timed native snapshots stay enabled only in this Mbs process. The shared
// vendor preferences and the original document files are never rewritten.
static CFPropertyListRef MbsRecoveryPreference(CFStringRef key, CFStringRef app,
    CFStringRef user, CFStringRef host) {
    if (app && CFEqual(app,CFSTR("com.kingsoft.Office"))) {
        if (CFEqual(key,CFSTR("6·0.common.Backup.EnableTimeBackup")))
            return CFRetain((__bridge CFTypeRef)@1);
        if (CFEqual(key,CFSTR("6·0.common.Backup.TimeBackupInterval")))
            return CFRetain(CFSTR("1"));
    }
    return CFPreferencesCopyValue(key,app,user,host);
}

static NSArray<NSURL *> *MbsRecoverySnapshots(NSURL *source, NSDate *since) {
    NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtURL:source
        includingPropertiesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,NSURLContentModificationDateKey,NSURLFileSizeKey]
        options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:
        @"^.+\\.[0-9a-fA-F]{32}\\.[0-9]{17}\\.(wps|et|pptx|pdf|docx|xlsx|dps)$" options:0 error:nil];
    NSMutableArray *result=[NSMutableArray array];
    for (NSURL *file in files) {
        NSString *name=file.lastPathComponent;
        if (![pattern numberOfMatchesInString:name options:0 range:NSMakeRange(0,name.length)]) continue;
        NSDictionary *values=[file resourceValuesForKeys:@[NSURLIsRegularFileKey,NSURLIsSymbolicLinkKey,
            NSURLContentModificationDateKey,NSURLFileSizeKey] error:nil];
        if (![values[NSURLContentModificationDateKey] isKindOfClass:NSDate.class] || ![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLIsSymbolicLinkKey] boolValue] ||
            [values[NSURLFileSizeKey] unsignedLongLongValue]==0 ||
            [values[NSURLFileSizeKey] unsignedLongLongValue]>128ULL*1024*1024 ||
            [values[NSURLContentModificationDateKey] compare:since]==NSOrderedAscending) continue;
        [result addObject:file];
    }
    return result;
}
static void MbsRecoveryCapture(NSURL *source, NSURL *destination, NSDate *since) {
    NSFileManager *fm=NSFileManager.defaultManager;
    for (NSURL *file in MbsRecoverySnapshots(source,since)) {
        [fm createDirectoryAtURL:destination withIntermediateDirectories:YES
            attributes:@{NSFilePosixPermissions:@0700} error:nil];
        NSURL *target=[destination URLByAppendingPathComponent:file.lastPathComponent];
        NSDictionary *current=[target resourceValuesForKeys:@[NSURLContentModificationDateKey] error:nil];
        NSDictionary *native=[fm attributesOfItemAtPath:file.path error:nil];
        if ([current[NSURLContentModificationDateKey] isEqual:native[NSFileModificationDate]]) continue;
        // Copy via a temporary sibling so an interrupted write never replaces a
        // complete recovery snapshot. Native backup names already carry version IDs.
        NSURL *temporary=[destination URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        if (![fm copyItemAtURL:file toURL:temporary error:nil]) continue;
        NSDictionary *after=[fm attributesOfItemAtPath:file.path error:nil];
        NSDictionary *copied=[fm attributesOfItemAtPath:temporary.path error:nil];
        if (![native[NSFileModificationDate] isEqual:after[NSFileModificationDate]] ||
            ![native[NSFileSize] isEqual:after[NSFileSize]] || ![native[NSFileSize] isEqual:copied[NSFileSize]]) {
            [fm removeItemAtURL:temporary error:nil]; continue;
        }
        if ([fm fileExistsAtPath:target.path])
            [fm replaceItemAtURL:target withItemAtURL:temporary backupItemName:nil options:0 resultingItemURL:nil error:nil];
        else [fm moveItemAtURL:temporary toURL:target error:nil];
        [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:target.path error:nil];
    }
}
static BOOL MbsRecoveryOffer(NSURL *folder) {
    NSArray *files=MbsRecoverySnapshots(folder,NSDate.distantPast);
    if (!files.count) return YES;
    NSAlert *alert=[NSAlert new];
    alert.window.title=@"文档恢复";
    alert.messageText=@"恢复上次编辑的文档";
    alert.informativeText=[NSString stringWithFormat:@"上次 Mbs Office 未正常退出，已保留 %lu 份自动恢复快照。请选择需要恢复的文档，打开后请另存为；原文件不会被覆盖。快照包含最近一次自动备份的内容，尚未来得及备份的修改可能无法恢复。",(unsigned long)files.count];
    [alert addButtonWithTitle:@"选择恢复文档…"];
    [alert addButtonWithTitle:@"稍后恢复"];
    [NSApp activateIgnoringOtherApps:YES];
    [alert.window makeKeyAndOrderFront:nil];
    if ([alert runModal]!=NSAlertFirstButtonReturn) return NO;
    NSOpenPanel *picker=[NSOpenPanel openPanel];
    picker.title=@"选择自动恢复快照"; picker.directoryURL=folder;
    picker.canChooseDirectories=NO; picker.allowsMultipleSelection=YES;
    if ([picker runModal]!=NSModalResponseOK) return NO;
    for (NSURL *url in picker.URLs) {
        if (![url.URLByDeletingLastPathComponent.standardizedURL isEqual:folder.standardizedURL]) continue;
        [NSWorkspace.sharedWorkspace openURLs:@[url] withApplicationAtURL:NSBundle.mainBundle.bundleURL
            configuration:NSWorkspaceOpenConfiguration.configuration completionHandler:nil];
    }
    return YES;
}
static void MbsScheduleRecoveryOffer(NSURL *folder, NSURL *pending) {
    __block BOOL shown=NO;
    __block id becameKey=nil, closed=nil, activated=nil;
    void (^attempt)(void)=^{
        if (shown || !NSApp.isActive || NSApp.modalWindow) return;
        for (NSWindow *window in NSApp.windows)
            if (window.isVisible && [window.title isEqualToString:@"Mbs Office 账号"]) return;
        shown=YES;
        for (id observer in @[becameKey,closed,activated])
            [NSNotificationCenter.defaultCenter removeObserver:observer];
        becameKey=nil; closed=nil; activated=nil;
        if (MbsRecoveryOffer(folder)) [NSFileManager.defaultManager removeItemAtURL:pending error:nil];
    };
    void (^changed)(NSNotification *)=^(NSNotification *note) { dispatch_async(dispatch_get_main_queue(),attempt); };
    becameKey=[NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeKeyNotification object:nil queue:nil usingBlock:changed];
    closed=[NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification object:nil queue:nil usingBlock:changed];
    activated=[NSNotificationCenter.defaultCenter addObserverForName:NSApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:changed];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),attempt);
}
#ifndef MBS_DOCUMENT_RECOVERY_TEST
struct MbsRecoveryInterpose { const void *replacement,*original; };
__attribute__((used,section("__DATA,__interpose"))) static const MbsRecoveryInterpose MbsRecoveryPreferences[]={
    {(const void *)&MbsRecoveryPreference,(const void *)&CFPreferencesCopyValue}
};
__attribute__((constructor)) static void MbsInstallDocumentRecovery(void) {
    dispatch_async(dispatch_get_main_queue(),^{
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.mbs.office.wps"]) return;
        NSURL *base=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
            URLByAppendingPathComponent:@"Mbs Office/Recovery" isDirectory:YES];
        NSFileManager *fm=NSFileManager.defaultManager;
        [fm createDirectoryAtURL:base withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
        static int lock=-1; lock=open([base URLByAppendingPathComponent:@"session.lock"].fileSystemRepresentation,O_CREAT|O_RDWR|O_CLOEXEC,0600);
        if (lock<0 || flock(lock,LOCK_EX|LOCK_NB)!=0) return;
        NSURL *marker=[base URLByAppendingPathComponent:@"active-session.plist"];
        NSURL *pending=[base URLByAppendingPathComponent:@"pending-session.plist"];
        NSDictionary *previous=[NSDictionary dictionaryWithContentsOfURL:marker];
        NSString *prior=[previous[@"id"] isKindOfClass:NSString.class] ? previous[@"id"] : nil;
        NSURL *oldSession=prior && [[NSUUID alloc] initWithUUIDString:prior] ? [base URLByAppendingPathComponent:prior] : nil;
        if (oldSession && MbsRecoverySnapshots(oldSession,NSDate.distantPast).count)
            [@{@"id":prior} writeToURL:pending atomically:YES];
        NSDictionary *pendingState=[NSDictionary dictionaryWithContentsOfURL:pending];
        NSString *pendingID=[pendingState[@"id"] isKindOfClass:NSString.class] ? pendingState[@"id"] : nil;
        NSURL *offered=pendingID && [[NSUUID alloc] initWithUUIDString:pendingID] ? [base URLByAppendingPathComponent:pendingID] : nil;
        NSString *identifier=NSUUID.UUID.UUIDString;
        NSDate *started=NSDate.date;
        NSURL *destination=[base URLByAppendingPathComponent:identifier isDirectory:YES];
        if ([@{@"id":identifier,@"started":started} writeToURL:marker atomically:YES])
            MbsRecoveryArmExitCleanup(marker.fileSystemRepresentation);
        NSURL *source=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@".kingsoft/office6/data/backup"] isDirectory:YES];
        dispatch_queue_t queue=dispatch_queue_create("com.mbs.office.document-recovery",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));
        static dispatch_source_t timer;
        timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
        dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),30*NSEC_PER_SEC,3*NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer,^{ @autoreleasepool { MbsRecoveryCapture(source,destination,started); } });
        dispatch_resume(timer);
        [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillTerminateNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            [fm removeItemAtURL:marker error:nil];
        }];
        if (offered) MbsScheduleRecoveryOffer(offered,pending);
    });
}
#endif
