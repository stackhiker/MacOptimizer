#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/updater-validation
xcrun swiftc -module-cache-path .build/module-cache Tests/UpdaterValidation/FixtureExecutable.swift \
    -o .build/updater-validation/fixture-executable
xcrun swiftc -parse-as-library -module-cache-path .build/module-cache \
    AppUninstaller/AppUpdateLookup.swift AppUninstaller/AppUpdateInstaller.swift \
    Tests/UpdaterValidation/main.swift Tests/UpdaterValidation/InstallerChecks.swift \
    -o .build/updater-validation/check
MACOPTIMIZER_FIXTURE_EXECUTABLE="$PWD/.build/updater-validation/fixture-executable" .build/updater-validation/check "$@"
