#!/usr/bin/env bash
# Start one side of a before/after recording and wait until it answers (spec step 2).
# Worktree mode with --ref (cached per sha), checkout mode without.
#
# provision.sh --side before|after --repo <root> [--ref <ref>] [--dir <rel>]
#              [--install <cmd>] --start <cmd> [--port-env PORT] --port <n>
#              [--env K=V]... [--copy <path>]... [--ready <path>] --state <dir>
# stdout: side= url= pid= root=
set -euo pipefail
. "$(dirname "$0")/lib.sh"

side= repo= ref= dir=. install= start= port_env=PORT port= ready=/ state=
envs=() copies=()
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "missing value for $1"
  case $1 in
    --side) side=$2 ;;
    --repo) repo=$2 ;;
    --ref) ref=$2 ;;
    --dir)
      case $2 in ''|/*|./|..|../*|*/..|*/../*) die "--dir must be a relative path inside the repo" ;; esac
      dir=$2 ;;
    --install) install=$2 ;;
    --start) start=$2 ;;
    --port-env) port_env=$2 ;;
    --port) port=$2 ;;
    --env) envs+=("$2") ;;
    --copy)
      case $2 in ''|/*|.|./|..|../*|*/..|*/../*) die "--copy must be a relative path inside the repo" ;; esac
      copies+=("$2") ;;
    --ready) ready=$2 ;;
    --state) state=$2 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift 2
done
case $side in before|after) ;; *) die "--side must be before or after" ;; esac
if [ -z "$repo" ] || [ -z "$start" ] || [ -z "$port" ] || [ -z "$state" ]; then
  die "--repo, --start, --port and --state are required"
fi
case $port in ''|*[!0-9]*) die "--port must be a number" ;; esac
repo=$(cd "$repo" && pwd) || die "no such repo: $repo"
mkdir -p "$state"
state=$(cd "$state" && pwd)

holder() {
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp 2>/dev/null | grep -E ":$port[[:space:]]" || true
  else
    lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  fi
}
rc=0
curl -s --noproxy '*' -o /dev/null --max-time 2 "http://localhost:$port/" || rc=$?
if [ "$rc" != 7 ]; then die "port $port is already in use: $(holder)"; fi

root=$repo
if [ -n "$ref" ]; then
  sha=$(git -C "$repo" rev-parse --verify --quiet "$ref^{commit}") || die "unknown ref: $ref"
  cache=$(ba_cache_dir "$repo")
  root=$cache/$sha
  fresh=
  if [ ! -f "$root.ok" ] || [ ! -d "$root" ]; then
    rm -f "$root.ok"
    if [ -d "$root" ]; then git -C "$repo" worktree remove --force "$root" >/dev/null 2>&1 || rm -rf "$root"; fi
    git -C "$repo" worktree prune
    mkdir -p "$cache"
    msg=$(git -C "$repo" worktree add -q --detach "$root" "$sha" 2>&1) || die "git worktree add failed: $msg"
    fresh=1
  fi
  for f in ${copies[@]+"${copies[@]}"}; do
    if [ ! -e "$repo/$f" ]; then die "--copy source missing: $repo/$f"; fi
    mkdir -p "$(dirname "$root/$f")"
    if [ -d "$repo/$f" ]; then rm -rf "$root/$f"; fi
    cp -R "$repo/$f" "$root/$f"
  done
  if [ -n "$fresh" ]; then
    if [ -n "$install" ]; then
      if ! (cd "$root/$dir" && sh -c "$install") >"$state/$side.install.log" 2>&1; then
        tail -n 30 "$state/$side.install.log" >&2
        die "install failed in $root/$dir (log: $state/$side.install.log)"
      fi
    fi
    touch "$root.ok"
  fi
fi
[ -d "$root/$dir" ] || die "no such dir: $root/$dir"

# Own process group (set -m) so teardown can stop the server and all its children.
log=$state/$side.log
set -m
(
  cd "$root/$dir"
  export "$port_env=$port"
  for kv in ${envs[@]+"${envs[@]}"}; do export "$(printf '%s' "$kv" | sed "s/{port}/$port/g")"; done
  exec nohup sh -c "$start"
) >"$log" 2>&1 </dev/null &
pid=$!
set +m
# pid + start time: teardown refuses a pid that has since been reused
echo "$pid $(ps -o lstart= -p "$pid" || true)" >"$state/$side.pid"

url=http://localhost:$port
secs=${BA_READY_SECS:-180}
SECONDS=0
until curl -s --noproxy '*' -o /dev/null --max-time 2 "$url$ready"; do
  if ! kill -0 -- "-$pid" 2>/dev/null; then
    tail -n 30 "$log" >&2
    die "server exited before it was ready (log: $log); run teardown.sh --state $state"
  fi
  if [ "$SECONDS" -ge "$secs" ]; then
    tail -n 30 "$log" >&2
    kill -TERM -- "-$pid" 2>/dev/null || true
    die "not ready after ${secs}s: $url$ready (log: $log); run teardown.sh --state $state"
  fi
  sleep 1
done
echo "side=$side"
echo "url=$url"
echo "pid=$pid"
echo "root=$root"
