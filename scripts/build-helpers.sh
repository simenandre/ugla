#!/usr/bin/env bash
# Stage the bundled helper binaries the app drives at runtime, into app/helpers/.
# assemble-app.sh copies these into Ugla.app/Contents/Resources/Helpers.
#
#   scripts/build-helpers.sh [--universal]
#
# --universal builds a fat (arm64 + x86_64) bridge for distribution and expects a
# universal, *static* ffmpeg (see ffmpeg sourcing below). Without it, an
# arm64-only bridge is built and the system ffmpeg is copied (local dev only).
#
# ffmpeg sourcing:
#   - Local dev (no flag): copies whatever ffmpeg is on PATH (may be dynamically
#     linked — fine on this machine, NOT for distribution).
#   - Distribution (--universal): set FFMPEG_UNIVERSAL=/path/to/ffmpeg to a
#     self-contained universal static ffmpeg. It is validated to be universal.
#     (A signed/notarized static build can be fetched from e.g.
#     https://ffmpeg.martin-riedl.de — but choosing/trusting a binary to bundle
#     is your call, so this script never downloads one.)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/app/helpers"
mkdir -p "$OUT"
UNIVERSAL="${1:-}"

echo "Building bridge..."
if [ "$UNIVERSAL" = "--universal" ]; then
  ( cd "$ROOT/bridge" && CGO_ENABLED=0 GOARCH=arm64 go build -o "$OUT/.bridge.arm64" . )
  ( cd "$ROOT/bridge" && CGO_ENABLED=0 GOARCH=amd64 go build -o "$OUT/.bridge.amd64" . )
  lipo -create -output "$OUT/avent-webrtc-bridge" "$OUT/.bridge.arm64" "$OUT/.bridge.amd64"
  rm -f "$OUT/.bridge.arm64" "$OUT/.bridge.amd64"
else
  ( cd "$ROOT/bridge" && CGO_ENABLED=0 go build -o "$OUT/avent-webrtc-bridge" . )
fi
echo "  -> $OUT/avent-webrtc-bridge ($(lipo -archs "$OUT/avent-webrtc-bridge"))"

echo "Staging ffmpeg..."
if [ "$UNIVERSAL" = "--universal" ]; then
  [ -n "${FFMPEG_UNIVERSAL:-}" ] || {
    echo "  !! set FFMPEG_UNIVERSAL=/path/to/universal-static-ffmpeg for distribution builds" >&2
    exit 1
  }
  cp "$FFMPEG_UNIVERSAL" "$OUT/ffmpeg"
  archs="$(lipo -archs "$OUT/ffmpeg" 2>/dev/null || echo unknown)"
  case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) : ;;
    *) echo "  !! $FFMPEG_UNIVERSAL is not universal (archs: $archs)" >&2; exit 1 ;;
  esac
  echo "  -> $OUT/ffmpeg ($archs)"
else
  FFMPEG="$(command -v ffmpeg || true)"
  [ -n "$FFMPEG" ] || { echo "  !! ffmpeg not found on PATH" >&2; exit 1; }
  cp "$FFMPEG" "$OUT/ffmpeg"
  echo "  -> $OUT/ffmpeg (dev copy from $FFMPEG; replace with a static build for release)"
fi

echo "Done."
