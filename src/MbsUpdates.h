#pragma once
#ifdef __cplusplus
extern "C" {
#endif

// Downloads signed self-developed modules and delegates installation and restart
// to the separate installer, preserving the editor's normal save/quit prompts.
void MbsShowUpdates(void);
void MbsStartUpdateChecks(void);

#ifdef __cplusplus
}
#endif
