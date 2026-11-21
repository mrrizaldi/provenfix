#!/usr/bin/env bash
# Check what the pipeline needs; list every missing item at once (spec step 0).
# stdout: preflight=ok git_root= encoder= playwright_cache=
set -euo pipefail
. "$(dirname "$0")/lib.sh"

missing=
need() { missing="$missing
  - $1"; }
enc=

git rev-parse --show-toplevel >/dev/null 2>&1 || need "run inside the project's git repository (a work tree, not .git/)"
for c in git curl ffmpeg ffprobe; do
  command -v "$c" >/dev/null 2>&1 || need "$c not found"
done
if command -v ffmpeg >/dev/null 2>&1; then
  filters=$(ffmpeg -hide_banner -filters 2>/dev/null || true)
  for f in mpdecimate showinfo tile; do
    case $filters in *" $f "*) ;; *) need "ffmpeg lacks the $f filter" ;; esac
  done
  enc=$(ba_h264) || need "ffmpeg has no H.264 encoder: install a build with libx264 (Fedora: ffmpeg from RPM Fusion; macOS: brew install ffmpeg) or libopenh264"
  if [ -n "$enc" ] && ! ffmpeg -hide_banner -loglevel error -f lavfi -i color=s=64x64:d=0.1 -c:v "$enc" -f null - >/dev/null 2>&1; then
    need "ffmpeg lists $enc but cannot encode with it (Fedora: install openh264 from fedora-cisco-openh264, or ffmpeg from RPM Fusion)"
  fi
fi
pw=$(ba_playwright_cache)
if ! ls -d "$pw"/ffmpeg-* >/dev/null 2>&1; then
  need "Playwright's own ffmpeg is missing in $pw. Install it with the playwright version @playwright/mcp uses: npx -y playwright@\$(npm view @playwright/mcp@latest dependencies.playwright) install ffmpeg"
fi

if [ -n "$missing" ]; then
  echo "preflight: missing:$missing" >&2
  exit 1
fi
echo "preflight=ok"
echo "git_root=$(git rev-parse --show-toplevel)"
echo "encoder=$enc"
echo "playwright_cache=$pw"
