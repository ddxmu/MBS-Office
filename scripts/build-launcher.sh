#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
swiftc -O -target arm64-apple-macos13.0 \
  -framework AppKit -framework CryptoKit \
  src/MbsIndependentEditors.swift src/MbsLauncher.swift \
  -o build/MbsLauncher
codesign --force --sign - build/MbsLauncher >/dev/null
echo "build/MbsLauncher"
