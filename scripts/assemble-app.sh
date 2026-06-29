#!/usr/bin/env bash
# Build the SwiftPM executable and assemble a runnable BabyMonitor.app bundle.
# Phase 0: app binary + Info.plist only. Bundled helpers (bridge, ffmpeg) and
# Developer ID signing are added in later phases (build-helpers.sh / release.sh).
#
#   scripts/assemble-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APPDIR="$ROOT/app"
OUT="$APPDIR/build/BabyMonitor.app"

echo "Building ($CONFIG)..."
swift build --package-path "$APPDIR" -c "$CONFIG" --product BabyMonitor
BIN="$(swift build --package-path "$APPDIR" -c "$CONFIG" --show-bin-path)/BabyMonitor"
[ -x "$BIN" ] || { echo "error: built binary not found at $BIN" >&2; exit 1; }

echo "Assembling $OUT ..."
rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources/Helpers"
cp "$BIN" "$OUT/Contents/MacOS/BabyMonitor"
cp "$APPDIR/Resources/Info.plist" "$OUT/Contents/Info.plist"
printf 'APPL????' > "$OUT/Contents/PkgInfo"

# Ad-hoc sign so it launches locally (Developer ID signing happens in release.sh).
codesign --force --deep --sign - "$OUT" >/dev/null 2>&1 || \
  echo "warning: ad-hoc codesign failed (app may still run)"

echo "Done: $OUT"
