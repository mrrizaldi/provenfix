# Data reset

Read this when the scenario changes data (creates, edits or deletes anything), or any DoD row has Proof `data` or `mail`. Both sides share the same services, so without a reset BEFORE's changes leak into AFTER.

## Choosing the target (first run, before the plan screen)

When config has no `reset_target` (the first run, or a later run whose scenario is the first to change data), put the choice on the plan screen (1c, item 4). Don't ask in a separate prompt.

- `sandbox` (recommended): `reset.sh` restores a throwaway copy, e.g. a separate database or container.
- `dev`: it resets the user's own local dev database, losing their local data each phase.

Then:
1. Write `BA/reset.sh` for the recommended choice. Its comment header names exactly what it touches. Rewrite it if the user picks the other.
2. Set `reset: bash BA/reset.sh` in config, and record `reset_target` once the user confirms.
3. Later runs reuse it without asking. Change it only when the user asks.

Never point a reset at a database that is not on this machine (a host other than localhost, 127.0.0.1 or a local container): stop and ask.

## What a reset must also clear

- Test accounts and rows the scenario creates. Name them so `reset.sh` can find and delete them.
- Shared mailboxes when mail is proven (e.g. Mailpit `DELETE /api/v1/messages`).

## When it runs

- Dry-run (step 3): before EACH side's call. BEFORE's data changes must not leak into AFTER's dry-run.
- Record (step 4): reset, BEFORE, reset, AFTER, for every preset. In `both` and `walkthrough` mode, reset again before the WALKTHROUGH phase.

## Plan screen, item 4

Show the reset target (the choice, if not saved yet), what `reset.sh` touches, and the test accounts or rows the scenario will create.
