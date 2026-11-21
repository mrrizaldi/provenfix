#!/usr/bin/env bash
# examples/notes-api: bug on main, fix on fix/notes-auth, probes and reset work without the MCP.
. "$(dirname "$0")/lib.sh"
X=$ROOT/examples/notes-api
T=$(mktemp -d)
T=$(cd "$T" && pwd)
pid=
cleanup() { if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; fi; rm -rf "$T"; }
trap cleanup EXIT
freeport() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

"$X/make-repo.sh" "$T/repo" >/dev/null
assert_eq "make-repo exits 0" "$?" 0
assert_eq "left on main" "$(git -C "$T/repo" rev-parse --abbrev-ref HEAD)" main
assert_not_has "main has no role check" "$(cat "$T/repo/server.mjs")" "403"
assert_has "fix answers 403" "$(git -C "$T/repo" show fix/notes-auth:server.mjs)" "403"

port=$(freeport)
serve() { # $1 = server file, $2 = side
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; fi
  NOTES_DB=$T/notes.json NOTES_OUTBOX=$T/outbox.log PORT=$port node "$1" >"$T/$2.log" 2>&1 &
  pid=$!
  i=0
  until curl -s --noproxy '*' -o /dev/null --max-time 1 "http://127.0.0.1:$port/"; do
    i=$((i + 1)); [ "$i" -lt 50 ] || break; sleep 0.1
  done
}
probe() { BA_RUN=$T BA_SIDE=$1 BA_PORT=$port bash "$X/probes.sh" "${@:2}"; }
del() { curl -s --noproxy '*' -o /dev/null -w '%{http_code}' -X POST -H 'X-Role: viewer' "http://127.0.0.1:$port/notes/2/delete"; }

bash "$X/reset.sh" "$T"
serve "$T/repo/server.mjs" before
assert_eq "seeded with 2 notes" "$(probe before note_count)" 2
assert_eq "outbox empty after reset" "$(probe before outbox_tail)" "(empty)"
assert_eq "main lets a viewer delete" "$(del)" 200
assert_eq "main: note gone" "$(probe before note_count)" 1
assert_has "main: mail written" "$(probe before outbox_tail)" "deleted by viewer"
assert_eq "main: server log line" "$(probe before log_grep 'deleted note')" 1

git -C "$T/repo" show fix/notes-auth:server.mjs > "$T/fixed.mjs"
bash "$X/reset.sh" "$T"
serve "$T/fixed.mjs" after
assert_eq "fix refuses a viewer" "$(del)" 403
assert_eq "fix: still 2 notes" "$(probe after note_count)" 2
assert_eq "fix: no mail" "$(probe after outbox_tail)" "(empty)"
assert_eq "fix: no delete in its log" "$(probe after log_grep 'deleted note')" 0
done_testing
