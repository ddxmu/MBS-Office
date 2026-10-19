#pragma once
#ifdef __cplusplus
extern "C" {
#endif

typedef void (*MbsAiInsertCallback)(const char *utf8Text);
typedef void (*MbsAiCompletion)(const char *utf8Result, const char *utf8Error);
// These functions may be called from any thread. UI and callbacks run on the main queue.
// Callback strings are valid only for the duration of the callback; copy if needed.
void MbsShowAiSettings(void);
void MbsShowAiAssistant(const char *operation, const char *text);
void MbsSetAiInsertCallback(MbsAiInsertCallback callback);
void MbsAiRequestAsync(const char *operation, const char *text, MbsAiCompletion completion);

#ifdef __cplusplus
}
#endif
