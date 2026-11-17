#!/bin/bash
# Redraws the logo and rebuilds Resources/AppIcon.icns and Resources/icon.png.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
swift tools/make_icon.swift "$TMP/icon_1024.png"
for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$TMP/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
sips -z 256 256 "$TMP/icon_1024.png" --out Resources/icon.png >/dev/null
rm -rf "$TMP"
echo "Wrote Resources/AppIcon.icns and Resources/icon.png"
