#!/bin/bash
# Both architectures use the same source, resource, and packaging definitions.
set -euo pipefail
cd "$(dirname "$0")"
exec /bin/bash ./build_dual_dmg.sh "$@"
