#!/bin/bash
# Build the web export into web/build/ and stamp the git SHA into the Version autoload.
set -euo pipefail
cd "$(dirname "$0")/.."

SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "Building web export for git $SHA ..."

sed -i.bak "s/const GIT_SHA := \".*\"/const GIT_SHA := \"$SHA\"/" scripts/Version.gd
rm -f scripts/Version.gd.bak

mkdir -p web/build
godot --headless --export-release "Web" web/build/index.html
echo "Done: web/build/"
ls -la web/build/
