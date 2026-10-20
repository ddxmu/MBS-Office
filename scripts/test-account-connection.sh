#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
temporary=$(mktemp -d -t mbs-account-connection)
trap 'rm -rf "$temporary"' EXIT HUP INT TERM
clang++ -std=c++17 -fobjc-arc -Wno-nullability-completeness \
  tests/account_connection_test.mm -framework AppKit -framework Security -o "$temporary/test"
for scenario in login cached no-cache expires-before-later expired-session revoked-session retry cached-then-revoked; do
  mkdir "$temporary/$scenario"
  MBS_TEST_HOME="$temporary/$scenario" "$temporary/test" "$scenario"
done
