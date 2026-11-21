# Backend proofs

Read this when any DoD row has Proof `http`, `data`, `mail` or `log`. A UI-only run never needs it.

`examples/notes-api/` in the skill dir is a complete example: a scenario with no UI path, requests, probes and a stage page.

## http: show the real request and response

For UI flows the scenario asserts on UI state, not HTTP status (findings #6). For `http` proofs the status *is* the evidence:

- `ui.request(method, path, { form | json | multipart, headers, expect, maxRedirects, ms })` sends the request and draws a panel from what was really sent and received.
- Redirects are not followed, so a 302 to login stays visible. `expect` colours the panel: green when the status matches, red when not.
- On non-GET it sends `Origin: <app origin>`, as a browser does.
- It returns `{ status, body, url, sent }`. Return observed facts (e.g. `{ status: 403, skipped: true }`) that differ between a broken and a fixed run. Never return `body`, or a secret from it, as a fact: facts go into `summary.md`.

Stack-specific behaviour:
- React Router 7 (`.data` requests): `references/stacks/react-router-7.md`.
- Token in localStorage, sent as `Authorization: Bearer`: `references/stacks/bearer-token.md`.

## data, mail, log: probes

1. Copy `SKILL_DIR/templates/probes.sh` to `BA/<slug>/probes.sh`. Add one `case` branch per check.
   - `# cmd:` = the command text the video shows.
   - `# trigger` on branches that change state (e.g. running a cron job). The plan screen lists them apart.
2. Call `ui.console(name, ...args)` right after the action it proves. The side comes from the label (BEFORE / AFTER / WALKTHROUGH) or `P.side`.

Rules for every branch:
- Probes read. Async effects poll inside the branch for at most 8 s (the server kills a branch at 10 s).
- No credentials on a command line or in `# cmd:`: query the DB inside its container. Never `cat` secret files.
- Nothing in the background: it is killed when the branch exits.
- Never point at a database or host that is not on this machine.

Mail: most apps send mail through an HTTP API or SMTP even in dev. Prove `mail` with the app's dev mail log line (`log_grep`). If the scenario would make the app send real mail, say so on the plan screen (1c, item 4).

Any `data` or `mail` probe makes a reset required, because both sides share services: see `references/reset.md`.

## Probe server (step 2)

When `BA/<slug>/probes.sh` exists, start the probe server after the sides, from the project root (probes run in that directory):

```
SKILL_DIR/scripts/probe.sh --probes BA/<slug>/probes.sh --state BA/run --port <probe_port> --mask-env <login user_env>,<login pass_env>
```

- Pass its `probe_url` and `probe_token` in every run call as `probe: { url, token }`.
- Omit `--mask-env` when config has no `login`.
- Probes need provisioned sides. With `--before-url` / `--after-url` overrides there is no `<side>.log`, and data probes would read local data: don't use data or log probes for an overridden side.
- Teardown stops it (`stopped=probe`).

## No UI path: the stage page

For a webhook, cron job or internal API with nothing to click:
- Pass `stage: '<title>'` (and `stageSub`) in every run call. The harness draws a plain stage page before recording starts, so the raw page never shows. Panels then render centred and larger.
- One chapter per DoD item. `ui.stage(title, sub)` changes the stage text mid-scenario.

## What the panels hide

Masked automatically:
- request/response panels: secret-looking keys in JSON bodies, query strings and `Location`; Bearer and Basic credentials;
- probe output: secret env values and URL credentials.

Not masked: tokens in HTML attributes and URL path segments, so don't show such responses. A `***` where the proof needs a value: assert on a different field.

## Plan screen, item 4

Add to the Data item: `probes.sh` in full, its `# trigger` branches listed apart, and whether the app could send real mail.
