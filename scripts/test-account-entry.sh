#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mbs_test_tmp=$(mktemp -d -t mbs-account-entry)
trap 'rm -rf "$mbs_test_tmp"' EXIT HUP INT TERM
for mbs_test_case in account_entry login_accessibility login_hit_target; do
  clang++ -std=c++17 -fobjc-arc -Wno-deprecated-declarations "tests/${mbs_test_case}_test.mm" \
    -framework AppKit -o "$mbs_test_tmp/$mbs_test_case"
  "$mbs_test_tmp/$mbs_test_case"
done
mbs_engine='/Applications/Mbs Office.app/Contents/Resources/MbsEngine.app/Contents'
clang++ -std=c++17 -fobjc-arc -ffunction-sections -Wno-deprecated-declarations \
  tests/native_account_entries_test.mm -framework AppKit -framework Security \
  -F"$mbs_engine/Frameworks/office6" -framework QtWidgetsKso -framework QtCoreKso \
  -Wl,-rpath,"$mbs_engine/Frameworks/office6" -Wl,-dead_strip -Wl,-undefined,dynamic_lookup \
  -o "$mbs_test_tmp/native-account-entries-test"
QT_PLUGIN_PATH="$mbs_engine/PlugIns" "$mbs_test_tmp/native-account-entries-test"
