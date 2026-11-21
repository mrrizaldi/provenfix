# config.yml

Lives at `<project>/.playwright-mcp/ba/config.yml`. Local only, never committed. Written by the discover step, confirmed by the user.

## Schema

```yaml
base: main                      # required. default branch for merge-base; an MR's target overrides it
services:                       # optional. shared by both sides; checked/started, never stopped
  - name: db
    check: <cmd>                # exit 0 = up
    start: <cmd>                # run once if check fails, then check again
app:                            # required
  dir: .                        # relative to repo root
  install: <cmd>                # run in worktrees only, skipped on cache hit
  start: <cmd>                  # foreground dev server command
  port_env: PORT                # env var the server reads for its port
  ports: { before: 3011, after: 3010 }
  env: { KEY: "value with {port}" }   # {port} is replaced per side
  copy: [.env]                  # gitignored files copied checkout -> worktree on every run
  ready: /                      # path polled until HTTP answers (any status)
viewports: [desktop]            # optional. desktop | tablet | mobile | custom name
presets:                        # optional. custom presets, passed to the harness as `preset` (an object)
  laptop-sm: { width: 1366, height: 768, dpr: 1, mobile: false }
reset: <cmd>                    # optional. runs before every dry-run and record phase
reset_target: sandbox            # set when reset exists. sandbox | dev, the user's answer (SKILL.md 0.5), reused on later runs
probe_port: 47100               # optional. port for scripts/probe.sh when a scenario has probes; discover picks a free one
login:                          # optional. env var NAMES, never values
  path: /login
  user_env: BA_USER
  pass_env: BA_PASS
notes: |                        # optional. discovery findings worth keeping
```

## config -> provision.sh flags

| config | flag |
|---|---|
| `app.dir` | `--dir` |
| `app.install` | `--install` (worktree side only matters) |
| `app.start` | `--start` |
| `app.port_env` | `--port-env` |
| `app.ports.before` / `.after` | `--port` |
| each `app.env` entry | `--env KEY=value` (keep `{port}` literal; provision replaces it) |
| each `app.copy` entry | `--copy <path>` |
| `app.ready` | `--ready` |

Always add `--side`, `--repo <git root>`, `--state <project>/.playwright-mcp/ba/run`, and `--ref <sha>` when resolve says that side is a worktree (BEFORE always is; AFTER when `after_mode=worktree`).

## Example: examples/counter

```yaml
base: main
app:
  dir: .
  start: python3 -m http.server "$PORT"
  port_env: PORT
  ports: { before: 8101, after: 8102 }
  ready: /index.html
viewports: [desktop]
```

## Example: monorepo with a database (shape of a real project)

```yaml
base: main
services:
  - name: db
    check: docker exec demo-db pg_isready -U postgres
    start: docker start demo-db
app:
  dir: apps/app
  install: pnpm install --frozen-lockfile --prefer-offline --ignore-scripts
  start: pnpm dev
  port_env: PORT
  ports: { before: 3011, after: 3010 }
  env: { VITE_APP_URL: "http://localhost:{port}" }
  copy: [apps/app/.env]
  ready: /login
reset: sh .playwright-mcp/ba/reset.sh
reset_target: sandbox
login: { path: /login, user_env: BA_USER, pass_env: BA_PASS }
notes: |
  redis 6379 is held by another project's container; the app runs without it.
  Fresh worktree Vite re-optimizes deps on first load: the dry-run absorbs it.
```

## Example: examples/notes-api (backend proof, stage page)

```yaml
base: main
app:
  dir: .
  start: node server.mjs
  port_env: PORT
  ports: { before: 8111, after: 8112 }
  env: { NOTES_DB: "<abs project>/.playwright-mcp/ba/run/notes.json", NOTES_OUTBOX: "<abs project>/.playwright-mcp/ba/run/outbox.log" }
  ready: /
reset: bash .playwright-mcp/ba/reset.sh .playwright-mcp/ba/run
reset_target: sandbox
probe_port: 47100
viewports: [desktop]
```
