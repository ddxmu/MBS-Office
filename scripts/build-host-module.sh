#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
clang++ -target arm64-apple-macos13.0 -std=c++17 -dynamiclib \
  src/MbsOfflineFlags.cpp src/MbsNativeBranding.mm src/MbsIntegration.cpp \
  src/MbsAiPanel.mm src/MbsAiBridge.mm src/MbsLocalAccount.mm src/MbsEditorAuthorization.mm \
  src/MbsUpdates.mm src/MbsUiActions.mm src/MbsPluginPaths.mm \
  -Isrc -fobjc-arc -framework AppKit -framework Security \
  -undefined dynamic_lookup -Wno-nullability-completeness -Wno-deprecated-declarations \
  -o build/MbsOfflineFlags.dylib
