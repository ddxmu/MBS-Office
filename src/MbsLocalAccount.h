#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Validates a saved server session or presents the startup account window.
void MbsStartAccountSession(void);
// Presents the Mbs Office account window on the main queue.
void MbsShowLocalAccount(void);
// Explicit login buttons always present the login form, including when signed in.
void MbsShowLoginForm(void);
// Describes the independent Mbs account service and self-developed features.
const char *MbsLocalAccountCapabilities(void);
// Caller owns this UTF-8 JSON buffer and must free() it. No password is returned.
char *MbsCopyLocalAccountState(void);
void MbsLocalAccountSignOut(void);
// Returns the current signed-in email for native header/status updates.
const char *MbsCurrentAccountEmail(void);
// Updates the account hover card from the editor's small account hit area.
// The window pointer is borrowed and is only used during the call.
void MbsAccountHoverAtWindow(void *window, double x, double y);
void MbsHideAccountPopover(void);
#ifdef __cplusplus
}
#endif
