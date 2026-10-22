#pragma once

#ifdef __OBJC__
#import <Foundation/Foundation.h>
// Returns YES when Mbs consumed the path (including the login/authorization
// prompt), so the legacy editor must not open a visitor-mode document.
bool MbsOpenIndependentEditorPath(NSString *path);
#endif
