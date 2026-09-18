#!/bin/bash
# Reproducible release web export. Thin wrapper around tools/build_web.py.
# Stamp/restore of scripts/Version.gd and output validation live in the
# Python pipeline (see docs/worker-build-pipeline.md).
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tools/build_web.py --engine "${GODOT_BIN:-godot}" "$@"
