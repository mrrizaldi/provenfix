#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
. "$ROOT/scripts/lib.sh"

a=$(BA_CACHE_DIR=/c ba_cache_dir /x/myrepo)
b=$(BA_CACHE_DIR=/c ba_cache_dir /y/myrepo)
assert_has "cache dir sits under BA_CACHE_DIR and is named after the repo" "$a" "/c/myrepo-"
if [ "$a" != "$b" ]; then ok "same name, different path: different cache"; else not_ok "cache collision: $a"; fi
assert_eq "cache dir is stable" "$(BA_CACHE_DIR=/c ba_cache_dir /x/myrepo)" "$a"
assert_eq "trailing slash: same cache" "$(ba_cache_dir "$ROOT/")" "$(ba_cache_dir "$ROOT")"
case $(cd /tmp && BA_CACHE_DIR=rel ba_cache_dir /x/myrepo) in /tmp/rel/myrepo-*) ok "relative BA_CACHE_DIR made absolute" ;; *) not_ok "relative BA_CACHE_DIR not absolute" ;; esac
assert_eq "PLAYWRIGHT_BROWSERS_PATH wins" "$(PLAYWRIGHT_BROWSERS_PATH=/pw ba_playwright_cache)" "/pw"
if enc=$(ba_h264); then ok "H.264 encoder found: $enc"; else not_ok "no H.264 encoder (need ffmpeg with libx264 or libopenh264)"; fi
out=$( (die "boom") 2>&1 )
assert_has "die prints the reason" "$out" "boom"
done_testing
