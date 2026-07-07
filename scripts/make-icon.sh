#!/usr/bin/env bash
# Render the Ugla owl icon and build app/Resources/AppIcon.icns.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$(mktemp -t ugla-icon).png"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"

echo "Rendering master 1024x1024..."
swift "$ROOT/scripts/make-icon.swift" "$MASTER" >/dev/null

echo "Building iconset..."
for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" \
            "128 128x128" "256 128x128@2x" "256 256x256" "512 256x256@2x" \
            "512 512x512" "1024 512x512@2x"; do
  set -- $spec
  sips -z "$1" "$1" "$MASTER" --out "$SET/icon_$2.png" >/dev/null
done

iconutil -c icns "$SET" -o "$ROOT/app/Resources/AppIcon.icns"
echo "Wrote $ROOT/app/Resources/AppIcon.icns"
rm -f "$MASTER"; rm -rf "$(dirname "$SET")"
