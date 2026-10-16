#!/usr/bin/env bash
# Keep the original scenario entry point by forwarding all arguments to the generator.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/generate-data.sh" "$@"
