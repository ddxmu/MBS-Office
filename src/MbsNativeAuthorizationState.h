#pragma once
#include <stdint.h>

enum MbsNativeAuthorizationOperation : unsigned {
    MbsNativeAuthSync = 1, MbsNativeAuthCheck, MbsNativeAuthTrial,
    MbsNativeAuthFree, MbsNativeAuthPaying, MbsNativeAuthInvalid,
    MbsNativeAuthVisitor, MbsNativeAuthRemainingSecs, MbsNativeAuthRemainingDays,
    MbsNativeAuthZero, MbsNativeAuthStatus, MbsNativeAuthAuthority, MbsNativeAuthType
};

// Called only from version-bound native adapters. QString results use result,
// the caller's uninitialized hidden-return storage; old setter arguments confer no authority.
extern "C" uint64_t MbsNativeAuthorizationDispatch(void *manager, unsigned operation,
    const void *arg1, const void *arg2, void *result);
// Redacted runtime evidence; caller owns the JSON buffer.
extern "C" char *MbsCopyNativeAuthorizationDiagnostics(void);
