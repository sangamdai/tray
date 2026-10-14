#!/bin/bash
set -euo pipefail

# Builds a release Tray.app into build/.
# Signs with the "Tray Development" certificate when it's in the keychain (so macOS
# keeps Tray's Accessibility permission across builds), otherwise ad-hoc.
# Usage: ./Scripts/build-app.sh

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/Tray.app"
SIGNING_IDENTITY="Tray Development"

cd "$PROJECT_DIR"

echo "==> Building release binary..."
swift build -c release
BINARY="$(swift build -c release --show-bin-path)/Tray"

echo "==> Assembling Tray.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/Tray"
cp Sources/App/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "==> Signing..."
if security find-identity -v -p codesigning | grep -q "\"$SIGNING_IDENTITY\""; then
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    echo "    \"$SIGNING_IDENTITY\" not found; signing ad-hoc"
    codesign --force --sign - "$APP_DIR"
fi

echo "==> Done: $APP_DIR ($(du -sh "$APP_DIR" | cut -f1))"
