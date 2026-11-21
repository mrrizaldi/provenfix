# Assert helpers for tests/test-*.sh. Source it, then call done_testing at the end.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fail=0
ok()     { echo "ok   - $1"; }
not_ok() { echo "FAIL - $1"; fail=1; }
assert_eq()      { if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1: expected [$3], got [$2]"; fi; }
assert_has()     { case "$2" in *"$3"*) ok "$1" ;; *) not_ok "$1: [$3] not found in: $2" ;; esac; }
assert_not_has() { case "$2" in *"$3"*) not_ok "$1: [$3] unexpectedly found" ;; *) ok "$1" ;; esac; }
# kv <output> <key>: value of the first key=value line
kv() { printf '%s\n' "$1" | awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }'; }
done_testing() { if [ "$fail" = 0 ]; then echo "# all passed"; else echo "# FAILED"; exit 1; fi; }
