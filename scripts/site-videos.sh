#!/bin/zsh
# Finishes the website's video lap from its showreel take (scenes/site-lap.yaml):
# search zooms in on the picker as it drops in, to a 1120×700 pt box so its text
# reads on a phone, and back out as it closes; then the lap and each clip are
# encoded for the page, with the feature cards' frames (shot-*.webp). Nothing is
# burned in: the page shows each clip's line and keys beside the video. Prints an
# SSIM seam check of the lap's last frame against its first.
#
#   scripts/showreel record site-lap      # the take (after site-lap-warmup)
#   scripts/site-videos.sh                # → tools/showreel/out/site-videos/
set -eu
repo=${0:A:h:h}
take="$repo/tools/showreel/out/site-lap"
dest="$repo/tools/showreel/out/site-videos"
work="$dest/work"
mkdir -p "$work"
manifest="$take/manifest.json"
master="$take/lap-master.mp4"
[ -f "$master" ] || { echo "no $master — run scripts/showreel record site-lap" >&2; exit 1; }
colors=(-colorspace bt709 -color_primaries bt709 -color_trc iec61966-2-1 -color_range tv)

# A marker's time in the master: from lap-start, less the cut PR search before it.
at() {
  jq -r --arg m "$1" '
    .markers as $k
    | ($k[$m] - $k["lap-start"])
      - (if $k[$m] > $k["pr-results"] - 0.3 then ($k["pr-results"] - 0.3) - $k["pr-searching"] else 0 end)' "$manifest"
}
zoom_in=$(( $(at search-open) + 0.15 ))
zoom_out=$(at search-closing)
themes=$(at themes-start)
windows=$(at windows-start)

# The zoom box: 1120×700 pt (the master is 2 px per point) around the picker, kept on screen.
read px py pw ph <<< "$(jq -r '.windows.picker | if type == "array" then "\(.[0]) \(.[1]) \(.[2]) \(.[3])" else "\(.x) \(.y) \(.width) \(.height)" end' "$manifest")"
cx=$(( (px + pw / 2) * 2 )); cy=$(( (py + ph / 2) * 2 ))
z=$(( 1600.0 / 1120 ))
ease="st(0,clip((on/30-${zoom_in})/0.5,0,1));st(1,clip((on/30-${zoom_out})/0.5,0,1))"
ease+=";1+(${z}-1)*(ld(0)*ld(0)*(3-2*ld(0))-ld(1)*ld(1)*(3-2*ld(1)))"
zoompan="zoompan=z='${ease}':x='clip(${cx}-iw/zoom/2,0,iw-iw/zoom)':y='clip(${cy}-ih/zoom/2,0,ih-ih/zoom)'"
zoompan+=":d=1:s=1600x1000:fps=30"

echo "zoom: in at ${zoom_in}s, out at ${zoom_out}s, around (${cx}, ${cy}) px"
ffmpeg -v error -y -i "$master" -vf "$zoompan,format=yuv420p,setsar=1" \
  -c:v libx264 -preset slow -crf 12 -pix_fmt yuv420p "${colors[@]}" -an "$work/zoomed.mp4"

# The feature cards' frames, from the master at the scene's shot-* markers: the
# picker itself (its window less the 40 pt shadow margin), its footer cropped off
# to the cards' 800×506, and the whole screen for the grid.
m=40
integer sx sy sw sh   # whole pixels for crop
sx=$(( (px + m) * 2 )); sy=$(( (py + m) * 2 )); sw=$(( (pw - 2 * m) * 2 )); sh=$(( sw * 506 / 800 ))
yuv="in_color_matrix=bt709:in_range=tv:flags=lanczos"
shot() {  # shot <name> <filter>
  ffmpeg -v error -y -ss "$(at "shot-$1")" -i "$master" -frames:v 1 -vf "$2,format=rgb24" "$work/shot-$1.png"
  cwebp -quiet -q 84 "$work/shot-$1.png" -o "$dest/shot-$1.webp"
}
for name in tab meeting claude; do
  shot $name "crop=${sw}:${sh}:${sx}:${sy},scale=800:506:${yuv}"
done
shot grid "scale=800:500:${yuv}"

# Each clip at its own pace (the take runs long; the plan's lap is about 52 s), joined
# at the markers, which are continuous footage of the same take.
s1=1.15 s2=1.3 s3=1.3
# Braces throughout: zsh reads `$var:e…` as a modifier and `$var[…]` as a subscript.
graph="[0:v]trim=end=${themes},setpts=(PTS-STARTPTS)/${s1}"; graph+="[a];"
graph+="[0:v]trim=start=${themes}:end=${windows},setpts=(PTS-STARTPTS)/${s2}"; graph+="[b];"
graph+="[0:v]trim=start=${windows},setpts=(PTS-STARTPTS)/${s3}"; graph+="[c];"
graph+="[a][b][c]concat=n=3:v=1:a=0,fps=30"; graph+="[out]"
ffmpeg -v error -y -i "$work/zoomed.mp4" -filter_complex "$graph" -map "[out]" \
  -c:v libx264 -preset slow -crf 12 -pix_fmt yuv420p "${colors[@]}" -an "$work/lap.mp4"
themes=$(( themes / s1 )); windows=$(( themes + (windows - themes * s1) / s2 ))

encode() {  # encode <in> <name> [<from> <to>]
  local in=$1 name=$2 cut=()
  [ $# -ge 4 ] && cut=(-ss "$3" -to "$4")
  ffmpeg -v error -y -i "$in" "${cut[@]}" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p \
    "${colors[@]}" -movflags +faststart -an "$dest/$name.mp4"
  ffmpeg -v error -y -i "$in" "${cut[@]}" -c:v libvpx-vp9 -crf 36 -b:v 0 -row-mt 1 \
    "${colors[@]}" -an "$dest/$name.webm"
}

encode "$work/lap.mp4" lap
ffmpeg -v error -y -i "$work/lap.mp4" -vf "scale=800:-2" -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p \
  "${colors[@]}" -movflags +faststart -an "$dest/lap-800.mp4"
ffmpeg -v error -y -i "$take/lap-poster.png" -q:v 3 "$dest/lap-poster.jpg"

# Each clip on its own, for social posts.
length=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$work/lap.mp4")
encode "$work/lap.mp4" search 0 "$themes"
encode "$work/lap.mp4" themes "$themes" "$windows"
encode "$work/lap.mp4" windows "$windows" "$length"

for f in lap.mp4 lap.webm lap-800.mp4 lap-poster.jpg search.mp4 search.webm themes.mp4 themes.webm windows.mp4 windows.webm \
  shot-tab.webp shot-meeting.webp shot-claude.webp shot-grid.webp; do
  printf '  %-16s %6s KB  %ss\n' "$f" $(( $(stat -f %z "$dest/$f") / 1024 )) \
    "$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dest/$f" 2>/dev/null | cut -c1-5)"
done
printf '  joins: themes at %ss, windows at %ss, lap %ss\n' "$themes" "$windows" "${length:0:5}"

# Seam: the lap's last frame against its first (SSIM ≈ 1.0).
ffmpeg -v error -y -i "$dest/lap.mp4" -frames:v 1 "$work/first.png"
ffmpeg -v error -y -sseof -0.2 -i "$dest/lap.mp4" -update 1 "$work/last.png"
ffmpeg -i "$work/first.png" -i "$work/last.png" -lavfi ssim -f null - 2>&1 | grep -o "All:[0-9.]*" | sed 's/^/  seam SSIM /'
echo "→ $dest"
