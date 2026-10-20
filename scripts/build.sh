#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
clang++ -target arm64-apple-macos13.0 -std=c++17 -fobjc-arc -dynamiclib \
  src/MbsAiPanel.mm src/MbsLocalAccount.mm src/MbsEditorAuthorization.mm src/MbsUpdates.mm \
  -framework AppKit -framework Security -o build/MbsOfficeModules.dylib
swiftc -parse-as-library -target arm64-apple-macos13.0 \
  src/MbsModuleInstaller.swift -o build/MbsModuleInstaller
