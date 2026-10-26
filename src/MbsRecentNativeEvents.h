#pragma once
// Native event capture attaches automatically when the host module loads.
#ifdef MBS_RECENT_NATIVE_EVENTS_TEST
#ifdef __cplusplus
extern "C" {
#endif
bool MbsRecentNativeEventsTestBindImage(const void *header,const char *path);
void MbsRecentNativeEventsTestRemoveImage(const void *header);
void MbsRecentNativeEventsTestBind(const void *meta);
void MbsRecentNativeEventsTestActivate(void *sender,const void *meta,int signal,void **arguments);
#ifdef __cplusplus
}
#endif
#endif
