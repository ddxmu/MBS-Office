#include "MbsIntegration.h"
extern "C" const char *MbsIntegrationCapabilities()
{
    return "{\"apiVersion\":1,\"account\":\"local_only\",\"registration\":\"local_only\",\"ai\":\"openai_compatible_async\"}";
}
// Requests are neither transmitted nor stored by these unconfigured interfaces.
extern "C" int MbsAccountSignIn(const char *) { return MbsIntegrationNotConfigured; }
extern "C" int MbsAccountRegister(const char *) { return MbsIntegrationNotConfigured; }
extern "C" int MbsAiRequest(const char *) { return MbsIntegrationNotConfigured; }
