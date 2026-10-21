#pragma once
#import <AppKit/AppKit.h>
#import "MbsLocalAccount.h"

static NSString *MbsAccountEntryEmail(void) {
    const char *value = MbsCurrentAccountEmail();
    NSString *email = value ? [NSString stringWithUTF8String:value] : @"";
    free((void *)value);
    return email;
}

static NSString *MbsAccountEntryTitle(void) {
    NSString *email = MbsAccountEntryEmail();
    return email.length ? [email componentsSeparatedByString:@"@"].firstObject : @"立即登录";
}

static BOOL MbsIsAccountEntryText(NSString *text) {
    return [text isEqualToString:@"立即登录"] ||
        (MbsAccountEntryEmail().length && [text isEqualToString:MbsAccountEntryTitle()]);
}

static void MbsOpenAccountEntry(void) {
    if (MbsAccountEntryEmail().length) MbsShowLocalAccount();
    else MbsShowLoginForm();
}
