#!/bin/bash
set -euo pipefail

SOURCE="${1:-Resources/AppIcon.png}"
OUTPUT="${2:-Resources/AppIcon.icns}"
ICONSET="$(mktemp -d)/AppIcon.iconset"

mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null 2>&1
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null 2>&1
done

iconutil -c icns "$ICONSET" -o "$OUTPUT"
rm -rf "$(dirname "$ICONSET")"
echo "Generated $OUTPUT"
