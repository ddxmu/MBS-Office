#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Presents the local account window on the main queue. Never contacts a server.
void MbsShowLocalAccount(void);
// Does not grant, alter, or represent WPS subscription entitlements.
const char *MbsLocalAccountCapabilities(void);
// Caller owns this UTF-8 JSON buffer and must free() it. No password is returned.
char *MbsCopyLocalAccountState(void);
void MbsLocalAccountSignOut(void);
#ifdef __cplusplus
}
#endif
