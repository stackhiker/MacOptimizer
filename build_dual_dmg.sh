#!/bin/bash
# Both architectures share the verified packaging and cleanup implementation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/env python3 -B "$SCRIPT_DIR/scripts/build_package.py" --arch both "$@"
