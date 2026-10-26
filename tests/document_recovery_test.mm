#define MBS_DOCUMENT_RECOVERY_TEST
#import "../src/MbsDocumentRecovery.mm"
#include <assert.h>
#include <sys/wait.h>
#include <signal.h>
int main() { @autoreleasepool {
    NSURL *base=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL *source=[base URLByAppendingPathComponent:@"source"], *dest=[base URLByAppendingPathComponent:@"dest"];
    NSFileManager *fm=NSFileManager.defaultManager;
    [fm createDirectoryAtURL:source withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *name=@"未保存验收.docx.0123456789abcdef0123456789ABCDEF.20261027010101000.wps";
    NSURL *native=[source URLByAppendingPathComponent:name];
    [@"unsaved native snapshot" writeToURL:native atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"original saved content" writeToURL:[source URLByAppendingPathComponent:@"original.docx"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [fm createSymbolicLinkAtURL:[source URLByAppendingPathComponent:@"link.docx.0123456789abcdef0123456789ABCDEF.20261027010101000.wps"] withDestinationURL:native error:nil];
    assert(MbsRecoverySnapshots(source,NSDate.distantPast).count==1);
    MbsRecoveryCapture(source,dest,NSDate.distantPast);
    assert(MbsRecoverySnapshots(dest,NSDate.distantPast).count==1);
    assert([[NSString stringWithContentsOfURL:[dest URLByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil] isEqual:@"unsaved native snapshot"]);
    assert(MbsRecoverySnapshots(source,[NSDate dateWithTimeIntervalSinceNow:60]).count==0);
    CFPropertyListRef enabled=MbsRecoveryPreference(CFSTR("6·0.common.Backup.EnableTimeBackup"),CFSTR("com.kingsoft.Office"),kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    assert([(__bridge NSNumber *)enabled intValue]==1); CFRelease(enabled);
    CFPropertyListRef interval=MbsRecoveryPreference(CFSTR("6·0.common.Backup.TimeBackupInterval"),CFSTR("com.kingsoft.Office"),kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    assert(CFEqual(interval,CFSTR("1")));CFRelease(interval);
    NSURL *marker=[base URLByAppendingPathComponent:@"active-session.plist"];
    [@"session" writeToURL:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    pid_t child=fork(); assert(child>=0);
    if (!child) { MbsRecoveryArmExitCleanup(marker.fileSystemRepresentation); exit(0); }
    int status=0; assert(waitpid(child,&status,0)==child && WIFEXITED(status));
    assert(![fm fileExistsAtPath:marker.path]);
    [@"session" writeToURL:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    int ready[2]; assert(pipe(ready)==0);
    child=fork(); assert(child>=0);
    if (!child) {
        close(ready[0]); MbsRecoveryArmExitCleanup(marker.fileSystemRepresentation);
        assert(write(ready[1],"1",1)==1); for (;;) pause();
    }
    close(ready[1]); char byte; assert(read(ready[0],&byte,1)==1); close(ready[0]);
    assert(kill(child,SIGKILL)==0 && waitpid(child,&status,0)==child && WIFSIGNALED(status));
    assert([fm fileExistsAtPath:marker.path]);
    // An atomically replaced marker belongs to a newer owner and must survive.
    MbsRecoveryArmExitCleanup(marker.fileSystemRepresentation);
    [@"new owner" writeToURL:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    MbsRecoveryNormalExit(); assert([fm fileExistsAtPath:marker.path]);
    [fm removeItemAtURL:base error:nil];
    puts("PASS: real native snapshot copied, ordinary originals and symlinks excluded, session cutoff, process-only timer settings, normal exit cleanup, SIGKILL persistence, changed-owner guard");
} }
