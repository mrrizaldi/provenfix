#!/usr/bin/env bash
# probes for <slug>. Reads: <what>. Touches: <what, or "nothing">. Select counts or non-secret columns only.
# Run by scripts/probe-server.mjs as: bash probes.sh <name> <args...>, never through a shell.
# Env: BA_SIDE (before|after), BA_PORT (that side's app port), BA_RUN (BA/run: <side>.log lives there).
# One branch per probe. "# cmd: <text>" is what the video shows after "$ ": $1..$9 (bash positionals:
# $1 = probe name, $2.. = args), $BA_SIDE and $BA_PORT are replaced by their real values. Tag state-changing
# probes "# trigger". Async effects: poll inside the branch, at most 8 s (the server kills at 10 s).
# No credentials on a command line or in "# cmd:" (query inside the DB container instead), never cat
# secret files, nothing in the background (it is killed when the branch exits).
# Never point at a database or host that is not on this machine.
set -euo pipefail
case "${1:-}" in
  log_grep)     # cmd: grep -c "$2" $BA_SIDE.log
    grep -c -- "${2:?pattern}" "$BA_RUN/$BA_SIDE.log" || true ;;
  # Shapes that worked on real projects (copy, adapt, delete the rest):
  # row_count)  # cmd: select count(*) from <table>
  #   docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "select count(*) from <table>"' ;;
  # sqlite_rows) # cmd: sqlite3 <file> 'select ...'
  #   sqlite3 <file> 'select count(*) from <table>' ;;
  # queue_wait) # cmd: redis-cli LLEN bull:<queue>:wait
  #   docker compose exec -T redis redis-cli LLEN 'bull:<queue>:wait' ;;
  # mail_sent)  # cmd: grep -c "<mail log marker>" $BA_SIDE.log   (most apps log mail in dev instead of using a catcher)
  #   grep -c -- '<mail log marker>' "$BA_RUN/$BA_SIDE.log" || true ;;
  *) echo "unknown probe: ${1:-}" >&2; exit 2 ;;
esac
