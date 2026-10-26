#define MBS_BROWSER_RETRY_TEST
#include "../src/MbsBrowserRetry.mm"
#include <assert.h>
#include <thread>
#include <unistd.h>
#include <sys/stat.h>
extern char **environ;

static void awaitFailures(const std::string &path,unsigned count) {
    double until=MbsRetryNow()+2;
    while (MbsRetryNow()<until) {
        { std::lock_guard<std::mutex> lock(MbsBrowserRetryLock);
          if (MbsBrowserRetries[path].failures==count) return; }
        usleep(10000);
    }
    assert(!"exit event not delivered");
}
int main() { @autoreleasepool {
    NSString *file=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
        @"Contents/SharedSupport/promecefpluginhost.app/Contents/MacOS/promecefpluginhost"];
    assert(![NSFileManager.defaultManager fileExistsAtPath:file]);
    [NSFileManager.defaultManager createDirectoryAtPath:file.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    [@"#!/bin/sh\nexit 42\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(file.fileSystemRepresentation,0700);
    std::string path=file.fileSystemRepresentation;
    char *argv[]={const_cast<char *>(path.c_str()),nullptr};
    for (unsigned i=1;i<=2;i++) {
        pid_t child=0; assert(MbsBrowserSpawn(&child,path.c_str(),nullptr,nullptr,argv,environ)==0);
        awaitFailures(path,i);
        int status=0;assert(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==42);
    }
    pid_t unchanged=123;errno=EDOM;
    double mainStart=MbsRetryNow();
    assert(MbsBrowserSpawn(&unchanged,path.c_str(),nullptr,nullptr,argv,environ)==0);
    assert(unchanged!=123 && errno==EDOM && MbsRetryNow()-mainStart<0.5);
    int third=0; assert(waitpid(unchanged,&third,0)==unchanged && WEXITSTATUS(third)==42);
    char ordinary[]="/usr/bin/true";char *normal[]={ordinary,nullptr};
    pid_t child=0;assert(MbsBrowserSpawnP(&child,ordinary,nullptr,nullptr,normal,environ)==0);
    int status;assert(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0);
    [@"#!/bin/sh\nexit 0\n" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];
    chmod(file.fileSystemRepresentation,0700);
    double start=MbsRetryNow();
    std::thread retry([&]{ assert(MbsBrowserSpawnP(&child,path.c_str(),nullptr,nullptr,argv,environ)==0); });
    retry.join(); assert(MbsRetryNow()-start>1);
    awaitFailures(path,0);
    assert(waitpid(child,&status,0)==child && WIFEXITED(status) && WEXITSTATUS(status)==0);
    [NSFileManager.defaultManager removeItemAtPath:[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"Contents"] error:nil];
    puts("PASS: rapid failures delay only exact CEF host, UI never waits, unrelated spawn unchanged, child status preserved, successful retry clears backoff");
} }
