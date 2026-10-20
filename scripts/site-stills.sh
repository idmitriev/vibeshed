#!/bin/zsh
# Finishes the website's stills from their showreel takes
# (scenes/site-picker-themes.yaml and scenes/site-theme-montage.yaml): converts
# them to sRGB, writes WebP beside each PNG or JPEG for <picture>, and lays the
# six theme screens out as the montage, three across and two down, sized for
# the page's 1160 px band at 2×.
#
#   scripts/showreel record site-picker-themes site-theme-montage
#   scripts/site-stills.sh                # → showreel/out/site-stills/
set -eu
repo=${0:A:h:h}
out="$repo/showreel/out"
dest="$out/site-stills"
work="$dest/work"
mkdir -p "$work"
srgb="/System/Library/ColorSync/Profiles/sRGB Profile.icc"
themes=(vibeshed-glow tokyo-night catppuccin-latte dracula mac-os-9 amiga-workbench-1-3)

# Into sRGB, untagged, as browsers assume for images without a profile.
tosrgb() { magick "$1" -profile "$srgb" -strip "$2"; }   # tosrgb <in> <out>

# The picker: alone on transparency (PNG and WebP, alpha kept exactly), and on
# its theme's wallpaper (JPEG and WebP). All at the capture's 2×.
for f in "$out"/site-picker-themes/picker-*.png; do
  name=${f:t:r}
  if [[ $name == *-desktop ]]; then
    tosrgb "$f" "$work/$name.png"
    magick "$work/$name.png" -quality 86 -sampling-factor 4:2:0 "$dest/$name.jpg"
    cwebp -quiet -q 84 "$work/$name.png" -o "$dest/$name.webp"
  else
    tosrgb "$f" "$dest/$name.png"
    cwebp -quiet -q 90 -alpha_q 100 -exact "$dest/$name.png" -o "$dest/$name.webp"
  fi
done

# Each theme's screen at 1600 px, and a tile of it with rounded corners.
tiles=()
for t in "${themes[@]}"; do
  tosrgb "$out/site-theme-montage/montage-${t}.png" "$work/screen-${t}.png"
  magick "$work/screen-${t}.png" -resize 1600x -quality 86 -sampling-factor 4:2:0 "$dest/theme-${t}.jpg"
  cwebp -quiet -q 84 -resize 1600 0 "$work/screen-${t}.png" -o "$dest/theme-${t}.webp"
  magick "$work/screen-${t}.png" -resize 760x475 \
    \( -size 760x475 xc:none -fill white -draw "roundrectangle 0,0 759,474 12,12" \) \
    -compose DstIn -composite "$work/tile-${t}.png"
  tiles+=("$work/tile-${t}.png")
done

# The montage: 24 px between tiles (12 around each, shaved off the outside).
magick montage "${tiles[@]}" -tile 3x2 -geometry 760x475+12+12 -background none "$work/montage-padded.png"
magick "$work/montage-padded.png" -shave 12x12 "$dest/montage.png"
cwebp -quiet -q 86 -alpha_q 100 "$dest/montage.png" -o "$dest/montage.webp"

for f in "$dest"/*.(png|jpg|webp); do
  printf '  %-36s %5s KB  %s\n' "${f:t}" $(( $(stat -f %z "$f") / 1024 )) \
    "$(magick identify -format '%wx%h' "$f" 2>/dev/null)"
done
echo "→ $dest"
