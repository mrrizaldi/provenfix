#!/usr/bin/env bash
# probes for notes-api. Reads: BA_RUN/notes.json, BA_RUN/outbox.log, BA_RUN/<side>.log. Touches: nothing.
set -euo pipefail
case "${1:-}" in
  note_count)   # cmd: grep -o '"id"' notes.json | wc -l
    grep -o '"id"' "$BA_RUN/notes.json" | wc -l | tr -d ' ' ;;
  outbox_tail)  # cmd: tail -n 3 outbox.log
    if [ -s "$BA_RUN/outbox.log" ]; then tail -n 3 "$BA_RUN/outbox.log"; else echo "(empty)"; fi ;;
  log_grep)     # cmd: grep -c "$2" $BA_SIDE.log
    grep -c -- "${2:?pattern}" "$BA_RUN/$BA_SIDE.log" || true ;;
  *) echo "unknown probe: ${1:-}" >&2; exit 2 ;;
esac
