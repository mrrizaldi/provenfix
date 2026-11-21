#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
PP=$ROOT/scripts/postprocess.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mk() { ffmpeg -hide_banner -loglevel error -y "$@"; }
dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# 6 s of motion, then 4 s frozen
mk -f lavfi -i testsrc=d=6:s=320x240:r=25 -f lavfi -i color=c=gray:d=4:s=320x240:r=25 \
   -filter_complex '[0][1]concat=n=2:v=1' -c:v libvpx -b:v 300k "$T/tail.webm"
out=$("$PP" "$T/tail.webm" "$T/tail.mp4")
assert_eq "tail clip ok" "$?" 0
d=$(dur "$T/tail.mp4")
if awk -v d="$d" 'BEGIN { exit !(d > 6.5 && d < 7.5) }'; then ok "static tail trimmed to ~7 s ($d)"; else not_ok "duration $d, expected ~7"; fi
assert_eq "trim reported" "$(kv "$out" trimmed)" "7.00"
if [ -s "$T/tail.png" ]; then ok "contact sheet written"; else not_ok "no contact sheet"; fi
assert_eq "mp4 is H.264" "$(ffprobe -v error -select_streams v -show_entries stream=codec_name -of csv=p=0 "$T/tail.mp4")" h264

# fully static
mk -f lavfi -i color=c=gray:d=10:s=320x240:r=25 -c:v libvpx -b:v 300k "$T/static.webm"
"$PP" "$T/static.webm" "$T/static.mp4" 2>/dev/null
assert_eq "static clip gated (exit 3)" "$?" 3

# small change on a big static frame: 16 px box blinking every 0.5 s on 390x844 (findings #10)
mk -f lavfi -i color=c=white:s=390x844:r=25:d=4 \
   -vf "drawbox=x=40:y=400:w=16:h=16:color=black:t=fill:enable='lt(mod(t,1),0.5)'" -c:v libvpx -b:v 300k "$T/small.webm"
out=$("$PP" "$T/small.webm" "$T/small.mp4")
assert_eq "small-change clip not gated" "$?" 0
assert_eq "small-change clip not trimmed" "$(kv "$out" trimmed)" ""
assert_eq "mobile size kept" "$(ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$T/small.mp4")" "390,844"

# slideshow: a panel changes every 6 s, nothing moves in between (stage-page proofs: ~97% frozen
# but 7 separate changes). Readable pauses are not a static video.
mk -f lavfi -i color=c=gray:s=160x120:r=5:d=40 \
   -vf "drawbox=x=20:y=20:w=40:h=40:color=black:t=fill:enable='lt(mod(t,12),6)'" -c:v libvpx -b:v 100k "$T/slides.webm"
out=$("$PP" "$T/slides.webm" "$T/slides.mp4" 2>&1)
assert_eq "slideshow with 7 changes not gated" "$?" 0
assert_has "slideshow reports its change count" "$out" "changes=7"

# comma-decimal locale with mawk ("7,00" broke -t); runs only where both exist
loc=$(locale -a 2>/dev/null | grep -iE '^(de_DE|id_ID|fr_FR)\.utf-?8$' | sed -n 1p)
if command -v mawk >/dev/null 2>&1 && [ -n "$loc" ]; then
  mkdir -p "$T/bin"; ln -sf "$(command -v mawk)" "$T/bin/awk"
  out=$(PATH="$T/bin:$PATH" LC_ALL=$loc "$PP" "$T/tail.webm" "$T/loc.mp4" 2>&1)
  assert_eq "comma-decimal locale: trim still 7.00" "$(kv "$out" trimmed)" "7.00"
else
  ok "comma-decimal locale test skipped (needs mawk and a de/id/fr locale)"
fi

"$PP" "$T/missing.webm" "$T/x.mp4" 2>/dev/null
assert_eq "missing input exit 1" "$?" 1
done_testing
