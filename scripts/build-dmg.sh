#!/bin/bash
# Builds a signed, styled DMG from a built Rankly.app.
# Usage: scripts/build-dmg.sh <path/to/Rankly.app> <output.dmg>
# Requires: brew install create-dmg
set -euo pipefail
APP="$1"; OUT="$2"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Background (1x + 2x combined into one HiDPI TIFF).
swift "$ROOT/scripts/make-dmg-background.swift" "$STAGE" >/dev/null
tiffutil -cathidpicheck "$STAGE/dmg-background.png" "$STAGE/dmg-background@2x.png" -out "$STAGE/background.tiff" >/dev/null

mkdir -p "$STAGE/src"
ditto "$APP" "$STAGE/src/Rankly.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
rm -f "$OUT"

# Layout must match scripts/make-dmg-background.swift (icon centres 170,215 and 490,215).
create-dmg \
  --volname "Rankly $VERSION" \
  --volicon "$APP/Contents/Resources/AppIcon.icns" \
  --background "$STAGE/background.tiff" \
  --window-pos 200 140 \
  --window-size 660 448 \
  --icon-size 104 \
  --text-size 13 \
  --icon "Rankly.app" 170 215 \
  --hide-extension "Rankly.app" \
  --app-drop-link 490 215 \
  --no-internet-enable \
  "$OUT" "$STAGE/src" >/dev/null

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$OUT"
fi
echo "$OUT"
