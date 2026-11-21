#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
M=$ROOT/examples/counter/make-repo.sh

"$M" "$T/repo" >/dev/null
assert_eq "make-repo exits 0" "$?" 0
assert_eq "left on main" "$(git -C "$T/repo" rev-parse --abbrev-ref HEAD)" main
assert_has "main has the bug" "$(cat "$T/repo/index.html")" "n === 2"
assert_not_has "fix/counter has no bug" "$(git -C "$T/repo" show fix/counter:index.html)" "n === 2"
assert_eq "fix is one commit ahead" "$(git -C "$T/repo" rev-list --count main..fix/counter)" 1
"$M" "$T/repo" >/dev/null 2>&1
assert_eq "refuses an existing dir" "$?" 1
done_testing
