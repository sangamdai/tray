#!/bin/bash
set -euo pipefail

# Builds Tray.app and zips it for a GitHub release: build/Tray.zip
# Usage: ./Scripts/release.sh

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$PROJECT_DIR/Scripts/build-app.sh"

echo "==> Zipping..."
cd "$PROJECT_DIR/build"
rm -f Tray.zip
ditto -c -k --keepParent Tray.app Tray.zip
echo "==> Done: build/Tray.zip ($(du -h Tray.zip | cut -f1))"
