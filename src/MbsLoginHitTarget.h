#pragma once
#import <AppKit/AppKit.h>

// Read fresh AX frames for this click; never retain native widget pointers.
static NSArray<NSValue *> *MbsLoginButtonFrames(id root, NSRect windowFrame) {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
    NSMutableArray *frames = [NSMutableArray array];
    for (NSUInteger count=0; pending.count && count<256; ++count) {
        id item = pending.lastObject; [pending removeLastObject];
        NSString *role = MbsNativeAccessibilityValue(item,NSAccessibilityRoleAttribute);
        if (!role && [item respondsToSelector:@selector(accessibilityRole)]) role = [item accessibilityRole];
        NSString *title = MbsNativeAccessibilityValue(item,NSAccessibilityTitleAttribute);
        if (!title.length && [item respondsToSelector:@selector(accessibilityTitle)]) title = [item accessibilityTitle];
        NSString *label = MbsNativeAccessibilityValue(item,NSAccessibilityDescriptionAttribute);
        if (!label.length && [item respondsToSelector:@selector(accessibilityLabel)]) label = [item accessibilityLabel];
        BOOL login = [title isEqualToString:@"立即登录"] || [label isEqualToString:@"立即登录"];
        NSNumber *enabled = MbsNativeAccessibilityValue(item,NSAccessibilityEnabledAttribute);
        BOOL isEnabled = [enabled isKindOfClass:NSNumber.class] ? enabled.boolValue :
            (![item respondsToSelector:@selector(isAccessibilityEnabled)] || [item isAccessibilityEnabled]);
        if ([role isEqualToString:NSAccessibilityButtonRole] && login && isEnabled) {
            NSRect frame = [item respondsToSelector:@selector(accessibilityFrame)] ? [item accessibilityFrame] : NSZeroRect;
            if (NSIsEmptyRect(frame)) {
                NSValue *position = MbsNativeAccessibilityValue(item,NSAccessibilityPositionAttribute);
                NSValue *size = MbsNativeAccessibilityValue(item,NSAccessibilitySizeAttribute);
                if ([position isKindOfClass:NSValue.class] && [size isKindOfClass:NSValue.class])
                    frame = NSMakeRect(position.pointValue.x,position.pointValue.y,size.sizeValue.width,size.sizeValue.height);
            }
            if (frame.size.width>=20 && frame.size.width<=220 && frame.size.height>=12 && frame.size.height<=64 &&
                NSContainsRect(windowFrame,frame)) [frames addObject:[NSValue valueWithRect:frame]];
        }
        NSArray *children = MbsNativeAccessibilityValue(item,NSAccessibilityChildrenAttribute);
        if (!children.count && [item respondsToSelector:@selector(accessibilityChildren)]) children = [item accessibilityChildren];
        if ([children isKindOfClass:NSArray.class]) [pending addObjectsFromArray:children];
    }
    return frames;
}
