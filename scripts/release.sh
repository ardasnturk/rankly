#!/bin/bash
# Builds, signs, notarizes and packages a Rankly release, then adds it to the Sparkle appcast.
#
#   scripts/release.sh            # uses MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml
#
# Prerequisites (one time):
#   brew install xcodegen create-dmg
#   xcrun notarytool store-credentials "rankly-notary" --apple-id <id> --team-id 5JMD3VSD7N
#   Sparkle EdDSA key in the login keychain under account "rankly" (generate_keys --account rankly)
#
# Afterwards: commit docs/appcast.xml, push, then
#   gh release create v<version> dist/Rankly.dmg --title "Rankly <version>" --notes-file <notes>
# (the appcast points at releases/download/v<version>/Rankly.dmg, so publish the release before
#  the appcast goes live on GitHub Pages).
set -euo pipefail
cd "$(dirname "$0")/.."
NOTARY_PROFILE="${NOTARY_PROFILE:-rankly-notary}"
SPARKLE_BIN="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
APP="build/Build/Products/Release/Rankly.app"
DMG="dist/Rankly.dmg"

echo "▸ Generating project"
xcodegen generate -q

echo "▸ Building universal Release"
xcodebuild -project Rankly.xcodeproj -scheme Rankly -configuration Release -derivedDataPath build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build -quiet

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
echo "  version $VERSION ($BUILD)"

echo "▸ Signing (Developer ID, hardened runtime)"
scripts/sign-app.sh "$APP" >/dev/null

echo "▸ Building DMG"
mkdir -p dist
SIGN_IDENTITY="Developer ID Application: Arda SENTURK (5JMD3VSD7N)" scripts/build-dmg.sh "$APP" "$DMG" >/dev/null

echo "▸ Notarizing (this takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature "$DMG"

echo "▸ Signing update for Sparkle and updating docs/appcast.xml"
SIG=$("$SPARKLE_BIN/sign_update" --account rankly "$DMG")
python3 - "$VERSION" "$BUILD" "$SIG" <<'PY'
import sys, re, email.utils
version, build, sig = sys.argv[1:4]
path = "docs/appcast.xml"
xml = open(path).read()
# Drop an existing item for the same version (re-release), keep older ones.
xml = re.sub(r'\s*<item>(?:(?!</item>).)*<sparkle:shortVersionString>%s</sparkle:shortVersionString>.*?</item>' % re.escape(version),
             '', xml, flags=re.S)
item = f'''
    <item>
      <title>Rankly {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/ardasnturk/rankly/releases/tag/v{version}</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/ardasnturk/rankly/releases/download/v{version}/Rankly.dmg" {sig} type="application/octet-stream"/>
    </item>'''
xml = xml.replace("<language>en</language>", "<language>en</language>" + item, 1)
open(path, "w").write(xml)
PY
xmllint --noout docs/appcast.xml
echo "✓ $DMG ready (v$VERSION). Next: commit docs/appcast.xml, tag v$VERSION and create the GitHub release."
