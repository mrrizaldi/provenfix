#!/usr/bin/env bash
# Work out which commits are BEFORE and AFTER for a before/after recording (spec step 1a).
#
# resolve.sh --base <branch> [--before <ref>] [--after <ref>]
# stdout: before= after= after_mode=checkout|worktree dirty= rule=merge-base|uncommitted|after-only|explicit
#         commit=<short> <subject> (<=20)  file=<path>  warn=<text>
# exit:   0 resolved, 4 ambiguous (candidate=<sha> <subject>), 1 error
set -euo pipefail
. "$(dirname "$0")/lib.sh"

base= before= after=
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "missing value for $1"
  case $1 in
    --base) base=$2 ;;
    --before) before=$2 ;;
    --after) after=$2 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift 2
done
[ -n "$base" ] || die "--base is required"
top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not a git work tree"
cd "$top"
X=":(exclude).playwright-mcp"  # the skill's own output dir

commit() { git rev-parse --verify --quiet "$1^{commit}" || die "unknown ref: $1"; }
ambiguous() { git log -15 --format='candidate=%H %s' "$1"; exit 4; }

if git rev-parse --verify --quiet "refs/remotes/origin/$base" >/dev/null; then B=origin/$base; else B=$base; fi
B=$(commit "$B")
head=$(commit HEAD)
dirty=$(git status --porcelain --untracked-files=all -- . "$X" | wc -l | tr -d ' ')
after_given=$after

# AFTER: a named ref, or the checkout (HEAD + uncommitted edits)
if [ -n "$after_given" ]; then
  after=$(commit "$after_given")
  if [ "$after" = "$head" ] && [ "$dirty" = 0 ]; then mode=checkout; else mode=worktree; fi
else
  after=$head
  mode=checkout
fi

# BEFORE: named, else inferred
if [ -n "$before" ]; then
  before=$(commit "$before")
  rule=explicit
elif [ -n "$after_given" ]; then
  before=$(git merge-base "$B" "$after") || die "no common history between $base and $after_given (shallow clone? try: git fetch --unshallow)"
  if [ "$before" = "$after" ]; then ambiguous "$after"; fi
  rule=after-only
else
  mb=$(git merge-base "$B" "$head") || die "no common history between $base and HEAD (shallow clone? try: git fetch --unshallow)"
  if [ "$mb" != "$head" ]; then
    before=$mb; rule=merge-base
  elif [ "$dirty" != 0 ]; then
    before=$head; rule=uncommitted
  else
    ambiguous "$head"
  fi
fi

if [ "$before" = "$after" ]; then
  if [ "$mode" = worktree ] || [ "$dirty" = 0 ]; then die "no change between refs ($before)"; fi
fi

if [ "$mode" = checkout ]; then
  files=$( { git -c core.quotepath=off diff --no-renames --name-only "$before" -- . "$X"; git -c core.quotepath=off ls-files --others --exclude-standard -- . "$X"; } | sort -u )
  shown_dirty=$dirty
else
  files=$(git -c core.quotepath=off diff --no-renames --name-only "$before" "$after")
  shown_dirty=0
fi

echo "before=$before"
echo "after=$after"
echo "after_mode=$mode"
echo "dirty=$shown_dirty"
echo "rule=$rule"
git log -20 --format='commit=%h %s' "$before..$after"
if [ -n "$files" ]; then printf '%s\n' "$files" | sed 's/^/file=/'; fi

if ! git merge-base --is-ancestor "$before" "$after"; then
  echo "warn=BEFORE is not an ancestor of AFTER: the diff may include unrelated changes"
fi
if [ "$mode" = worktree ] && [ "$dirty" != 0 ]; then
  echo "warn=local uncommitted changes are NOT in AFTER ($dirty files)"
fi
if grep -Eiq 'migrat|prisma|alembic|drizzle|\.sql$|(^|/)(db|database)/' <<<"$files"; then
  echo "warn=migration-like files changed: BEFORE runs on AFTER's database schema (shared DB)"
fi
