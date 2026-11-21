#!/usr/bin/env bash
# Work out which commits are BEFORE and AFTER for a before/after recording (spec step 1a).
#
# resolve.sh --base <branch> [--before <ref>] [--after <ref>]
# resolve.sh [--base <branch>] --mr <n>     MR/PR from origin's forge (gh or glab); its target branch is the base
# stdout: before= after= after_mode=checkout|worktree dirty=
#         rule=merge-base|uncommitted|after-only|explicit|mr-open|mr-closed|mr-merged|mr-squash|mr-ff
#         mr=<n> <open|closed|merged> <url> (with --mr)
#         commit=<short> <subject> (<=20)  file=<path>  warn=<text>
# exit:   0 resolved, 4 ambiguous (candidate=<sha> <subject>), 1 error
set -euo pipefail
. "$(dirname "$0")/lib.sh"

base= before= after= mr=
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "missing value for $1"
  case $1 in
    --base) base=$2 ;;
    --before) before=$2 ;;
    --after) after=$2 ;;
    --mr) mr=$2 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift 2
done
[ -n "$base" ] || [ -n "$mr" ] || die "--base or --mr is required"
[ -z "$mr" ] || [ -z "$before$after" ] || die "--mr replaces --before/--after: give one or the other"
top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not a git work tree"
cd "$top"
X=":(exclude).playwright-mcp"  # the skill's own output dir

commit() { git rev-parse --verify --quiet "$1^{commit}" || die "unknown ref: $1"; }
ambiguous() { git log -15 --format='candidate=%H %s' "$1"; exit 4; }

# --mr: read the MR/PR, fetch its head and target, then continue as if --before/--after were named
mr_rule= mr_line= mr_warn=
if [ -n "$mr" ]; then
  forge=$(ba_forge)
  if [ "$forge" = github ]; then
    info=$(gh pr view "$mr" --json state,baseRefName,headRefOid,mergeCommit,commits,url \
      --jq '"state=\(.state)\nbase=\(.baseRefName)\nhead=\(.headRefOid)\nmerge=\(.mergeCommit.oid // "")\ncount=\(.commits | length)\nurl=\(.url)"' 2>&1) \
      || die "gh pr view $mr failed: $info"
    ref=refs/pull/$mr/head
  else
    json=$(glab api "projects/:id/merge_requests/$mr" 2>&1) || die "glab api merge_requests/$mr failed: $json"
    info=$(printf '%s' "$json" | ba_json '["state=" + j.state, "base=" + j.target_branch, "head=" + j.sha,
      "merge=" + (j.merge_commit_sha || j.squash_commit_sha || ""), "squash=" + (j.squash_commit_sha && !j.merge_commit_sha ? 1 : 0),
      "ff_base=" + ((j.diff_refs || {}).base_sha || ""), "url=" + j.web_url]') || die "unreadable MR JSON for $mr"
    ref=refs/merge-requests/$mr/head
  fi
  get() { printf '%s\n' "$info" | sed -n "s/^$1=//p" | head -1; }
  state=$(get state | tr 'A-Z' 'a-z'); base=$(get base); m=$(get merge)
  case $state in opened|open) state=open ;; merged) ;; *) state=closed ;; esac
  git fetch -q origin "$ref" 2>/dev/null || die "cannot fetch $ref from origin"
  head=$(git rev-parse FETCH_HEAD)
  git fetch -q origin "$base" 2>/dev/null || mr_warn="could not fetch $base from origin: local refs used"
  mr_line="mr=$mr $state $(get url)"
  if [ "$state" != merged ]; then
    after=$head; mr_rule=mr-$state
    [ "$state" = open ] || mr_warn="MR $mr is closed, not merged"
  elif [ -z "$m" ]; then  # fast-forward: no merge or squash commit
    ff=$(get ff_base); [ -n "$ff" ] || { echo "$mr_line"; ambiguous "$head"; }
    before=$ff after=$head mr_rule=mr-ff
  else
    m=$(commit "$m")
    if [ "$(git rev-list --parents -n1 "$m" | wc -w | tr -d ' ')" -gt 2 ]; then
      mr_rule=mr-merged
    elif [ "$(get squash)" = 1 ] || [ "$(get count)" = 1 ]; then
      mr_rule=mr-squash
    else  # GitHub, one parent, several PR commits: squash and rebase look alike
      echo "$mr_line"; ambiguous "$m"
    fi
    before=$m^1 after=$m
  fi
fi

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
echo "rule=${mr_rule:-$rule}"
[ -z "$mr_line" ] || echo "$mr_line"
git log -20 --format='commit=%h %s' "$before..$after"
if [ -n "$files" ]; then printf '%s\n' "$files" | sed 's/^/file=/'; fi

[ -z "$mr_warn" ] || echo "warn=$mr_warn"
if ! git merge-base --is-ancestor "$before" "$after"; then
  echo "warn=BEFORE is not an ancestor of AFTER: the diff may include unrelated changes"
fi
if [ "$mode" = worktree ] && [ "$dirty" != 0 ]; then
  echo "warn=local uncommitted changes are NOT in AFTER ($dirty files)"
fi
if grep -Eiq 'migrat|prisma|alembic|drizzle|\.sql$|(^|/)(db|database)/' <<<"$files"; then
  echo "warn=migration-like files changed: BEFORE runs on AFTER's database schema (shared DB)"
fi
