#!/usr/bin/env bash
# provision.sh + teardown.sh on the counter fixture.
. "$(dirname "$0")/lib.sh"
P=$ROOT/scripts/provision.sh
D=$ROOT/scripts/teardown.sh
T=$(mktemp -d)
export BA_CACHE_DIR=$T/cache BA_READY_SECS=20
extra=
cleanup() { "$D" --state "$T/run" >/dev/null 2>&1; if [ -n "$extra" ]; then kill "$extra" 2>/dev/null; fi; rm -rf "$T"; }
trap cleanup EXIT
freeport() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }
up() { curl -s --noproxy '*' -o /dev/null --max-time 2 "http://localhost:$1/"; }

"$ROOT/examples/counter/make-repo.sh" "$T/repo" >/dev/null
git -C "$T/repo" checkout -q fix/counter
echo "SECRET=1" > "$T/repo/.env"
main=$(git -C "$T/repo" rev-parse main)
pb=$(freeport); pa=$(freeport)
START="python3 '$ROOT/tests/serve.py' \"\$PORT\""
common=(--repo "$T/repo" --start "$START" --state "$T/run" --ready /index.html)

out=$("$P" --side before --ref main --port "$pb" --copy .env --install 'echo x >> installs.txt' "${common[@]}" 2>&1)
assert_eq "before starts" "$?" 0
assert_has "before runs in the cached worktree" "$(kv "$out" root)" "/$main"
assert_has "before serves buggy main" "$(curl -s "http://localhost:$pb/index.html")" "n === 2"
wt=$(kv "$out" root)
assert_eq ".env copied into worktree" "$(cat "$wt/.env")" "SECRET=1"
assert_eq "install ran" "$(wc -l < "$wt/installs.txt" | tr -d ' ')" 1

out=$("$P" --side after --port "$pa" "${common[@]}" 2>&1)
assert_eq "after starts" "$?" 0
assert_eq "after runs in the checkout" "$(kv "$out" root)" "$(cd "$T/repo" && pwd)"
assert_not_has "after serves the fix" "$(curl -s "http://localhost:$pa/index.html")" "n === 2"

out=$("$P" --side after --port "$pa" "${common[@]}" 2>&1)
assert_has "busy port refused" "$out" "port $pa is already in use"

out=$("$D" --state "$T/run")
assert_has "teardown stops before" "$out" "stopped=before"
assert_has "teardown stops after" "$out" "stopped=after"
if up "$pb"; then not_ok "before port still open"; else ok "before port closed"; fi
if up "$pa"; then not_ok "after port still open"; else ok "after port closed"; fi

"$P" --side before --ref main --port "$pb" --install 'echo x >> installs.txt' "${common[@]}" >/dev/null 2>&1
assert_eq "cache hit: install not run again" "$(wc -l < "$wt/installs.txt" | tr -d ' ')" 1
"$D" --state "$T/run" >/dev/null

out=$("$P" --side after --port "$pa" --repo "$T/repo" --start 'exit 3' --state "$T/run" 2>&1)
assert_has "dead server reported" "$out" "server exited before it was ready"

# wrapper that backgrounds the server and exits: the group is still alive
pw=$(freeport)
out=$("$P" --side before --port "$pw" --repo "$T/repo" --start "(sleep 2; exec $START) & exit 0" --state "$T/run" --ready /index.html 2>&1)
assert_eq "backgrounding wrapper is not reported dead" "$?" 0
assert_eq "wrapper server serves" "$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' "http://localhost:$pw/index.html")" 200
"$D" --state "$T/run" >/dev/null
if up "$pw"; then not_ok "wrapper port still open"; else ok "wrapper port closed"; fi

# not ready: fails, keeps the pid file, teardown kills even a TERM-ignoring server
out=$(BA_READY_SECS=3 "$P" --side after --port "$pw" --repo "$T/repo" --start 'trap "" TERM; exec sleep 61' --state "$T/run" 2>&1)
assert_eq "not-ready fails" "$?" 1
assert_has "not-ready message" "$out" "not ready"
if [ -f "$T/run/after.pid" ]; then ok "pid file kept after not-ready"; else not_ok "pid file removed"; fi
read -r gp _ < "$T/run/after.pid"
"$D" --state "$T/run" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do if ! kill -0 -- "-$gp" 2>/dev/null; then break; fi; sleep 0.2; done
if kill -0 -- "-$gp" 2>/dev/null; then not_ok "TERM-ignoring server group $gp still alive"; else ok "teardown stopped the TERM-ignoring server"; fi

# proxy env must not hide a busy port or break readiness
export http_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9
out=$("$P" --side after --port "$pw" --repo "$T/repo" --start "$START" --state "$T/run" --ready /index.html 2>&1)
assert_eq "starts under a proxy env" "$?" 0
out=$("$P" --side before --port "$pw" --repo "$T/repo" --start "$START" --state "$T/run" 2>&1)
assert_has "busy port refused under a proxy env" "$out" "port $pw is already in use"
"$D" --state "$T/run" >/dev/null
unset http_proxy HTTP_PROXY

# stale pid file: a live, unrelated process must survive teardown
set -m; sleep 99 & extra=$!; set +m
echo "$extra bogus start" > "$T/run/before.pid"
out=$("$D" --state "$T/run")
assert_has "reused pid skipped" "$out" "skipped=before"
if kill -0 "$extra" 2>/dev/null; then ok "unrelated process survived"; else not_ok "unrelated process killed"; fi
kill "$extra" 2>/dev/null; extra=
echo "1 x" > "$T/run/before.pid"
out=$("$D" --state "$T/run")
assert_has "pid 1 refused" "$out" "skipped=before (bad pid)"

# --copy / --dir must stay inside the repo
for bad in '' ../x /abs; do
  out=$("$P" --side before --port "$pw" --repo "$T/repo" --start "$START" --state "$T/run" --copy "$bad" 2>&1)
  assert_eq "--copy [$bad] refused" "$?" 1
  assert_has "--copy [$bad] message" "$out" "--copy"
done

# cache hit with the worktree dir gone rebuilds it
rm -rf "$wt"
out=$("$P" --side before --ref main --port "$pb" "${common[@]}" 2>&1)
assert_eq "rebuilds a missing cached worktree" "$?" 0
"$D" --state "$T/run" >/dev/null

# --keep resolves a ref to a sha
out=$("$D" --state "$T/run" --repo "$T/repo" --keep main)
assert_not_has "--keep main keeps main's worktree" "$out" "pruned="

out=$("$D" --state "$T/run" --repo "$T/repo" --keep nothing-to-keep)
assert_has "prune removes the unkept worktree" "$out" "pruned=$main"
if [ -d "$wt" ]; then not_ok "worktree dir still there"; else ok "worktree dir removed"; fi
assert_eq "git forgot the worktree" "$(git -C "$T/repo" worktree list | wc -l | tr -d ' ')" 1

# macOS ps pads "-o lstart=" with trailing spaces (CI evidence): the pid check must still match
mkdir -p "$T/shim"; realps=$(command -v ps)
printf '#!/bin/sh\ncase "$*" in *lstart=*) "%s" "$@" | sed "s/$/    /" ;; *) exec "%s" "$@" ;; esac\n' "$realps" "$realps" > "$T/shim/ps"
chmod +x "$T/shim/ps"
pm=$(freeport)
PATH=$T/shim:$PATH "$P" --side after --port "$pm" "${common[@]}" >/dev/null 2>&1
out=$(PATH=$T/shim:$PATH "$D" --state "$T/run")
assert_has "padded lstart: teardown still stops the server" "$out" "stopped=after"
if up "$pm"; then not_ok "padded lstart: port still open"; else ok "padded lstart: port closed"; fi
done_testing
