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
assert_has "base required" "$out" "--base is required"

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

done_testing
