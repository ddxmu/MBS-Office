#pragma once
#ifdef __cplusplus
extern "C" {
#endif
bool MbsHasVerifiedEditorLicense(void);
// Checks only the signed Mbs account grant, never editor/vendor entitlements.
bool MbsCanRestoreAccountSession(const char *token, const char *email);
void MbsRequestEditorLicense(const char *token, const char *email);
void MbsRedeemActivationCode(const char *code);
void MbsResetEditorLicense(void);
char *MbsCopyEditorAuthorizationState(void);
#ifdef __cplusplus
}
#endif

#ifdef __OBJC__
#import <Foundation/Foundation.h>
NSDictionary *MbsVerifyEditorGrant(NSData *response, NSData *publicKey,
    NSString *nonce, NSString *email, NSString *device, NSString *sessionHash, NSTimeInterval now);
// Call only with claims already returned by MbsVerifyEditorGrant.
bool MbsEditorGrantAllowsEditing(NSDictionary *verifiedClaims);
#endif
