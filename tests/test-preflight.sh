#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
PF=$ROOT/scripts/preflight.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/pw/ffmpeg-1" "$T/empty" "$T/nogit"

out=$(cd "$ROOT" && PLAYWRIGHT_BROWSERS_PATH=$T/pw "$PF" 2>&1)
assert_eq "passes in a git repo with Playwright ffmpeg" "$?" 0
assert_has "reports the encoder" "$out" "encoder=lib"

out=$(cd "$T/nogit" && PLAYWRIGHT_BROWSERS_PATH=$T/empty "$PF" 2>&1)
assert_eq "fails outside git without Playwright ffmpeg" "$?" 1
assert_has "lists the git problem" "$out" "git repository"
assert_has "lists the Playwright ffmpeg problem in the same run" "$out" "install ffmpeg"

out=$(cd "$ROOT/.git" && PLAYWRIGHT_BROWSERS_PATH=$T/pw "$PF" 2>&1)
assert_eq "fails inside .git/ (no work tree)" "$?" 1
done_testing
