#!/usr/bin/env bash
# Build a throwaway git repo for the counter demo: the bug on main, the fix on fix/counter.
# (A nested .git can't ship inside this repo, so the history is generated.)
# Serve it with: PORT=8000 python3 -m http.server "$PORT"
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
dir=${1:-}
if [ -z "$dir" ]; then echo "usage: make-repo.sh <dir>" >&2; exit 1; fi
if [ -e "$dir" ]; then echo "make-repo: $dir already exists" >&2; exit 1; fi

mkdir -p "$dir"
cd "$dir"
git init -q
git checkout -qb main
git config user.email demo@example.test
git config user.name demo
git config commit.gpgsign false
cp "$src/buggy.html" index.html
git add index.html
git commit -qm "Add counter page"
git checkout -qb fix/counter
cp "$src/fixed.html" index.html
git commit -qam "Fix counter skipping 3"
git checkout -q main
echo "repo=$(pwd)"
