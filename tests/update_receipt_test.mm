#include "../src/MbsUpdates.mm"
#include <assert.h>

int main() { @autoreleasepool {
    NSMutableDictionary *receipt = [@{@"format":@"mbs-update-result-v1",@"fromVersion":@"0.2.3",
        @"toVersion":@"0.2.4",@"state":@"failed",@"message":@"请保存文档后重新升级。"} mutableCopy];
    NSData *(^encode)(void) = ^{ return [NSJSONSerialization dataWithJSONObject:receipt options:0 error:nil]; };
    assert([MbsInstallerFailure(encode(),@"0.2.3",@"0.2.4") isEqual:receipt[@"message"]]);
    assert(!MbsInstallerFailure(encode(),@"0.2.2",@"0.2.4"));
    assert(!MbsInstallerFailure(encode(),@"0.2.3",@"0.2.5"));
    receipt[@"state"] = @"completed";
    assert(!MbsInstallerFailure(encode(),@"0.2.3",@"0.2.4"));
    receipt[@"state"] = @"failed"; receipt[@"message"] = @42;
    assert(!MbsInstallerFailure(encode(),@"0.2.3",@"0.2.4"));
    assert(!MbsInstallerFailure([@"[]" dataUsingEncoding:NSUTF8StringEncoding],@"0.2.3",@"0.2.4"));
    assert(!MbsInstallerFailure([NSMutableData dataWithLength:16385],@"0.2.3",@"0.2.4"));
    puts("PASS: update errors belong to the exact upgrade; completed, malformed and oversized receipts rejected");
} }
