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
# stub_forge <dir>: fake gh and glab in <dir>/bin. Each call is logged to <dir>/calls and answered
# with the file <dir>/<tool>_<arg1>_<arg2> (non-alphanumerics -> _); no such file = exit 1.
stub_forge() {
  mkdir -p "$1/bin"; : > "$1/calls"
  for t in gh glab; do
    cat > "$1/bin/$t" <<STUB
#!/usr/bin/env bash
echo "$t \$*" >> "$1/calls"
f="$1/\$(printf '%s' "$t \$1 \$2" | tr -c 'A-Za-z0-9' '_')"
[ -f "\$f" ] || { echo "$t stub: no answer for: \$1 \$2" >&2; exit 1; }
cat "\$f"
STUB
    chmod +x "$1/bin/$t"
  done
}
# answer <dir> <tool arg1 arg2> <content>: what the stub prints for that call
answer() { printf '%s\n' "$3" > "$1/$(printf '%s' "$2" | tr -c 'A-Za-z0-9' '_')"; }
