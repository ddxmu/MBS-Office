#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Presents the local account window on the main queue. Never contacts a server.
void MbsShowLocalAccount(void);
// Does not grant, alter, or represent WPS subscription entitlements.
const char *MbsLocalAccountCapabilities(void);
#ifdef __cplusplus
}
#endif
