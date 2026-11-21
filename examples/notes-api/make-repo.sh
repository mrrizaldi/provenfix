#!/usr/bin/env bash
# Build a throwaway git repo for the notes-api demo: the bug on main, the fix on fix/notes-auth.
# Serve it with: NOTES_DB=<dir>/notes.json NOTES_OUTBOX=<dir>/outbox.log PORT=8000 node server.mjs
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
cp "$src/buggy.mjs" server.mjs
git add server.mjs
git commit -qm "Add notes API"
git checkout -qb fix/notes-auth
cp "$src/fixed.mjs" server.mjs
git commit -qam "Only admins may delete notes"
git checkout -q main
echo "repo=$(pwd)"
