#import <AppKit/AppKit.h>

static id MbsNativeAccessibilityValue(id item, NSString *attribute) {
    return [item respondsToSelector:@selector(accessibilityAttributeValue:)] ? [item accessibilityAttributeValue:attribute] : nil;
}

static BOOL MbsHasLegacyCloudNotice(id root) {
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    for (NSUInteger count=0;pending.count && count<64;++count) {
        id item=pending.lastObject; [pending removeLastObject];
        for (NSString *attribute in @[NSAccessibilityTitleAttribute,NSAccessibilityDescriptionAttribute,NSAccessibilityValueAttribute]) {
            id value=MbsNativeAccessibilityValue(item,attribute);
            if ([value isKindOfClass:NSString.class] &&
                [value containsString:@"云服务连接异常，已开启离线特殊兼容"]) return YES;
        }
        NSString *label=[item respondsToSelector:@selector(accessibilityLabel)] ? [item accessibilityLabel] : nil;
        if ([label containsString:@"云服务连接异常，已开启离线特殊兼容"]) return YES;
        NSString *title=[item respondsToSelector:@selector(accessibilityTitle)] ? [item accessibilityTitle] : nil;
        if ([title containsString:@"云服务连接异常，已开启离线特殊兼容"]) return YES;
        NSArray *children=[item respondsToSelector:@selector(accessibilityChildren)] ? [item accessibilityChildren] : nil;
        if (!children.count) children=MbsNativeAccessibilityValue(item,NSAccessibilityChildrenAttribute);
        if ([children isKindOfClass:NSArray.class]) [pending addObjectsFromArray:children];
    }
    return NO;
}

// A normal online login must not be cancelled merely because it offers Later.
static id MbsFailedNativeLoginAction(id root) {
    NSMutableArray *pending = [NSMutableArray arrayWithObject:root];
    id later = nil;
    BOOL failed = NO;
    for (NSUInteger inspected=0; pending.count && inspected<256; ++inspected) {
        id item = pending.lastObject;
        [pending removeLastObject];
        NSString *role = [item respondsToSelector:@selector(accessibilityRole)] ? [item accessibilityRole] : nil;
        if (!role) role = MbsNativeAccessibilityValue(item,NSAccessibilityRoleAttribute);
        NSString *label = [item respondsToSelector:@selector(accessibilityLabel)] ? [item accessibilityLabel] : nil;
        NSString *title = [item respondsToSelector:@selector(accessibilityTitle)] ? [item accessibilityTitle] : nil;
        if (!title) title = MbsNativeAccessibilityValue(item,NSAccessibilityTitleAttribute);
        if (!label) label = MbsNativeAccessibilityValue(item,NSAccessibilityDescriptionAttribute);
        id value = MbsNativeAccessibilityValue(item,NSAccessibilityValueAttribute);
        for (id text in @[title ?: @"", label ?: @"", value ?: @""]) {
            if ([text isKindOfClass:NSString.class] &&
                ([text containsString:@"页面加载失败"] || [text containsString:@"Failed to load page"])) failed = YES;
        }
        if ([role isEqualToString:NSAccessibilityButtonRole] &&
            ([label isEqualToString:@"稍后登录"] || [title isEqualToString:@"稍后登录"])) later = item;
        NSArray *children = [item respondsToSelector:@selector(accessibilityChildren)] ? [item accessibilityChildren] : nil;
        if (!children.count) children = MbsNativeAccessibilityValue(item,NSAccessibilityChildrenAttribute);
        if ([children isKindOfClass:NSArray.class]) [pending addObjectsFromArray:children];
    }
    return failed ? later : nil;
}
