#!/usr/bin/env bash
# resolve.sh against spec step 1a, cases R1-R14 (R11 is agent-side, R15 has no git).
. "$(dirname "$0")/lib.sh"
R=$ROOT/scripts/resolve.sh
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0

c()   { echo "$1" >> f; git add f; git commit -qm "$1"; }
sha() { git rev-parse "$1"; }
run() { out=$("$R" "$@" 2>&1); code=$?; }
newrepo() { # fresh repo with a bare origin and one pushed commit "base" on main
  n=$((n + 1)); mkdir -p "$T/$n"; cd "$T/$n" || exit 1
  git init -q --bare origin.git
  git init -q w; cd w || exit 1
  git config user.email t@example.test; git config user.name t
  git remote add origin ../origin.git
  git checkout -qb main; c base; git push -q origin main
}

echo "# R1 feature branch, committed, clean"
newrepo; base=$(sha HEAD); git checkout -qb feat; c fix
run --base main
assert_eq "R1 exit" "$code" 0
assert_eq "R1 before = merge-base" "$(kv "$out" before)" "$base"
assert_eq "R1 after = HEAD" "$(kv "$out" after)" "$(sha HEAD)"
assert_eq "R1 mode" "$(kv "$out" after_mode)" checkout
assert_eq "R1 rule" "$(kv "$out" rule)" merge-base
assert_has "R1 lists the fix commit" "$out" "commit=$(git rev-parse --short HEAD) fix"
assert_has "R1 lists the changed file" "$out" "file=f"

echo "# R2 feature branch, committed + uncommitted"
newrepo; base=$(sha HEAD); git checkout -qb feat; c fix; echo new > g
run --base main
assert_eq "R2 before" "$(kv "$out" before)" "$base"
assert_eq "R2 mode" "$(kv "$out" after_mode)" checkout
assert_eq "R2 dirty" "$(kv "$out" dirty)" 1
assert_has "R2 lists the untracked file" "$out" "file=g"

echo "# R3 on base, uncommitted only"
newrepo; echo edit >> f
run --base main
assert_eq "R3 exit" "$code" 0
assert_eq "R3 before = HEAD" "$(kv "$out" before)" "$(sha HEAD)"
assert_eq "R3 rule" "$(kv "$out" rule)" uncommitted
assert_eq "R3 dirty" "$(kv "$out" dirty)" 1

echo "# R4 on base, fix committed, not pushed"
newrepo; base=$(sha HEAD); c fix
run --base main
assert_eq "R4 before = origin/main" "$(kv "$out" before)" "$base"
assert_eq "R4 after = HEAD" "$(kv "$out" after)" "$(sha HEAD)"
assert_eq "R4 rule" "$(kv "$out" rule)" merge-base

echo "# R5 on base, fix committed and pushed"
newrepo; c fix; git push -q origin main
run --base main
assert_eq "R5 ambiguous" "$code" 4
assert_has "R5 offers candidates" "$out" "candidate=$(sha HEAD) fix"
run --base main --before HEAD~1 --after HEAD
assert_eq "R5 explicit exit" "$code" 0
assert_eq "R5 explicit before" "$(kv "$out" before)" "$(sha HEAD~1)"
assert_eq "R5 explicit mode (after = clean HEAD)" "$(kv "$out" after_mode)" checkout
assert_eq "R5 explicit rule" "$(kv "$out" rule)" explicit

echo "# R6 open MR, user back on main"
newrepo; base=$(sha HEAD); git checkout -qb feat; c mr
git push -q origin HEAD:refs/merge-requests/1/head
git checkout -q main; git branch -qD feat
git fetch -q origin refs/merge-requests/1/head; head=$(sha FETCH_HEAD)
run --base main --after "$head"
assert_eq "R6 before = merge-base" "$(kv "$out" before)" "$base"
assert_eq "R6 after = MR head" "$(kv "$out" after)" "$head"
assert_eq "R6 mode" "$(kv "$out" after_mode)" worktree
assert_eq "R6 rule" "$(kv "$out" rule)" after-only

echo "# R7 merged MR with a merge commit"
newrepo; base=$(sha HEAD); git checkout -qb feat; c mr; git checkout -q main
git merge -q --no-ff feat -m "Merge feat"; mc=$(sha HEAD); c later
run --base main --before "$mc^1" --after "$mc"
assert_eq "R7 before = mc^1" "$(kv "$out" before)" "$base"
assert_eq "R7 after = mc" "$(kv "$out" after)" "$mc"
assert_eq "R7 mode" "$(kv "$out" after_mode)" worktree

echo "# R8 merged MR, fast-forward"
newrepo; base=$(sha HEAD); git checkout -qb feat; c mr; head=$(sha HEAD)
git checkout -q main; git merge -q --ff-only feat; c later
run --base main --before "$base" --after "$head"
assert_eq "R8 before" "$(kv "$out" before)" "$base"
assert_eq "R8 after" "$(kv "$out" after)" "$head"
assert_eq "R8 mode" "$(kv "$out" after_mode)" worktree

echo "# R9 branch named, remote only"
newrepo; base=$(sha HEAD); git checkout -qb fix/x; c fix; git push -q origin fix/x
git checkout -q main; git branch -qD fix/x
run --base main --after origin/fix/x
assert_eq "R9 before" "$(kv "$out" before)" "$base"
assert_eq "R9 after" "$(kv "$out" after)" "$(sha origin/fix/x)"
assert_eq "R9 mode" "$(kv "$out" after_mode)" worktree

echo "# R10 commit / range named"
newrepo; c a; c b; c later
run --base main --before HEAD~2 --after HEAD~1
assert_eq "R10 before" "$(kv "$out" before)" "$(sha HEAD~2)"
assert_eq "R10 after" "$(kv "$out" after)" "$(sha HEAD~1)"
assert_eq "R10 rule" "$(kv "$out" rule)" explicit
assert_not_has "R10 no ancestry warning" "$out" "not an ancestor"
git checkout -qb x HEAD~2; c x1; git checkout -qb y main; c y1
run --base main --before x --after y
assert_has "R10 diverged refs warn" "$out" "warn=BEFORE is not an ancestor"

echo "# R12 nothing to compare"
newrepo
run --base main
assert_eq "R12 ambiguous" "$code" 4

echo "# R13 named branch + local uncommitted edits"
newrepo; git checkout -qb fix/x; c fix; git checkout -q main; echo dirt >> f
run --base main --after fix/x
assert_eq "R13 mode" "$(kv "$out" after_mode)" worktree
assert_eq "R13 dirty not counted in AFTER" "$(kv "$out" dirty)" 0
assert_has "R13 warns local edits are excluded" "$out" "warn=local uncommitted changes are NOT in AFTER"

echo "# R14 MR targets another branch"
newrepo; git checkout -qb develop; c dev; git push -q origin develop; dev=$(sha HEAD)
git checkout -qb feat; c fix
run --base develop
assert_eq "R14 before = merge-base with develop" "$(kv "$out" before)" "$dev"

echo "# no origin: the local base branch is used"
n=$((n + 1)); mkdir -p "$T/$n/w"; cd "$T/$n/w" || exit 1
git init -q; git config user.email t@example.test; git config user.name t
git checkout -qb main; c base; base=$(sha HEAD); git checkout -qb feat; c fix
run --base main
assert_eq "local base before" "$(kv "$out" before)" "$base"

echo "# migration warning"
newrepo; git checkout -qb feat; mkdir -p db/migrations; echo x > db/migrations/001.sql
git add -A; git commit -qm migration
run --base main
assert_has "migration warn" "$out" "warn=migration-like files changed"

echo "# errors"
newrepo
run --base main --before HEAD --after HEAD
assert_eq "same refs exit 1" "$code" 1
assert_has "same refs message" "$out" "no change between refs"
run --base main --after nope
assert_eq "unknown ref exit 1" "$code" 1
assert_has "unknown ref message" "$out" "unknown ref: nope"
run --after HEAD
assert_has "base required" "$out" "--base or --mr is required"

echo "# working-tree view: .playwright-mcp, config, cwd"
newrepo; mkdir .playwright-mcp; echo log > .playwright-mcp/console.log
run --base main
assert_eq "pw dir ignored: ambiguous, not uncommitted" "$code" 4
newrepo; git config status.showUntrackedFiles no; echo x > new.js
run --base main
assert_eq "untracked rule despite config" "$(kv "$out" rule)" uncommitted
assert_has "untracked file listed despite config" "$out" "file=new.js"
newrepo; mkdir n; echo a > n/a; echo b > n/b
run --base main
assert_eq "untracked folder counts every file" "$(kv "$out" dirty)" 2
newrepo; git checkout -qb feat; mkdir sub; echo s > sub/s; git add sub; git commit -qm sub
echo t > top.txt; echo u > sub/u.txt; cd sub || exit 1
run --base main
assert_has "subdir run lists root untracked" "$out" "file=top.txt"
assert_has "subdir run lists repo-root path" "$out" "file=sub/u.txt"

echo "# rename lists both paths"
newrepo; mkdir -p db/migrations; echo x > db/migrations/001.sql
git add -A; git commit -qm mig; git push -q origin main
git checkout -qb feat; mkdir sql; git mv db/migrations/001.sql sql/001.sql; git commit -qm mv
run --base main
assert_has "rename old path" "$out" "file=db/migrations/001.sql"
assert_has "rename new path" "$out" "file=sql/001.sql"
assert_has "rename migration warn" "$out" "warn=migration-like files changed"

echo "# schema.ts is not a migration"
newrepo; git checkout -qb feat; mkdir -p src/validation; echo x > src/validation/schema.ts
git add -A; git commit -qm schema
run --base main
assert_not_has "no migration warn for schema.ts" "$out" "migration-like"

echo "# explicit before on dirty tree"
newrepo; c two; git push -q origin main; echo dirt >> f
run --base main --before HEAD~1
assert_eq "before-only mode" "$(kv "$out" after_mode)" checkout
assert_eq "before-only rule" "$(kv "$out" rule)" explicit
assert_eq "before-only dirty shown" "$(kv "$out" dirty)" 1
run --base main --before HEAD~1 --after HEAD
assert_eq "explicit after on dirty tree" "$(kv "$out" after_mode)" worktree
assert_has "explicit after warns" "$out" "warn=local uncommitted changes are NOT in AFTER"

echo "# --mr: MR/PR read through stub gh/glab (one per forge)"
S=$T/stub; stub_forge "$S"; PATH=$S/bin:$PATH
gl() { # gl <iid> <state> <target> <head> <merge or null> <squash or null> <diff base>: GitLab MR JSON
  answer "$S" "glab api projects/:id/merge_requests/$1" "{\"iid\":$1,\"state\":\"$2\",\"target_branch\":\"$3\",\"sha\":\"$4\",\"merge_commit_sha\":$5,\"squash_commit_sha\":$6,\"diff_refs\":{\"base_sha\":\"$7\",\"head_sha\":\"$4\"},\"web_url\":\"https://gitlab.example/g/r/-/merge_requests/$1\"}"
}
q() { [ "$1" = null ] && echo null || echo "\"$1\""; }
togithub() { mkdir -p ../github.com; mv ../origin.git ../github.com/r.git; git remote set-url origin ../github.com/r.git; }
ghpr() { # ghpr <n> <state> <base> <head> <merge oid or empty> <commit count>: gh pr view after its --jq
  answer "$S" "gh pr view" "state=$2
base=$3
head=$4
merge=$5
count=$6
url=https://github.com/o/r/pull/$1"
}

echo "# M1 GitLab open MR, user back on main"
newrepo; base=$(sha HEAD); git checkout -qb feat; c mr; head=$(sha HEAD)
git push -q origin HEAD:refs/merge-requests/1/head; git checkout -q main; git branch -qD feat
gl 1 opened main "$head" null null "$base"
run --mr 1
assert_eq "M1 exit" "$code" 0
assert_eq "M1 before = merge-base" "$(kv "$out" before)" "$base"
assert_eq "M1 after = MR head" "$(kv "$out" after)" "$head"
assert_eq "M1 mode" "$(kv "$out" after_mode)" worktree
assert_eq "M1 rule" "$(kv "$out" rule)" mr-open
assert_has "M1 names the MR" "$out" "mr=1 open https://gitlab.example/g/r/-/merge_requests/1"
assert_has "M1 asked glab, not gh" "$(cat "$S/calls")" "glab api projects/:id/merge_requests/1"

echo "# M2 GitLab merged with a merge commit"
newrepo; base=$(sha HEAD); git checkout -qb feat; c mr; head=$(sha HEAD)
git push -q origin HEAD:refs/merge-requests/2/head; git checkout -q main
git merge -q --no-ff feat -m "Merge feat"; mc=$(sha HEAD); c later; git push -q origin main
git reset -q --hard "$base"; git update-ref -d refs/remotes/origin/main
gl 2 merged main "$head" "$(q "$mc")" null "$base"
run --mr 2
assert_eq "M2 exit" "$code" 0
assert_eq "M2 before = mc^1" "$(kv "$out" before)" "$base"
assert_eq "M2 after = mc" "$(kv "$out" after)" "$mc"
assert_eq "M2 rule" "$(kv "$out" rule)" mr-merged

echo "# M3 GitLab merged as a squash commit"
newrepo; base=$(sha HEAD); git checkout -qb feat; c a; c b; head=$(sha HEAD)
git push -q origin HEAD:refs/merge-requests/3/head; git checkout -q main
git merge -q --squash feat; git commit -qm "squashed"; sc=$(sha HEAD); git push -q origin main
gl 3 merged main "$head" null "$(q "$sc")" "$base"
run --mr 3
assert_eq "M3 before = sc^1" "$(kv "$out" before)" "$base"
assert_eq "M3 after = sc" "$(kv "$out" after)" "$sc"
assert_eq "M3 rule" "$(kv "$out" rule)" mr-squash

echo "# M4 GitLab merged fast-forward"
newrepo; base=$(sha HEAD); git checkout -qb feat; c mr; head=$(sha HEAD)
git push -q origin HEAD:refs/merge-requests/4/head; git checkout -q main
git merge -q --ff-only feat; c later; git push -q origin main
gl 4 merged main "$head" null null "$base"
run --mr 4
assert_eq "M4 before = diff_refs.base_sha" "$(kv "$out" before)" "$base"
assert_eq "M4 after = head" "$(kv "$out" after)" "$head"
assert_eq "M4 rule" "$(kv "$out" rule)" mr-ff

echo "# M5 GitHub open PR into develop: its target wins over --base"
newrepo; togithub; git checkout -qb develop; c dev; git push -q origin develop; dev=$(sha HEAD)
git checkout -qb feat; c fix; head=$(sha HEAD); git push -q origin HEAD:refs/pull/5/head
git checkout -q main; git branch -qD feat
ghpr 5 OPEN develop "$head" "" 1
run --base main --mr 5
assert_eq "M5 exit" "$code" 0
assert_eq "M5 before = merge-base with develop" "$(kv "$out" before)" "$dev"
assert_eq "M5 after = PR head" "$(kv "$out" after)" "$head"
assert_eq "M5 rule" "$(kv "$out" rule)" mr-open
assert_has "M5 asked gh" "$(cat "$S/calls")" "gh pr view 5"

echo "# M6 GitHub merged, one-parent commit, several PR commits: squash or rebase? ask"
newrepo; togithub; base=$(sha HEAD); git checkout -qb feat; c a; c b; head=$(sha HEAD)
git push -q origin HEAD:refs/pull/6/head; git checkout -q main
git merge -q --squash feat; git commit -qm "squashed"; sc=$(sha HEAD); git push -q origin main
ghpr 6 MERGED main "$head" "$sc" 2
run --mr 6
assert_eq "M6 ambiguous" "$code" 4
assert_has "M6 offers the merge commit" "$out" "candidate=$sc squashed"

echo "# M7 GitHub merged, one-commit PR"
newrepo; togithub; base=$(sha HEAD); git checkout -qb feat; c one; head=$(sha HEAD)
git push -q origin HEAD:refs/pull/7/head; git checkout -q main
git merge -q --squash feat; git commit -qm "squashed"; sc=$(sha HEAD); git push -q origin main
ghpr 7 MERGED main "$head" "$sc" 1
run --mr 7
assert_eq "M7 before = sc^1" "$(kv "$out" before)" "$base"
assert_eq "M7 after = sc" "$(kv "$out" after)" "$sc"
assert_eq "M7 rule" "$(kv "$out" rule)" mr-squash

echo "# M8 GitHub merged with a merge commit"
newrepo; togithub; base=$(sha HEAD); git checkout -qb feat; c a; c b; head=$(sha HEAD)
git push -q origin HEAD:refs/pull/8/head; git checkout -q main
git merge -q --no-ff feat -m "Merge pull request #8"; mc=$(sha HEAD); git push -q origin main
ghpr 8 MERGED main "$head" "$mc" 2
run --mr 8
assert_eq "M8 before = mc^1" "$(kv "$out" before)" "$base"
assert_eq "M8 rule" "$(kv "$out" rule)" mr-merged

echo "# M9 closed without merging"
newrepo; base=$(sha HEAD); git checkout -qb feat; c mr; head=$(sha HEAD)
git push -q origin HEAD:refs/merge-requests/9/head; git checkout -q main
gl 9 closed main "$head" null null "$base"
run --mr 9
assert_eq "M9 rule" "$(kv "$out" rule)" mr-closed
assert_eq "M9 after = head" "$(kv "$out" after)" "$head"
assert_has "M9 warns" "$out" "warn=MR 9 is closed, not merged"

echo "# M10 --mr errors"
newrepo
run --mr 10 --after HEAD
assert_eq "M10 --mr with --after exit 1" "$code" 1
assert_has "M10 says why" "$out" "--mr replaces --before/--after"
run --mr 404
assert_eq "M10 unreadable MR exit 1" "$code" 1
assert_has "M10 quotes the CLI" "$out" "no answer for: api projects/:id/merge_requests/404"

done_testing
