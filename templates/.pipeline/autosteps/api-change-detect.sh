#!/bin/bash
# Backward-compatible wrapper for the Phase 5 API change detector.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/api-change-detector.sh" "$@"
