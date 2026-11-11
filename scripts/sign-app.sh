#!/bin/bash
# Re-signs Rankly.app inside-out with Developer ID + hardened runtime (needed for notarization;
# Xcode leaves Sparkle's nested helpers ad-hoc signed).
# Usage: scripts/sign-app.sh <path/to/Rankly.app> ["Developer ID Application: Name (TEAMID)"]
set -euo pipefail
APP="$1"
ID="${2:-Developer ID Application: Arda SENTURK (5JMD3VSD7N)}"
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
ENT="$(mktemp)"; trap 'rm -f "$ENT"' EXIT
codesign -d --entitlements :- "$APP" > "$ENT" 2>/dev/null

sign() { codesign --force --sign "$ID" --options runtime --timestamp "$@"; }
sign "$SP/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SP/XPCServices/Downloader.xpc"
sign "$SP/Autoupdate"
sign "$SP/Updater.app"
sign "$APP/Contents/Frameworks/Sparkle.framework"
sign --entitlements "$ENT" "$APP"
codesign --verify --deep --strict "$APP"
echo "signed: $APP"
