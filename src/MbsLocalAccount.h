#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Presents the Mbs Office account window on the main queue.
void MbsShowLocalAccount(void);
// Describes the independent Mbs account service and self-developed features.
const char *MbsLocalAccountCapabilities(void);
// Caller owns this UTF-8 JSON buffer and must free() it. No password is returned.
char *MbsCopyLocalAccountState(void);
void MbsLocalAccountSignOut(void);
#ifdef __cplusplus
}
#endif
