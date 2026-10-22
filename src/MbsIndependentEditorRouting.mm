#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import "MbsEditorAuthorization.h"
#import "MbsAccountEntry.h"
#import "MbsIndependentEditorRouting.h"

static NSString *MbsIndependentEditorBundle(NSString *extension) {
    if ([@[@"doc", @"docx", @"dot", @"dotx", @"dotm", @"docm", @"rtf"] containsObject:extension]) return @"MyAI Word.app";
    if ([@[@"xls", @"xlsx", @"xlsm", @"xlt", @"xltx", @"xltm", @"csv"] containsObject:extension]) return @"MyAI Excel.app";
    if ([@[@"ppt", @"pptx", @"pptm", @"pot", @"potx", @"potm"] containsObject:extension]) return @"MyAI Power Point.app";
    if ([extension isEqualToString:@"pdf"]) return @"MyAI PDF.app";
    return nil;
}

bool MbsOpenIndependentEditorPath(NSString *path) {
    if (!path.length || !path.isAbsolutePath) return NO;
    NSString *bundleName = MbsIndependentEditorBundle(path.pathExtension.lowercaseString);
    if (!bundleName) return NO;

    // The Mbs grant has already been signature-checked by the host module's
    // startup restore path. Never turn an unverified account into editor
    // access; show the existing Mbs login/account surface instead.
    if (!MbsHasVerifiedEditorLicense()) {
        MbsOpenAccountEntry();
        return YES;
    }

    NSBundle *engine = NSBundle.mainBundle;
    NSURL *outer = engine.bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
    NSURL *helper = [outer URLByAppendingPathComponent:[@"Contents/Helpers" stringByAppendingPathComponent:bundleName] isDirectory:YES];
    NSURL *executable = [helper URLByAppendingPathComponent:@"Contents/MacOS" isDirectory:YES];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:executable.path]) return NO;

    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration new];
    configuration.activates = YES;
    [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:path]]
                      withApplicationAtURL:helper
                             configuration:configuration
                         completionHandler:^(NSRunningApplication *application, NSError *error) {
        if (error) {
            NSAlert *alert = [NSAlert new];
            alert.messageText = @"独立编辑器启动失败";
            alert.informativeText = error.localizedDescription ?: @"请重新安装完整 Mbs Office。";
            [alert addButtonWithTitle:@"好"]; [alert runModal];
        }
    }];
    return YES;
}
