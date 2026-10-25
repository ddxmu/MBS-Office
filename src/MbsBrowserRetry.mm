#import <Foundation/Foundation.h>
#include <spawn.h>
#include <sys/event.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <mutex>
#include <map>
#include <string>
#include <time.h>
#include <errno.h>
#include <algorithm>
#include <cstring>

// Only repeated early crashes of this bundle's CEF host earn a retry delay.
// Process exit observation never consumes the editor's waitpid result.
static double MbsRetryNow() {
    struct timespec value; clock_gettime(CLOCK_MONOTONIC,&value);
    return value.tv_sec+value.tv_nsec/1e9;
}
struct MbsBrowserRetryState {
    unsigned failures=0;
    double next=0;
    void exited(bool abnormal,double lifetime,double now) {
        if (!abnormal || lifetime>=5) { failures=0; next=0; return; }
        failures=std::min(failures+1,2u);
        next=now+(failures<2 ? 0 : 2);
    }
};
struct MbsBrowserChild { std::string path; double started; };
static std::mutex MbsBrowserRetryLock;
static std::map<std::string,MbsBrowserRetryState> MbsBrowserRetries;
static std::map<pid_t,MbsBrowserChild> MbsBrowserChildren;
static int MbsBrowserEvents=-1;
static dispatch_source_t MbsBrowserEventSource;

static bool MbsIsBrowserHost(const char *path) {
    if (!path) return false;
    static NSString *expected;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        expected=[NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:
            @"Contents/SharedSupport/promecefpluginhost.app/Contents/MacOS/promecefpluginhost"];
    });
    return strcmp(path,expected.fileSystemRepresentation)==0;
}
static void MbsObserveBrowser(pid_t pid,const char *path) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        MbsBrowserEvents=kqueue();
        if (MbsBrowserEvents<0) return;
        fcntl(MbsBrowserEvents,F_SETFD,FD_CLOEXEC);
        MbsBrowserEventSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_READ,MbsBrowserEvents,0,
            dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
        dispatch_source_set_event_handler(MbsBrowserEventSource,^{
            struct kevent event; struct timespec zero={0,0};
            while (kevent(MbsBrowserEvents,nullptr,0,&event,1,&zero)>0) {
                std::lock_guard<std::mutex> lock(MbsBrowserRetryLock);
                auto child=MbsBrowserChildren.find((pid_t)event.ident);
                if (child==MbsBrowserChildren.end()) continue;
                if (!(event.flags&EV_ERROR) && (event.fflags&NOTE_EXITSTATUS)) {
                    int status=(int)event.data;
                    bool failed=WIFSIGNALED(status) || (WIFEXITED(status) && WEXITSTATUS(status)!=0);
                    double now=MbsRetryNow();
                    MbsBrowserRetries[child->second.path].exited(failed,now-child->second.started,now);
                }
                MbsBrowserChildren.erase(child);
            }
        });
        dispatch_resume(MbsBrowserEventSource);
    });
    if (MbsBrowserEvents<0) return;
    std::lock_guard<std::mutex> lock(MbsBrowserRetryLock);
    MbsBrowserChildren[pid]={path,MbsRetryNow()};
    struct kevent change;
    EV_SET(&change,pid,EVFILT_PROC,EV_ADD|EV_ONESHOT,NOTE_EXIT|NOTE_EXITSTATUS,0,nullptr);
    if (kevent(MbsBrowserEvents,&change,1,nullptr,0,nullptr)<0) MbsBrowserChildren.erase(pid);
}
static bool MbsWaitForBrowserRetry(const char *path) {
    for (;;) {
        double delay;
        {
            std::lock_guard<std::mutex> lock(MbsBrowserRetryLock);
            auto &state=MbsBrowserRetries[path];
            delay=state.next-MbsRetryNow();
            if (delay<=0) {
                // Reserve the retry slot when several launch workers are waiting.
                if (state.failures>=2) state.next=MbsRetryNow()+2;
                return true;
            }
        }
        if (NSThread.isMainThread) return false;
        struct timespec pause={(time_t)delay,(long)((delay-(time_t)delay)*1e9)};
        while (nanosleep(&pause,&pause)<0 && errno==EINTR) {}
    }
}
using MbsSpawn=int (*)(pid_t *,const char *,const posix_spawn_file_actions_t *,
    const posix_spawnattr_t *,char *const[],char *const[]);
static thread_local bool MbsBrowserSpawnActive;
static int MbsLaunchBrowser(MbsSpawn original,pid_t *pid,const char *path,
    const posix_spawn_file_actions_t *actions,const posix_spawnattr_t *attrs,
    char *const argv[],char *const env[]) {
    if (MbsBrowserSpawnActive || !MbsIsBrowserHost(path)) return original(pid,path,actions,attrs,argv,env);
    int saved=errno;
    if (!MbsWaitForBrowserRetry(path)) { errno=saved; return EAGAIN; }
    pid_t child=0;
    MbsBrowserSpawnActive=true;
    int result=original(pid ? pid : &child,path,actions,attrs,argv,env);
    MbsBrowserSpawnActive=false;
    int after=errno;
    if (!result) MbsObserveBrowser(pid ? *pid : child,path);
    errno=after;
    return result;
}
static int MbsBrowserSpawn(pid_t *pid,const char *path,const posix_spawn_file_actions_t *actions,
    const posix_spawnattr_t *attrs,char *const argv[],char *const env[]) {
    return MbsLaunchBrowser(posix_spawn,pid,path,actions,attrs,argv,env);
}
static int MbsBrowserSpawnP(pid_t *pid,const char *path,const posix_spawn_file_actions_t *actions,
    const posix_spawnattr_t *attrs,char *const argv[],char *const env[]) {
    return MbsLaunchBrowser(posix_spawnp,pid,path,actions,attrs,argv,env);
}
#ifndef MBS_BROWSER_RETRY_TEST
struct MbsBrowserInterpose { const void *replacement,*original; };
__attribute__((used,section("__DATA,__interpose"))) static const MbsBrowserInterpose MbsBrowserSpawns[]={
    {(const void *)&MbsBrowserSpawn,(const void *)&posix_spawn},
    {(const void *)&MbsBrowserSpawnP,(const void *)&posix_spawnp}
};
#endif
