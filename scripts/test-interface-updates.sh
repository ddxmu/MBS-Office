#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mbs_test_tmp=$(mktemp -d -t mbs-interface-updates)
trap 'rm -rf "$mbs_test_tmp"' EXIT HUP INT TERM
clang++ -std=c++17 -fobjc-arc tests/website_routing_test.mm -framework Foundation -o "$mbs_test_tmp/website-routing"
"$mbs_test_tmp/website-routing"
mbs_frameworks='/Applications/Mbs Office.app/Contents/Resources/MbsEngine.app/Contents/Frameworks/office6'
clang++ -std=c++17 -fobjc-arc -ffunction-sections -Wno-deprecated-declarations \
  tests/ai_promotion_filter_test.mm -framework AppKit -F"$mbs_frameworks" -framework QtCoreKso \
  -Wl,-rpath,"$mbs_frameworks" -Wl,-dead_strip -Wl,-export_dynamic -Wl,-undefined,dynamic_lookup \
  -o "$mbs_test_tmp/ai-promotion-filter"
"$mbs_test_tmp/ai-promotion-filter"
