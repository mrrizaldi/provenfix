#!/usr/bin/env bash
# Turn a Playwright screencast webm into a small mp4 plus a contact sheet (spec step 5).
# postprocess.sh <in.webm> <out.mp4>
# stdout: out= png= duration= trimmed=<seconds or empty> frozen= changes= encoder= bytes=
# exit 3: the video is static (>= 95% without change and < 5 separate changes); re-record instead of shipping it.
set -euo pipefail
export LC_ALL=C  # mawk honours LC_NUMERIC: "7,00" would break -t and fps=
. "$(dirname "$0")/lib.sh"

in=${1:-}
out=${2:-}
if [ ! -f "$in" ] || [ -z "$out" ]; then die "usage: postprocess.sh <in.webm> <out.mp4>"; fi
enc=$(ba_h264) || die "ffmpeg has no H.264 encoder: install a build with libx264 (Fedora: ffmpeg from RPM Fusion; macOS: brew install ffmpeg) or libopenh264"

dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$in")
case $dur in ''|N/A) die "cannot read the duration of $in" ;; esac

# Timestamps of frames that changed (mpdecimate keeps them; 8x8 block compare, findings #10).
changes=$(ffmpeg -hide_banner -nostats -i "$in" -vf mpdecimate,showinfo -an -f null - 2>&1 \
  | grep -oE 'pts_time:[0-9.]+' | cut -d: -f2) || die "ffmpeg could not decode $in"

# frozen = gaps >= 1 s between changes + the tail after the last change if >= 1 s
# events = separate changes (the first frame, then each change after a gap >= 1 s)
read -r frozen last events <<EOF
$(printf '%s\n' "$changes" | awk -v dur="$dur" '
  NR == 1 { prev = $1; events = 1; next }
  { if ($1 - prev >= 1) { frozen += $1 - prev; events++ } prev = $1 }
  END { if (dur - prev >= 1) frozen += dur - prev; printf "%.2f %.2f %d\n", frozen, prev, events }')
EOF
if [ -z "${last:-}" ]; then die "could not analyse motion in $in"; fi

# Static = almost no time with change AND almost no separate changes. A proof that holds each panel
# for a few seconds is ~97% frozen yet has many changes (findings #12, #18); a blank page has one.
if [ "$events" -lt 5 ] && awk -v f="$frozen" -v d="$dur" 'BEGIN { exit !(f >= 0.95 * d) }'; then
  echo "postprocess: $in is static (${frozen}s of ${dur}s without change, $events separate changes)" >&2
  exit 3
fi

end=$(awk -v l="$last" -v d="$dur" 'BEGIN { e = l + 1; if (e > d) e = d; printf "%.2f", e }')
trimmed=
if awk -v e="$end" -v d="$dur" 'BEGIN { exit !(e < d - 0.05) }'; then trimmed=$end; fi

if [ "$enc" = libx264 ]; then q=(-crf 28 -preset veryfast); else q=(-b:v 300k); fi
ffmpeg -hide_banner -loglevel error -y -i "$in" -t "$end" -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2' \
  -c:v "$enc" "${q[@]}" -pix_fmt yuv420p -movflags +faststart -an "$out" || die "encode failed: $out"

png=${out%.mp4}.png
ffmpeg -hide_banner -loglevel error -y -i "$out" -vf "fps=12/$end,scale=320:-2,tile=4x3" -frames:v 1 "$png" \
  || die "contact sheet failed: $png"

echo "out=$out"
echo "png=$png"
echo "duration=$end"
echo "trimmed=$trimmed"
echo "frozen=$frozen"
echo "changes=$events"
echo "encoder=$enc"
echo "bytes=$(wc -c <"$out" | tr -d ' ')"
