#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bundle="$PWD/.build/UpdaterValidation.app"
mkdir -p "$bundle/Contents/MacOS" .build/module-cache
cp Tests/UpdaterValidation/UIHarness.plist "$bundle/Contents/Info.plist"
xcrun swiftc -parse-as-library -target arm64-apple-macos13.0 -module-cache-path .build/module-cache \
    AppUninstaller/AppUpdateLookup.swift AppUninstaller/AppUpdateInstaller.swift AppUninstaller/BackgroundTaskQueue.swift AppUninstaller/AppUpdaterView.swift \
    Tests/UpdaterValidation/UIStubs.swift Tests/UpdaterValidation/UIHarness.swift \
    -o "$bundle/Contents/MacOS/UpdaterUIValidation"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
printf 'UI fixture: %s\n' "$bundle"
