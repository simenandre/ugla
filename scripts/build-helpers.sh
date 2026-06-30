#!/usr/bin/env bash
# Stage the bundled helper binaries the app drives at runtime, into app/helpers/.
# assemble-app.sh copies these into BabyMonitor.app/Contents/Resources/Helpers.
#
#   scripts/build-helpers.sh [--universal]
#
# --universal builds a fat (arm64 + x86_64) bridge for distribution. Without it,
# an arm64-only bridge is built (fine for local Apple Silicon development).
#
# ffmpeg: for local dev we copy whatever ffmpeg is on PATH. For a distributable
# build, drop a *static, universal* ffmpeg at app/helpers/ffmpeg before signing
# (a dynamically-linked ffmpeg will not run on a clean Mac). See README.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/app/helpers"
mkdir -p "$OUT"

echo "Building bridge..."
if [ "${1:-}" = "--universal" ]; then
  ( cd "$ROOT/bridge" && CGO_ENABLED=0 GOARCH=arm64 go build -o "$OUT/.bridge.arm64" . )
  ( cd "$ROOT/bridge" && CGO_ENABLED=0 GOARCH=amd64 go build -o "$OUT/.bridge.amd64" . )
  lipo -create -output "$OUT/avent-webrtc-bridge" "$OUT/.bridge.arm64" "$OUT/.bridge.amd64"
  rm -f "$OUT/.bridge.arm64" "$OUT/.bridge.amd64"
else
  ( cd "$ROOT/bridge" && CGO_ENABLED=0 go build -o "$OUT/avent-webrtc-bridge" . )
fi
echo "  -> $OUT/avent-webrtc-bridge ($(lipo -archs "$OUT/avent-webrtc-bridge" 2>/dev/null || echo native))"

echo "Staging ffmpeg..."
FFMPEG="$(command -v ffmpeg || true)"
if [ -n "$FFMPEG" ]; then
  cp "$FFMPEG" "$OUT/ffmpeg"
  echo "  -> $OUT/ffmpeg (copied from $FFMPEG; dev only — replace with static build for release)"
else
  echo "  !! ffmpeg not found on PATH; place a static universal ffmpeg at $OUT/ffmpeg" >&2
fi

echo "Done."
