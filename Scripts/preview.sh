#!/bin/bash
set -euo pipefail

# Rebuild and reopen the popup with sample data. Your installed Tray keeps running.
# Usage: ./Scripts/preview.sh [screenshot.png]

cd "$(dirname "$0")/.."

pkill -f "\.build/debug/Tray --preview" 2>/dev/null || true
rm -f .build/preview-window-id

swift build 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" || true
.build/debug/Tray --preview >/dev/null 2>&1 &

for _ in $(seq 1 50); do
    [ -s .build/preview-window-id ] && break
    sleep 0.1
done

if [ -n "${1:-}" ]; then
    sleep 0.3
    screencapture -o -x -l "$(cat .build/preview-window-id)" "$1"
    echo "Screenshot: $1"
fi
