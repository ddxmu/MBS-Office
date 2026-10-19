#pragma once
#ifdef __cplusplus
extern "C" {
#endif
// Legacy synchronous boundary. New UI modules expose separate asynchronous APIs.
enum MbsIntegrationResult { MbsIntegrationNotConfigured = 1 };
const char *MbsIntegrationCapabilities(void);
int MbsAccountSignIn(const char *requestJson);
int MbsAccountRegister(const char *requestJson);
int MbsAiRequest(const char *requestJson);
#ifdef __cplusplus
}
#endif
