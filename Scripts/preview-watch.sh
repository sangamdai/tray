#!/bin/bash
set -uo pipefail

# Reopen the preview popup whenever a file in Sources/ changes. Ctrl+C to stop.
# Usage: ./Scripts/preview-watch.sh

cd "$(dirname "$0")/.."

stamp=.build/preview-watch-stamp
trap 'pkill -f "\.build/debug/Tray --preview"; exit 0' INT TERM

./Scripts/preview.sh
touch "$stamp"
echo "Watching Sources/ — save a file to reload."

while true; do
    sleep 1
    if [ -n "$(find Sources -name '*.swift' -newer "$stamp" -print -quit)" ]; then
        touch "$stamp"
        echo "$(date +%H:%M:%S) change detected, rebuilding…"
        ./Scripts/preview.sh
    fi
done
