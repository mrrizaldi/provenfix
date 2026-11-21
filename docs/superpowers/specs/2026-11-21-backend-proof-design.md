# provenfix: backend proof (spec)

Date: 2026-11-21. Decision: D20 in `docs/design.md`. Extends the main spec `2026-11-20-before-after-design.md`; everything not named here stays as it is.

## Goal

Prove backend Definition-of-Done items in the same BEFORE/AFTER videos: HTTP behaviour, data side effects and out-of-band effects (mail, logs, jobs). Recording stays Playwright screencast only. Evidence shown on camera is always built from what was actually sent, received or printed, never a hand-written label (lesson of a private testbed run).

## Scope

**In:** a `Proof` column in `dod.md`; harness helpers `ui.request`, `ui.console`, `ui.stage`; `scripts/probe-server.mjs`; `templates/probes.sh`; a stage-page video for tickets with no UI path; a transcript block in `summary.md`; the public fixture `examples/notes-api/`.

**Out:** fail-to-pass test runs (not picked by the user; add when a ticket's DoD is "tests exist" and a video can't show it), Playwright `trace.zip` (carries cookies and tokens), terminal recorders (VHS, asciinema: break D1), Hurl or any new dependency, a no-video API mode.

## DoD: proof kinds

`dod.md`'s understanding table gains a column:

```markdown
| # | Criterion | Proof | BEFORE should show | AFTER should show |
|---|---|---|---|---|
| 1 | Wrong role can't delete a note | http | `← 200`, note gone | `← 403 Forbidden` |
| 2 | ... and nothing changes | data | `note_count` 2 → 1 | `note_count` stays 2 |
```

| Proof | On camera | Comes from |
|---|---|---|
| `ui` | page state (current behaviour) | DOM assertion |
| `http` | request panel | `ui.request` |
| `data` · `mail` · `log` | console panel | `ui.console` → probe |
| `none` | not shown; listed under "Not shown in video" | none |

Every item other than `none` maps to at least one returned fact that the dry-run gate checks.

## Harness helpers (`templates/harness.js`)

All three go on the existing `ui` object, return facts, and never reject on overlay errors (same rule as `banner`).

- `ui.request(method, path, { form | json | multipart, headers } = {})` sends through `page.request` (shares the page's cookies, so it acts as the user signed in on camera) against `P.base + path`. Non-GET requests carry `Origin: <app origin>` by default, as a browser would (`page.request` sends none, and Origin/CSRF checks are common: about 1 in 8 surveyed projects 403 without it); `opts.headers` can override it. Bearer-token apps keep the token in localStorage: the scenario reads it with `page.evaluate` and passes `Authorization` in `headers` (never shown). `multipart` fields show as `name=<file: filename>`. Shows a panel for about 4 s:
  ```
  -> POST /notes/2/delete
     X-Role: viewer
  <- 403 Forbidden
    {"error":"forbidden"}
  ```
  The method, the path as sent (including suffixes like `.data`), the request headers (not secret ones, not Origin), the encoded body, the status and a body excerpt (first 600 chars) come from the real request and response. Never shown: `Authorization`, `Cookie`, `Set-Cookie` and other secret-named headers. Body fields named like `password|secret|token` render as `***`. Panel is red when `opts.expect` is given and the status differs from it, green when it matches, grey without `expect`. Returns `{ status, body, url, sent }`. Redirects are not followed unless `opts.maxRedirects` is set, so a "redirected to login" proof shows the `302` and its `Location`. `opts.ms` changes how long the panel stays (default 4200).
- `ui.console(name, ...args)` calls `GET {P.probe.url}/{name}?a=<arg>&a=<arg>` with header `X-Probe-Token: {P.probe.token}` through `page.request`. Shows a terminal-styled panel: `$ <cmd line the server reports>` (`$1`..`$9`, `$BA_SIDE`, `$BA_PORT` in a `# cmd:` comment are replaced by the real values) then stdout. Returns `{ code, out }`. Throws when `P.probe` is missing (a scenario with probes was run without a probe server).
- `P.stage` (run param, plus optional `P.stageSub`) draws the stage page before recording starts, so the raw page never shows; on the stage page panels render centred and larger. `ui.stage(title)` replaces the page content with a plain dark canvas showing `title`, for tickets with no UI path. Panels and chapters render on it as usual. The URL pill shows the side's base URL.
- Every panel's text is also kept in order; the harness returns it as `transcript` (array of strings) next to the scenario's facts, and the agent writes it into `summary.md`.

## Probe server (`scripts/probe-server.mjs`)

Node stdlib only (node is always present: Playwright MCP runs through `npx`).

```
SKILL_DIR/scripts/probe.sh --probes BA/<slug>/probes.sh --state BA/run --port <probe_port> [--mask-env BA_USER,BA_PASS]
```

`probe.sh` generates the token, starts `probe-server.mjs` in its own process group (like `provision.sh`), writes `BA/run/probe.pid` in the format `teardown.sh` already reads, waits until the server answers, and prints `probe_url=` and `probe_token=`.

- The agent reads `probe_url` and `probe_token` and passes them as `P.probe = { url, token }` in each run call. One server serves both sides: `ui.console` sends query params `side` (`before` or `after`, from `P.label`; `WALKTHROUGH` maps to `after`, the server it runs on) and `port` (from `P.base`); the server rejects any other side value or a non-numeric port with `400`.
- Binds `127.0.0.1` only. Missing or wrong token → `401`.
- Name must match `^[a-z_]+$`, else `400`. Runs `spawn('bash', [probes, name, ...args], { shell: false })` with env `BA_SIDE`, `BA_PORT` (from the query) and `BA_RUN` (from `--run`). A name with no `<name>)` branch in `probes.sh` → `404` without running anything (exit codes pass through untouched: `grep` exits 2 on errors). The token is removed from the probe's env.
- Kills a probe after 10 s (`124` in the response). Caps stdout+stderr at 4 KB with a `...[cut]` marker.
- Masks secrets in all output as `***` (rules tuned on a survey of ~40 local projects):
  - every env var named in `--mask-env` (values of 4+ chars);
  - every env var whose name has a secret part (`TOKEN SECRET PASSWORD PASS PWD KEY APIKEY COOKIE DSN CREDENTIALS PRIVATE`, split on `_`, so `VALKEY_HOST` is not a key) and no public part (`ID PUBLIC ANON SITE TTL EXPIRY EXPIRES MIN LENGTH ENABLED ALLOW PATH FILE`, so `AWS_ACCESS_KEY_ID`, `SUPABASE_ANON_KEY`, `JWT_TOKEN_EXPIRY_MINUTES` stay visible), when the value has 6+ chars, is not a boolean, number or path, and is not also held by a plain env var (dev setups often use the DB user name as password; masking it would blank user and DB names in every probe);
  - the password part of any URL (`scheme://user:***@`), so a printed `DATABASE_URL` never leaks.
- Response: JSON `{ code, out, cmd }`; `cmd` is the probe's first `# cmd:` comment in its case branch, else `probes.sh <name> <args>`.
- Stopped by `teardown.sh` unchanged: it stops every `BA/run/*.pid` and prints `stopped=probe`.

## Probes file (`templates/probes.sh`)

Copied to `BA/<slug>/probes.sh` and filled in per scenario.

```bash
#!/usr/bin/env bash
# probes for <slug>. Reads: <what>. Touches: <what, or "nothing">.
# Never points at a database or host that is not on this machine.
set -euo pipefail
case "${1:-}" in
  note_count)   # cmd: node -p "require('./data/notes.json').length"
    node -p "require('./data/notes.json').length" ;;
  outbox_tail)  # cmd: tail -n 3 outbox.log  (polls up to 8 s for a new line)
    ... ;;
  log_grep)     # cmd: grep -c "$2" BA/run/$BA_SIDE.log
    grep -c -- "${2:?pattern}" "$BA_RUN/$BA_SIDE.log" || true ;;
  run_cron)     # trigger  cmd: node jobs/cleanup.js
    ... ;;
  *) echo "unknown probe: ${1:-}" >&2; exit 2 ;;
esac
```

- A `# trigger` tag marks probes that change state. The plan screen lists trigger probes separately.
- Probes that wait for async effects poll inside the branch, at most 8 s.
- Probes never put credentials on a command line or in `# cmd:` (query the DB inside its container: `docker compose exec -T <svc> sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "..."'`, so the variables expand inside the container), never `cat` secret files (`*_FILE`, key files), and run nothing in the background (the server kills a probe's process group when it exits).
- Mail: surveyed apps send through an HTTP API (Postmark, Resend) or SMTP even in dev, not to a local catcher, and some dev setups really deliver to a redirect address. So `mail` is usually proven by the app's own dev mail log line (`log_grep`), or a local catcher when the app is wired to one. When the scenario would make the app send real mail, the plan screen says so.
- Same locality rule as `reset.sh`: a probe that would reach a non-local database or host stops the run and the agent asks.

## SKILL.md changes

- **1 Context:** `dod.md` template gets the `Proof` column.
- **1b Scenario:** pick a proof kind per DoD item. `http` → `ui.request`; `data`/`mail`/`log` → write `BA/<slug>/probes.sh` from the template and use `ui.console`. No UI path at all → start the scenario with `ui.stage(title)` and one chapter per DoD item.
- **1c Plan screen:** item 4 (Data) also shows `probes.sh` in full and lists trigger probes. Any `data` or `mail` probe makes a reset required; the 0.5 reset-target choice applies, and the reset also clears shared mailboxes (e.g. Mailpit `DELETE /api/v1/messages`).
- **2 Provision:** after the sides, start the probe server when `probes.sh` exists.
- **3 Dry-run gate:** probe and request facts are judged against `dod.md` like UI facts.
- **5 Teardown:** stops the probe server.
- **6 Report:** `summary.md` gets per side a `<details><summary>BEFORE evidence</summary>` block with every request panel's text and every console's `$ cmd` + output, in order.
- **Config:** top-level `probe_port` (discover picks a free one, e.g. from 47100).

## Testing

- `tests/test-probe.sh` (in `run-all.sh`; CI ubuntu + macOS bash 3.2): allowed probe returns stdout and code; unknown name → 404; bad name → 400; no or wrong token → 401; arg `;$(touch x)` echoed literally and `x` not created; 10 s timeout → 124; output over 4 KB cut; masking (named, secret-part, public-part, numeric, reused-value and URL-credential cases); binds 127.0.0.1 only.
- `examples/notes-api/` (no deps): `server.mjs` (node stdlib), JSON file as DB, `outbox.log` as mail. `main`: `POST /notes/:id/delete` has no role check and writes a "deleted" line to the outbox. `fix/notes-auth`: `403` for role `viewer`, nothing written. `make-repo.sh` like counter. `flow.js` runs on `ui.stage`, uses `ui.request` and `ui.console` (`note_count`, `outbox_tail`, `log_grep`). Covers `http` + `data` + `mail` + `log` and the stage page in one manual e2e run.
- The harness helpers run only inside the MCP, so the fixture's dry-run gate is their test (as today).
- Real-world check before release: the private testbed re-run uses `ui.request` and a `user_role` probe instead of the hand-written panels; compare with the earlier hand-made videos.

## Done when

- `bash tests/run-all.sh` passes on ubuntu and macOS CI.
- The notes-api fixture records BEFORE and AFTER: BEFORE shows `← 200`, `note_count` dropping and an outbox line; AFTER shows `← 403`, the count unchanged and no outbox line; the gate passes; both contact sheets show panels, not a blank stage.
- `summary.md` holds the evidence blocks for both sides with no secret values.
- The private testbed re-run passes the gate with probe-backed panels only.
