#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import "../src/MbsEditorAuthorization.h"

static NSString *hash(NSData *data) {
    unsigned char bytes[32]; CC_SHA256(data.bytes,(CC_LONG)data.length,bytes);
    NSMutableString *text = [NSMutableString string];
    for (unsigned char byte : bytes) [text appendFormat:@"%02x",byte];
    return text;
}
int main(void) { @autoreleasepool {
    NSDictionary *attributes = @{(__bridge id)kSecAttrKeyType:(__bridge id)kSecAttrKeyTypeECSECPrimeRandom,
        (__bridge id)kSecAttrKeySizeInBits:@256};
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes,NULL);
    NSCAssert(privateKey,@"create private key");
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    NSData *publicBytes = CFBridgingRelease(SecKeyCopyExternalRepresentation(publicKey,NULL));
    NSString *keyId = [@"mbs-editor-p256-" stringByAppendingString:[hash(publicBytes) substringToIndex:16]];
    double now = floor(NSDate.date.timeIntervalSince1970);
    NSString *nonce = [@"n" stringByPaddingToLength:43 withString:@"n" startingAtIndex:0];
    NSString *device = NSUUID.UUID.UUIDString, *email = @"qa@example.invalid", *session = hash([@"test-session" dataUsingEncoding:NSUTF8StringEncoding]);
    NSDictionary *valid = @{@"version":@1,@"issuer":@"https://ttys.ddxmu.com",@"audience":@"mbs.office.editor.custom",
        @"authority":@"mbs-custom",@"userId":@42,@"email":email,@"deviceId":device,@"nonce":nonce,
        @"sessionHash":session,@"issuedAt":@(now),@"expiresAt":@(now+86400),@"jti":@"01234567890123456789012345678901"};
    NSData *(^sign)(NSDictionary *) = ^NSData *(NSDictionary *claims) {
        NSData *payload = [NSJSONSerialization dataWithJSONObject:claims options:NSJSONWritingSortedKeys error:nil];
        NSData *signature = CFBridgingRelease(SecKeyCreateSignature(privateKey,kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
            (__bridge CFDataRef)payload,NULL));
        return [NSJSONSerialization dataWithJSONObject:@{@"ok":@YES,@"payload":[payload base64EncodedStringWithOptions:0],
            @"signature":[signature base64EncodedStringWithOptions:0],@"keyId":keyId} options:0 error:nil];
    };
    NSData *envelope = sign(valid);
    NSCAssert(MbsVerifyEditorGrant(envelope,publicBytes,nonce,email,device,session,now),@"valid grant");
    NSMutableDictionary *activated = [valid mutableCopy];
    activated[@"activation"] = @{@"id":@1,@"plan":@"vip",@"expiresAt":@(now+86400),@"maxDevices":@1,@"deviceId":device};
    NSCAssert(MbsVerifyEditorGrant(sign(activated),publicBytes,nonce,email,device,session,now),@"signed activation grant");
    for (NSDictionary *mutation in @[@{@"id":@0},@{@"plan":@"admin"},@{@"expiresAt":@(now+1)},
        @{@"deviceId":NSUUID.UUID.UUIDString},@{@"maxDevices":@0},@{@"maxDevices":@YES}]) {
        NSMutableDictionary *metadata = [activated[@"activation"] mutableCopy]; [metadata addEntriesFromDictionary:mutation];
        NSMutableDictionary *claims = [activated mutableCopy]; claims[@"activation"] = metadata;
        NSCAssert(!MbsVerifyEditorGrant(sign(claims),publicBytes,nonce,email,device,session,now),@"invalid activation metadata");
    }
    NSCAssert(!MbsVerifyEditorGrant(envelope,publicBytes,@"different",email,device,session,now),@"nonce replay");
    NSCAssert(!MbsVerifyEditorGrant(envelope,publicBytes,nonce,@"other@example.invalid",device,session,now),@"account binding");
    NSCAssert(!MbsVerifyEditorGrant(envelope,publicBytes,nonce,email,NSUUID.UUID.UUIDString,session,now),@"device binding");
    NSCAssert(!MbsVerifyEditorGrant(envelope,publicBytes,nonce,email,device,@"other",now),@"session binding");
    NSCAssert(!MbsVerifyEditorGrant(envelope,publicBytes,nonce,email,device,session,now+86400),@"expired grant");
    for (NSString *field in @[@"issuer",@"audience",@"authority",@"jti"]) {
        NSMutableDictionary *claims = [valid mutableCopy]; claims[field] = @"wrong";
        NSCAssert(!MbsVerifyEditorGrant(sign(claims),publicBytes,nonce,email,device,session,now),@"wrong claim %@",field);
    }
    for (NSDictionary *mutation in @[@{@"version":@YES},@{@"issuedAt":@(now+301)},@{@"expiresAt":@(now+31*86400)},@{@"userId":@0}]) {
        NSMutableDictionary *claims = [valid mutableCopy]; [claims addEntriesFromDictionary:mutation];
        NSCAssert(!MbsVerifyEditorGrant(sign(claims),publicBytes,nonce,email,device,session,now),@"claim bounds");
    }
    NSMutableDictionary *tampered = [[NSJSONSerialization JSONObjectWithData:envelope options:0 error:nil] mutableCopy];
    NSMutableDictionary *claims = [valid mutableCopy]; claims[@"expiresAt"] = @(now+86401);
    tampered[@"payload"] = [[NSJSONSerialization dataWithJSONObject:claims options:0 error:nil] base64EncodedStringWithOptions:0];
    NSData *bad = [NSJSONSerialization dataWithJSONObject:tampered options:0 error:nil];
    NSCAssert(!MbsVerifyEditorGrant(bad,publicBytes,nonce,email,device,session,now),@"tampered signature");
    NSMutableData *wrongKey = [publicBytes mutableCopy]; ((unsigned char *)wrongKey.mutableBytes)[20] ^= 1;
    NSCAssert(!MbsVerifyEditorGrant(envelope,wrongKey,nonce,email,device,session,now),@"wrong pinned key");
    NSCAssert(!MbsVerifyEditorGrant([@"[]" dataUsingEncoding:NSUTF8StringEncoding],publicBytes,nonce,email,device,session,now),@"malformed response");
    CFRelease(publicKey); CFRelease(privateKey);
    puts("PASS: signed grant, account/device/session/nonce binding, expiry, claims, tampering and pinned key");
} return 0; }
