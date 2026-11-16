#!/bin/bash
# Keep the original Apple Silicon APP/DMG paths; --arch and --install are optional.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/env python3 -B "$SCRIPT_DIR/scripts/build_package.py" "$@"
