#!/usr/bin/env bash
# Stop the servers provision.sh started; optionally prune cached worktrees.
# teardown.sh --state <dir> [--repo <root> [--keep <sha>]...]
# stdout: stopped=<side>  pruned=<sha>
set -euo pipefail
. "$(dirname "$0")/lib.sh"

state= repo= keeps=" "
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "missing value for $1"
  case $1 in
    --state) state=$2 ;;
    --repo) repo=$2 ;;
    --keep) keeps="$keeps$2 " ;;
    *) die "unknown flag: $1" ;;
  esac
  shift 2
done
[ -n "$state" ] || die "--state is required"

for f in "$state"/*.pid; do
  [ -e "$f" ] || continue
  side=$(basename "$f" .pid)
  pid= start=
  read -r pid start <"$f" || true
  case $pid in ''|*[!0-9]*) pid=0 ;; esac
  if [ "$pid" -le 1 ]; then
    rm -f "$f"
    echo "skipped=$side (bad pid)"
    continue
  fi
  if ps -p "$pid" >/dev/null 2>&1 && [ "$(ps -o lstart= -p "$pid")" != "$start" ]; then
    rm -f "$f"
    echo "skipped=$side (pid reused)"
    continue
  fi
  if kill -TERM -- "-$pid" 2>/dev/null; then
    i=0
    while kill -0 -- "-$pid" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    kill -KILL -- "-$pid" 2>/dev/null || true
  fi
  rm -f "$f"
  echo "stopped=$side"
done

if [ -n "$repo" ]; then
  repo=$(cd "$repo" && pwd) || die "no such repo: $repo"
  keep=" "
  for k in $keeps; do keep="$keep$(git -C "$repo" rev-parse --verify -q "$k^{commit}" || echo "$k") "; done
  cache=$(ba_cache_dir "$repo")
  for d in "$cache"/*; do
    [ -d "$d" ] || continue
    sha=$(basename "$d")
    case $keep in *" $sha "*) continue ;; esac
    git -C "$repo" worktree remove --force "$d" >/dev/null 2>&1 || rm -rf "$d"
    rm -f "$d.ok"
    echo "pruned=$sha"
  done
  git -C "$repo" worktree prune
fi
