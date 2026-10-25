#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
python3 scripts/build-branding-resource.py
clang++ -target arm64-apple-macos13.0 -std=c++17 -dynamiclib \
  src/MbsOfflineFlags.cpp src/MbsNativeBranding.mm src/MbsBrandResources.mm src/MbsIntegration.cpp \
  src/MbsAiPanel.mm src/MbsAiPresentation.mm src/MbsAbout.mm src/MbsAiBridge.mm src/MbsLocalAccount.mm src/MbsEditorAuthorization.mm \
  src/MbsUpdates.mm src/MbsUiActions.mm src/MbsLoginAccessibility.mm src/MbsLegacyKeychain.mm src/MbsStartupRouting.mm src/MbsPluginPaths.mm src/MbsPdfPrivileges.cpp src/MbsLegacyUpdateNotice.mm src/MbsLegacyDialogRouting.mm src/MbsBrowserRetry.mm \
  -isystem "$(xcrun --show-sdk-path)/usr/include/c++/v1" -Isrc -fobjc-arc -framework AppKit -framework Security \
  -undefined dynamic_lookup -Wno-nullability-completeness -Wno-deprecated-declarations \
  -Wl,-sectcreate,__TEXT,__mbs_art,assets/mbs-ai-assistant.png \
  -Wl,-sectcreate,__TEXT,__mbs_brand,build/mbs-wordmark.rcc \
  -Wl,-sectcreate,__TEXT,__mbs_repair,assets/mbs-startup-repair.png \
  -o build/MbsOfflineFlags.dylib
