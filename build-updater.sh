#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
original="${1:?Pass the backed-up original application path}"
bundle="${2:-$PWD/build-updater/Mac优化大师.app}"
mkdir -p "$(dirname "$bundle")" .build/module-cache
ditto "$original" "$bundle"
sources=()
while IFS= read -r -d '' file; do sources+=("$file"); done < <(find AppUninstaller -name '*.swift' -print0)
xcrun swiftc -O -target arm64-apple-macos13.0 -parse-as-library \
    -module-cache-path .build/module-cache \
    -o "$bundle/Contents/MacOS/AppUninstaller" "${sources[@]}"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 3' "$bundle/Contents/Info.plist"
codesign --force --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
printf 'Built: %s\n' "$bundle"
