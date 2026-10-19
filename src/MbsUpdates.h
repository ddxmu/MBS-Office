#pragma once
#ifdef __cplusplus
extern "C" {
#endif

// The current updater downloads and verifies self-developed modules only.
// It does not extract, execute, install, quit the editor, or restart the app.
void MbsShowUpdates(void);
void MbsStartUpdateChecks(void);

#ifdef __cplusplus
}
#endif
