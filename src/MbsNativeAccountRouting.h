#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Called only by the version-bound native account entry adapters.
// 1=login, 2=logout, 3=old automatic login, 4=old LoginSNAuth switch.
int MbsNativeAccountRoute(void *proxy, int action);
void MbsRepublishNativeAccountState(void);
void MbsSyncForceLoginAccount(void);
// Returns false without constructing output for an unrelated query.
// For the exact force-login editing query, constructs a native QVariant(bool).
bool MbsNativeAccountQuery(void *proxy, const void *key, void *output);
#ifdef __cplusplus
}
#endif
