#!/usr/bin/env bash
# Build a distributable BabyMonitor.app + DMG locally: arm64, bundled signed
# helpers, Hardened Runtime, notarized + stapled. (Universal builds need full
# Xcode and are produced by .github/workflows/release.yml instead.)
#
#   # Full signed + notarized release (Apple Silicon):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="babymonitor" \
#   FFMPEG_STATIC=/path/to/static-ffmpeg \
#   scripts/release.sh 1.0.0
#
#   # Local mechanics check (ad-hoc, no notarize):
#   FFMPEG_STATIC=/path/to/static-ffmpeg scripts/release.sh 1.0.0
#
# Prereqs for a real release: a "Developer ID Application" identity + a notarytool
# keychain profile (scripts/setup-codesigning.sh), and a self-contained static
# ffmpeg you trust (FFMPEG_STATIC).
set -euo pipefail

VERSION="${1:?usage: release.sh <version>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPDIR="$ROOT/app"
DIST="$ROOT/dist"
APP="$DIST/BabyMonitor.app"
DMG="$DIST/BabyMonitor-$VERSION.dmg"
IDENTITY="${SIGN_IDENTITY:--}"
: "${FFMPEG_STATIC:?set FFMPEG_STATIC to a self-contained static ffmpeg}"

rm -rf "$DIST"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Helpers"

echo "==> Building app ($VERSION, $(uname -m))"
swift build --package-path "$APPDIR" -c release --product BabyMonitor
BIN="$(swift build --package-path "$APPDIR" -c release --show-bin-path)/BabyMonitor"
cp "$BIN" "$APP/Contents/MacOS/BabyMonitor"

echo "==> Info.plist"
sed "s#0.1.0#$VERSION#" "$APPDIR/Resources/Info.plist" > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Helpers (bridge built static; ffmpeg from FFMPEG_STATIC)"
( cd "$ROOT/bridge" && CGO_ENABLED=0 go build -o "$APP/Contents/Resources/Helpers/avent-webrtc-bridge" . )
cp "$FFMPEG_STATIC" "$APP/Contents/Resources/Helpers/ffmpeg"
chmod +x "$APP/Contents/Resources/Helpers/"*

echo "==> Codesign (identity: $IDENTITY)"
if [ "$IDENTITY" = "-" ]; then SIGN=(--force --sign -); else SIGN=(--force --options runtime --timestamp --sign "$IDENTITY"); fi
codesign "${SIGN[@]}" "$APP/Contents/Resources/Helpers/avent-webrtc-bridge"
codesign "${SIGN[@]}" "$APP/Contents/Resources/Helpers/ffmpeg"
codesign "${SIGN[@]}" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> DMG"
STAGE="$DIST/stage"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Baby Monitor" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

if [ "$IDENTITY" = "-" ]; then echo "==> Ad-hoc DMG (not notarized): $DMG"; exit 0; fi

echo "==> Notarize + staple"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE (a notarytool keychain profile)}"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
echo "==> Release ready: $DMG"
