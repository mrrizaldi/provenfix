#!/usr/bin/env bash
# Reset for the notes-api demo. Touches only <dir>/notes.json and <dir>/outbox.log.
# reset.sh <dir>   (the run's BA/run dir, where config points NOTES_DB and NOTES_OUTBOX)
set -euo pipefail
dir=${1:?usage: reset.sh <dir>}
printf '%s\n' '[{"id":1,"text":"first"},{"id":2,"text":"second"}]' > "$dir/notes.json"
: > "$dir/outbox.log"
