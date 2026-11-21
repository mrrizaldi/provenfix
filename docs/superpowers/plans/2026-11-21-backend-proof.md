# Backend Proof Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove backend DoD items (HTTP, data, mail, log) inside the BEFORE/AFTER videos, from real requests and real command output.

**Architecture:** The harness gains `ui.request` (panel from a real `page.request` round trip), `ui.console` (panel from a named probe's real stdout) and `ui.stage` (blank canvas for tickets with no UI). Probes are `case` branches in `BA/<slug>/probes.sh`, run by a node-stdlib server on 127.0.0.1 (`scripts/probe-server.mjs`), started by `scripts/probe.sh` in its own process group so the existing `teardown.sh` stops it unchanged. A public fixture `examples/notes-api/` exercises all of it.

**Tech Stack:** bash (3.2-compatible, D15), node stdlib (ESM, node 18+), Playwright MCP screencast API.

Spec: `docs/superpowers/specs/2026-11-21-backend-proof-design.md`. Decision: D20 in `docs/design.md`.

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `docs/superpowers/specs/2026-11-21-backend-proof-design.md` | modify | align spec with the plan's start/stop and 404 rules |
| `scripts/probe-server.mjs` | create | HTTP server: token, name check, spawn without shell, kill, cap, mask |
| `scripts/probe.sh` | create | start the server in its own process group, write `probe.pid`, print url + token |
| `tests/test-probe.sh` | create | behaviour of probe.sh + probe-server.mjs + teardown |
| `templates/probes.sh` | create | probe file template |
| `templates/harness.js` | modify | `ui.request`, `ui.console`, `ui.stage`, transcript |
| `templates/flow.js` | modify | header lists the new helpers |
| `tests/test-template.sh` | modify | parse/ASCII/assert the new helpers and the fixture flow |
| `examples/notes-api/{buggy.mjs,fixed.mjs,make-repo.sh,reset.sh,probes.sh,flow.js}` | create | fixture |
| `tests/test-notes-api.sh` | create | fixture bug, fix, probes, reset |
| `tests/test-portability.sh` | modify | scan `examples/*/*.sh` |
| `SKILL.md`, `references/config.md`, `README.md` | modify | pipeline, config, docs |

---

### Task 1: Align the spec with the plan

Three details changed while planning: `teardown.sh` stops pid files written as `<pid> <lstart>` of a process-group leader, so a bash wrapper must start the server (as `provision.sh` does); a probe exit code 2 is ambiguous (`grep` errors exit 2), so unknown names are rejected by scanning `probes.sh` before running; and auth proofs need redirects shown, not followed.

**Files:**
- Modify: `docs/superpowers/specs/2026-11-21-backend-proof-design.md`

- [ ] **Step 1: Replace the probe server start block**

Replace:
````
```
node SKILL_DIR/scripts/probe-server.mjs --probes BA/<slug>/probes.sh --run BA/run \
  --port <ports.probe> [--mask-env BA_USER,BA_PASS]
```
````
with:
````
```
SKILL_DIR/scripts/probe.sh --probes BA/<slug>/probes.sh --state BA/run --port <probe_port> [--mask-env BA_USER,BA_PASS]
```

`probe.sh` generates the token, starts `probe-server.mjs` in its own process group (like `provision.sh`), writes `BA/run/probe.pid` in the format `teardown.sh` already reads, waits until the server answers, and prints `probe_url=` and `probe_token=`.
````

- [ ] **Step 2: Fix the sentence that follows**

Replace `- Prints \`probe_url=http://127.0.0.1:<port>\` and \`probe_token=<32 hex>\` on stdout once listening, writes its pid to \`<run>/probe.pid\`, then stays in the foreground. The agent starts it in the background, reads the two lines, and passes them as \`P.probe\` in each run call.` with `- The agent reads \`probe_url\` and \`probe_token\` and passes them as \`P.probe = { url, token }\` in each run call.`

- [ ] **Step 3: Fix the unknown-name rule**

Replace `Exit 2 from the \`*)\` branch → \`404\`.` with `A name with no \`<name>)\` branch in \`probes.sh\` → \`404\` without running anything (exit codes pass through untouched: \`grep\` exits 2 on errors). The token is removed from the probe's env.`

- [ ] **Step 4: Redirects and transcript in `ui.request`**

After `Returns \`{ status, body, url, sent }\`.` add: ` Redirects are not followed unless \`opts.maxRedirects\` is set, so a "redirected to login" proof shows the \`302\` and its \`Location\`. \`opts.ms\` changes how long the panel stays (default 4200).`

After the `ui.stage` bullet add: `- Every panel's text is also kept in order; the harness returns it as \`transcript\` (array of strings) next to the scenario's facts, and the agent writes it into \`summary.md\`.`

- [ ] **Step 5: Teardown line and config key**

Replace `- Stopped by \`teardown.sh\`, which kills \`BA/run/probe.pid\` when present.` with `- Stopped by \`teardown.sh\` unchanged: it stops every \`BA/run/*.pid\` and prints \`stopped=probe\`.` Replace `- **Config:** \`ports.probe\` (default: first free port from 47100).` with `- **Config:** top-level \`probe_port\` (discover picks a free one, e.g. from 47100).`

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-11-21-backend-proof-design.md
git commit -m "docs: align backend-proof spec with plan"
```

---

### Task 2: Probe server and starter

**Files:**
- Create: `tests/test-probe.sh`
- Create: `scripts/probe-server.mjs`
- Create: `scripts/probe.sh`

- [ ] **Step 1: Write the failing test**

`tests/test-probe.sh`:

```bash
#!/usr/bin/env bash
# probe.sh + probe-server.mjs + teardown.sh (spec: backend proof).
. "$(dirname "$0")/lib.sh"
S=$ROOT/scripts/probe.sh
D=$ROOT/scripts/teardown.sh
T=$(mktemp -d)
T=$(cd "$T" && pwd)
cleanup() { "$D" --state "$T/run" >/dev/null 2>&1; rm -rf "$T"; }
trap cleanup EXIT
freeport() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

cat > "$T/probes.sh" <<'EOF'
case "${1:-}" in
  echo_args) # cmd: printf '%s|' "$@"
    shift; printf '%s|' "$@" ;;
  env_info) echo "$BA_SIDE $BA_PORT $BA_RUN token=${BA_PROBE_TOKEN:-unset}" ;;
  fail) echo oops >&2; exit 3 ;;
  big) head -c 10000 /dev/zero | tr '\0' x ;;
  slow) sleep 30 ;;
  *) exit 2 ;;
esac
EOF

export BA_PROBE_KILL_MS=1500
pp=$(freeport)
out=$("$S" --probes "$T/probes.sh" --state "$T/run" --port "$pp" 2>&1)
assert_eq "probe.sh starts" "$?" 0
url=$(kv "$out" probe_url)
tok=$(kv "$out" probe_token)
assert_eq "url is loopback" "$url" "http://127.0.0.1:$pp"
assert_eq "token is 32 hex" "$(printf '%s' "$tok" | grep -cE '^[0-9a-f]{32}$')" 1
assert_has "pid file written" "$(cat "$T/run/probe.pid")" " "
assert_has "binds loopback only" "$(cat "$ROOT/scripts/probe-server.mjs")" "listen(Number(opt.port), '127.0.0.1')"

code() { curl -s --noproxy '*' -o /dev/null -w '%{http_code}' "$@"; }
q() { curl -s --noproxy '*' -H "X-Probe-Token: $tok" "$url/$1"; }
assert_eq "no token is 401" "$(code "$url/echo_args?side=before&port=1")" 401
assert_eq "wrong token is 401" "$(code -H 'X-Probe-Token: nope' "$url/echo_args?side=before&port=1")" 401
assert_eq "bad name is 400" "$(code -H "X-Probe-Token: $tok" "$url/Bad-Name?side=before&port=1")" 400
assert_eq "unknown name is 404" "$(code -H "X-Probe-Token: $tok" "$url/nope?side=before&port=1")" 404
assert_eq "bad side is 400" "$(code -H "X-Probe-Token: $tok" "$url/echo_args?side=prod&port=1")" 400
assert_eq "bad port is 400" "$(code -H "X-Probe-Token: $tok" "$url/echo_args?side=before&port=x")" 400

r=$(q "echo_args?side=before&port=1&a=1&a=two%20words")
assert_has "args arrive as argv" "$r" '"out":"1|two words|"'
assert_has "exit code returned" "$r" '"code":0'
assert_has "cmd comment shown" "$r" '"cmd":"printf'

enc=$(node -p 'encodeURIComponent(process.argv[1])' ";\$(touch $T/pwned)")
r=$(q "echo_args?side=before&port=1&a=$enc")
assert_has "shell syntax comes back literally" "$r" 'touch'
assert_eq "shell syntax not run" "$([ -e "$T/pwned" ] && echo yes || echo no)" no

r=$(q "env_info?side=after&port=4242")
assert_has "probe env: side, port, run dir" "$r" "after 4242 $T/run"
assert_has "token not passed to probes" "$r" "token=unset"

r=$(q "fail?side=before&port=1")
assert_has "non-zero exit passes through" "$r" '"code":3'
assert_has "stderr captured" "$r" 'oops'

r=$(q "big?side=before&port=1")
assert_has "big output cut" "$r" '...[cut]'
assert_eq "cut near 4 KB" "$([ ${#r} -lt 4300 ] && echo yes || echo no)" yes

SECONDS=0
r=$(q "slow?side=before&port=1")
assert_has "slow probe killed with 124" "$r" '"code":124'
assert_eq "killed within the limit" "$([ "$SECONDS" -lt 6 ] && echo yes || echo no)" yes

out=$("$S" --probes "$T/probes.sh" --state "$T/run2" --port "$pp" 2>&1)
assert_has "busy port refused" "$out" "port $pp is already in use"
out=$("$S" --probes "$T/missing.sh" --state "$T/run2" --port "$(freeport)" 2>&1)
assert_has "missing probes file refused" "$out" "no such probes file"

out=$("$D" --state "$T/run")
assert_has "teardown stops the probe server" "$out" "stopped=probe"
assert_eq "server gone after teardown" "$(code --max-time 2 "$url/")" 000
done_testing
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-probe.sh`
Expected: FAIL lines, starting with `FAIL - probe.sh starts` (script missing).

- [ ] **Step 3: Write `scripts/probe-server.mjs`**

```js
// provenfix probe server (spec: docs/superpowers/specs/2026-11-21-backend-proof-design.md).
// Start it with probe.sh, not directly. It binds 127.0.0.1, needs BA_PROBE_TOKEN, and runs only
// named branches of the probes file, as argv without a shell.
import http from 'node:http';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';

const opt = {};
for (let i = 2; i < process.argv.length; i += 2) opt[process.argv[i].replace(/^--/, '')] = process.argv[i + 1] ?? '';
const token = process.env.BA_PROBE_TOKEN;
if (!opt.probes || !opt.run || !opt.port || !token) {
  console.error('probe-server: --probes, --run, --port and BA_PROBE_TOKEN are required');
  process.exit(1);
}
const LIMIT = 4096;
const KILL_MS = Number(process.env.BA_PROBE_KILL_MS) || 10000;
const maskNames = (opt['mask-env'] || '').split(',').filter(Boolean);
const mask = (text) => text;

const childEnv = { ...process.env };
delete childEnv.BA_PROBE_TOKEN;

const server = http.createServer((req, res) => {
  const send = (code, body) => {
    res.writeHead(code, { 'content-type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  if (req.headers['x-probe-token'] !== token) return send(401, { error: 'bad or missing X-Probe-Token' });
  const u = new URL(req.url, 'http://127.0.0.1');
  const name = u.pathname.slice(1);
  const side = u.searchParams.get('side');
  const port = u.searchParams.get('port') || '';
  if (!/^[a-z_]+$/.test(name)) return send(400, { error: 'probe name must match ^[a-z_]+$' });
  if (side !== 'before' && side !== 'after') return send(400, { error: 'side must be before or after' });
  if (!/^\d+$/.test(port)) return send(400, { error: 'port must be a number' });

  let src;
  try { src = readFileSync(opt.probes, 'utf8'); } catch (e) { return send(500, { error: `cannot read ${opt.probes}: ${e.message}` }); }
  if (!new RegExp(`^\\s*${name}\\)`, 'm').test(src)) return send(404, { error: `no probe named ${name}` });
  const args = u.searchParams.getAll('a');
  const cmdLine = src.match(new RegExp(`^\\s*${name}\\).*?cmd:\\s*(.+)$`, 'm'));
  const cmd = cmdLine ? cmdLine[1].trim() : ['probes.sh', name, ...args].join(' ');

  // detached: own process group, so a kill also reaches the probe's children (sleep, curl, psql)
  const child = spawn('bash', [opt.probes, name, ...args], {
    env: { ...childEnv, BA_SIDE: side, BA_PORT: port, BA_RUN: opt.run },
    stdio: ['ignore', 'pipe', 'pipe'],
    detached: true,
  });
  let out = '';
  const take = (d) => { if (out.length <= LIMIT) out += d; };
  child.stdout.on('data', take);
  child.stderr.on('data', take);
  let killed = false;
  const timer = setTimeout(() => {
    killed = true;
    try { process.kill(-child.pid, 'SIGKILL'); } catch { /* already gone */ }
  }, KILL_MS);
  child.on('close', (code) => {
    clearTimeout(timer);
    const cut = out.length > LIMIT;
    out = mask(cut ? out.slice(0, LIMIT) : out) + (cut ? '\n...[cut]' : '');
    send(200, { code: killed ? 124 : code, out, cmd: mask(cmd) });
  });
});
server.on('error', (e) => { console.error(`probe-server: ${e.message}`); process.exit(1); });
server.listen(Number(opt.port), '127.0.0.1');
```

- [ ] **Step 4: Write `scripts/probe.sh`**

```bash
#!/usr/bin/env bash
# Start the probe server for one run (spec: backend proof). teardown.sh stops it (probe.pid).
# probe.sh --probes <file> --state <dir> --port <n> [--mask-env A,B]
# stdout: probe_url= probe_token=
set -euo pipefail
. "$(dirname "$0")/lib.sh"
here=$(cd "$(dirname "$0")" && pwd)

probes= state= port= mask=
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || die "missing value for $1"
  case $1 in
    --probes) probes=$2 ;;
    --state) state=$2 ;;
    --port) port=$2 ;;
    --mask-env) mask=$2 ;;
    *) die "unknown flag: $1" ;;
  esac
  shift 2
done
if [ -z "$probes" ] || [ -z "$state" ] || [ -z "$port" ]; then die "--probes, --state and --port are required"; fi
case $port in *[!0-9]*) die "--port must be a number" ;; esac
[ -f "$probes" ] || die "no such probes file: $probes"
command -v node >/dev/null 2>&1 || die "node not found"
url=http://127.0.0.1:$port
if curl -s --noproxy '*' -o /dev/null --max-time 1 "$url/"; then die "port $port is already in use"; fi

probes=$(cd "$(dirname "$probes")" && pwd)/$(basename "$probes")
mkdir -p "$state"
state=$(cd "$state" && pwd)
token=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')

# Own process group (set -m), same as provision.sh, so teardown.sh stops it unchanged.
set -m
(
  export BA_PROBE_TOKEN=$token
  exec nohup node "$here/probe-server.mjs" --probes "$probes" --run "$state" --port "$port" --mask-env "$mask"
) >"$state/probe.log" 2>&1 </dev/null &
pid=$!
set +m
echo "$pid $(ps -o lstart= -p "$pid" || true)" >"$state/probe.pid"

i=0
until [ "$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 1 "$url/" || true)" = 401 ]; do
  if ! kill -0 "$pid" 2>/dev/null; then
    tail -n 20 "$state/probe.log" >&2
    die "probe server exited (log: $state/probe.log)"
  fi
  if [ "$i" -ge 50 ]; then die "probe server not answering on $url (log: $state/probe.log)"; fi
  sleep 0.2
  i=$((i + 1))
done
echo "probe_url=$url"
echo "probe_token=$token"
```

Run: `chmod +x scripts/probe.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `bash tests/test-probe.sh`
Expected: every line `ok`, last line `# all passed`.

- [ ] **Step 6: Run the whole suite (portability scans `scripts/*.sh`)**

Run: `bash tests/run-all.sh`
Expected: exit 0, no `FAIL` lines.

- [ ] **Step 7: Commit**

```bash
git add scripts/probe-server.mjs scripts/probe.sh tests/test-probe.sh
git commit -m "feat: add probe server for backend proof"
```

---

### Task 3: Secret masking (written by the user)

The rule decides what can leak into a published video, so the user writes it. The tests below are the contract; the reference version is the fallback.

**Files:**
- Modify: `tests/test-probe.sh`
- Modify: `scripts/probe-server.mjs` (the `const mask = (text) => text;` line)

- [ ] **Step 1: Add the failing test**

In `tests/test-probe.sh`, add a probe branch inside the heredoc, before `*) exit 2 ;;`:

```bash
  leak) echo "pw=$BA_PASS key=$MY_API_KEY short=$MY_TOKEN plain=$PLAIN_VAR" ;;
```

Change the start line to pass mask names and secrets in env:

```bash
export BA_PASS=hunter22 MY_API_KEY=abcd1234 MY_TOKEN=abc PLAIN_VAR=visible1
out=$("$S" --probes "$T/probes.sh" --state "$T/run" --port "$pp" --mask-env BA_PASS 2>&1)
```

Add after the `fail` assertions:

```bash
r=$(q "leak?side=before&port=1")
assert_not_has "--mask-env value masked" "$r" "hunter22"
assert_not_has "*KEY* env value masked" "$r" "abcd1234"
assert_has "masked values show ***" "$r" "pw=*** key=***"
assert_has "values under 4 chars left alone" "$r" "short=abc"
assert_has "other env values left alone" "$r" "plain=visible1"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-probe.sh`
Expected: `FAIL - --mask-env value masked`, `FAIL - *KEY* env value masked`, `FAIL - masked values show ***`.

- [ ] **Step 3: Implement `mask` (user contribution)**

Replace `const mask = (text) => text;` in `scripts/probe-server.mjs`. Trade-offs: a wider name pattern hides more (safer for a public video) but can hide the fact you are trying to show; matching values longer-first avoids a short secret masking half of a longer one. Reference:

```js
// Values of named env vars and of any *TOKEN*/*SECRET*/*PASSWORD*/*KEY*/*COOKIE* var become ***.
// Under 4 chars is skipped: masking "1" or "on" would wreck ordinary output.
const SECRET_NAME = /TOKEN|SECRET|PASSWORD|KEY|COOKIE/i;
const secrets = Object.entries(process.env)
  .filter(([k, v]) => v && v.length >= 4 && (maskNames.includes(k) || SECRET_NAME.test(k)))
  .map(([, v]) => v)
  .sort((a, b) => b.length - a.length);
const mask = (text) => secrets.reduce((t, v) => t.split(v).join('***'), text);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-probe.sh`
Expected: `# all passed`.

- [ ] **Step 5: Commit**

```bash
git add scripts/probe-server.mjs tests/test-probe.sh
git commit -m "feat: mask secret env values in probe output"
```

---

### Task 4: Harness helpers and probes template

**Files:**
- Modify: `tests/test-template.sh`
- Modify: `templates/harness.js:70-96`
- Modify: `templates/flow.js:4-9`
- Create: `templates/probes.sh`

- [ ] **Step 1: Add failing asserts**

In `tests/test-template.sh`, after the `pgrep marker` assert, add:

```bash
assert_has "request panel helper" "$h" "request: async (method, path, opts = {})"
assert_has "requests show redirects instead of following them" "$h" "maxRedirects: opts.maxRedirects ?? 0"
assert_has "non-GET requests carry the app Origin like a browser" "$h" "Origin: new URL(P.base).origin"
assert_has "multipart supported" "$h" "o.multipart = opts.multipart"
assert_has "secret-looking body fields hidden" "$h" "SECRET_FIELD.test(k) ? '***'"
assert_has "console helper sends the probe token" "$h" "'X-Probe-Token': P.probe.token"
assert_has "console refuses without a probe server" "$h" "ui.console needs P.probe"
assert_has "stage helper" "$h" "stage: async (title, sub = '')"
assert_has "panels feed the transcript" "$h" "transcript.push(text)"
p=$(cat "$ROOT/templates/probes.sh")
assert_has "probes template rejects unknown names" "$p" 'exit 2'
assert_has "probes template states what it touches" "$p" "Touches:"
if bash -n "$ROOT/templates/probes.sh"; then ok "probes template parses"; else not_ok "probes template has a syntax error"; fi
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-template.sh`
Expected: `FAIL - request panel helper` and the other new asserts fail.

- [ ] **Step 3: Add the helpers to `templates/harness.js`**

Replace:

```js
      const ACTIONS = { position: 'top-right', duration: 700 };
      const ui = {
```

with:

```js
      const ACTIONS = { position: 'top-right', duration: 700 };
      // Request and console panels (spec: backend proof). Text comes only from what was really sent,
      // received or printed; it is escaped here, kept in `transcript` for summary.md, and held on
      // screen for ms so the viewer can read it.
      const transcript = [];
      const SECRET_FIELD = /pass|secret|token/i;
      const panel = async (text, color, ms) => {
        transcript.push(text);
        await page.screencast.showOverlay(`<pre style="position:fixed;right:16px;bottom:56px;max-width:min(760px,92vw);max-height:62vh;overflow:hidden;margin:0;padding:12px 16px;border-radius:10px;border-left:6px solid ${color};background:rgba(12,12,12,.93);color:#e5e5e5;font:13px/1.45 ui-monospace,monospace;white-space:pre-wrap;word-break:break-all;box-shadow:0 4px 16px rgba(0,0,0,.35)">${esc(text)}</pre>`, { duration: ms }).catch(() => {});
        await page.waitForTimeout(ms + 200);
      };
      const ui = {
```

Then, inside the `ui` object, after the `banner:` entry (the line ending `// never reject: an un-awaited banner must not crash the MCP`), add:

```js
        // Sends through page.request (the page's cookies: acts as the user signed in on camera).
        // opts: { form } | { json } | { multipart }, headers, expect (status: green when it matches, red when not),
        // maxRedirects, ms. Non-GET gets the app's Origin like a browser would (Origin/CSRF checks are common).
        // Bearer apps: read the token with page.evaluate and pass headers.Authorization; headers are never shown.
        request: async (method, path, opts = {}) => {
          const origin = /^(GET|HEAD)$/i.test(method) ? {} : { Origin: new URL(P.base).origin };
          const o = { method, headers: { ...origin, ...opts.headers }, failOnStatusCode: false, maxRedirects: opts.maxRedirects ?? 0 };
          let sent = '';
          if (opts.multipart) {
            o.multipart = opts.multipart;
            sent = Object.entries(opts.multipart).map(([k, v]) => `${k}=${v && typeof v === 'object' ? `<file: ${v.name || 'blob'}>` : SECRET_FIELD.test(k) ? '***' : v}`).join('&');
          } else if (opts.form) {
            o.form = opts.form;
            sent = new URLSearchParams(Object.entries(opts.form).map(([k, v]) => [k, SECRET_FIELD.test(k) ? '***' : String(v)])).toString();
          } else if (opts.json !== undefined) {
            o.data = opts.json;
            sent = JSON.stringify(opts.json, (k, v) => (k && SECRET_FIELD.test(k) ? '***' : v));
          }
          const r = await page.request.fetch(P.base.replace(/\/+$/, '') + path, o);
          const body = await r.text();
          const u = new URL(r.url());
          const loc = r.headers().location;
          const text = `-> ${method} ${u.pathname}${u.search}${sent ? `\n   ${sent}` : ''}\n<- ${r.status()} ${r.statusText()}${loc ? `  Location: ${loc}` : ''}${body ? `\n   ${body.slice(0, 600)}${body.length > 600 ? ' ...' : ''}` : ''}`;
          const match = opts.expect === undefined ? null : r.status() === opts.expect;
          await panel(text, match === null ? '#737373' : match ? '#16a34a' : '#dc2626', opts.ms || 4200);
          return { status: r.status(), body, url: u.pathname + u.search, sent };
        },
        // Runs a named probe from BA/<slug>/probes.sh through scripts/probe.sh's server.
        console: async (name, ...args) => {
          if (!P.probe) throw new Error('ui.console needs P.probe { url, token }: start scripts/probe.sh and pass its output');
          const side = /^before$/i.test(P.label || '') ? 'before' : 'after'; // WALKTHROUGH runs on the AFTER server
          const b = new URL(P.base);
          const port = b.port || (b.protocol === 'https:' ? '443' : '80');
          const q = new URLSearchParams([['side', side], ['port', port], ...args.map((a) => ['a', String(a)])]);
          const r = await page.request.get(`${P.probe.url}/${name}?${q}`, { headers: { 'X-Probe-Token': P.probe.token }, failOnStatusCode: false });
          if (r.status() !== 200) throw new Error(`probe ${name}: HTTP ${r.status()} ${await r.text()}`);
          const { code, out, cmd } = await r.json();
          await panel(`$ ${cmd}\n${out.replace(/\n$/, '')}${code ? `\n[exit ${code}]` : ''}`, '#a3a3a3', 3500);
          return { code, out: out.trim() };
        },
        // Plain canvas for tickets with no UI path; the URL pill keeps the side's base URL.
        stage: async (title, sub = '') => {
          await page.setContent(`<!doctype html><title>${esc(title)}</title><body style="margin:0;height:100vh;display:grid;place-items:center;background:#0b0b0c;color:#e5e5e5;font:600 30px/1.3 system-ui,sans-serif;text-align:center"><div>${esc(title)}<div style="font:400 17px/1.4 system-ui,sans-serif;opacity:.6;margin-top:10px">${esc(sub)}</div></div></body>`);
        },
```

Replace:

```js
      const result = await scenario({ page, ui, P, preset: preset.name });
      return { label: P.label, preset: preset.name, ...result };
```

with:

```js
      const result = await scenario({ page, ui, P, preset: preset.name });
      return { label: P.label, preset: preset.name, ...result, ...(transcript.length ? { transcript } : {}) };
```

- [ ] **Step 4: Update the header of `templates/flow.js`**

Replace:

```js
//   ui     ui.chapter(title, desc, ms), ui.banner(html, ms, bg), ui.fillSecret(locator, value), ui.esc(text)
```

with:

```js
//   ui     ui.chapter(title, desc, ms), ui.banner(html, ms, bg), ui.fillSecret(locator, value), ui.esc(text),
//          ui.request(method, path, { form | json | multipart, headers, expect, maxRedirects, ms }) -> { status, body, url, sent },
//          ui.console(probeName, ...args) -> { code, out } (needs P.probe), ui.stage(title, sub) for no-UI tickets
```

- [ ] **Step 5: Create `templates/probes.sh`**

```bash
#!/usr/bin/env bash
# probes for <slug>. Reads: <what>. Touches: <what, or "nothing">.
# Run by scripts/probe-server.mjs as: bash probes.sh <name> <args...>, never through a shell.
# Env: BA_SIDE (before|after), BA_PORT (that side's app port), BA_RUN (BA/run: <side>.log lives there).
# One branch per probe. "# cmd: <text>" is what the video shows after "$ ". Tag state-changing
# probes "# trigger". Async effects: poll inside the branch, at most 8 s (the server kills at 10 s).
# No credentials on a command line or in "# cmd:" (query inside the DB container instead), never cat
# secret files, nothing in the background (it is killed when the branch exits).
# Never point at a database or host that is not on this machine.
set -euo pipefail
case "${1:-}" in
  log_grep)     # cmd: grep -c <pattern> <side>.log
    grep -c -- "${2:?pattern}" "$BA_RUN/$BA_SIDE.log" || true ;;
  # Shapes that worked on real projects (copy, adapt, delete the rest):
  # row_count)  # cmd: select count(*) from <table>
  #   docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc 'select count(*) from <table>' ;;
  # sqlite_rows) # cmd: sqlite3 <file> 'select ...'
  #   sqlite3 <file> 'select count(*) from <table>' ;;
  # queue_wait) # cmd: redis-cli LLEN bull:<queue>:wait
  #   docker compose exec -T redis redis-cli LLEN 'bull:<queue>:wait' ;;
  # mail_sent)  # cmd: grep <dev mail log line> <side>.log   (most apps log mail in dev instead of using a catcher)
  #   grep -c -- '<mail log marker>' "$BA_RUN/$BA_SIDE.log" || true ;;
  *) echo "unknown probe: ${1:-}" >&2; exit 2 ;;
esac
```

- [ ] **Step 6: Run the tests**

Run: `bash tests/test-template.sh`
Expected: `# all passed` (parse, ASCII and the new asserts).

- [ ] **Step 7: Commit**

```bash
git add templates/harness.js templates/flow.js templates/probes.sh tests/test-template.sh
git commit -m "feat: request, console and stage helpers in the harness"
```

---

### Task 5: notes-api fixture

**Files:**
- Create: `examples/notes-api/buggy.mjs`, `fixed.mjs`, `make-repo.sh`, `reset.sh`, `probes.sh`, `flow.js`
- Create: `tests/test-notes-api.sh`
- Modify: `tests/test-template.sh` (file loops)
- Modify: `tests/test-portability.sh:40`

- [ ] **Step 1: Write the failing test**

`tests/test-notes-api.sh`:

```bash
#!/usr/bin/env bash
# examples/notes-api: bug on main, fix on fix/notes-auth, probes and reset work without the MCP.
. "$(dirname "$0")/lib.sh"
X=$ROOT/examples/notes-api
T=$(mktemp -d)
T=$(cd "$T" && pwd)
pid=
cleanup() { if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; fi; rm -rf "$T"; }
trap cleanup EXIT
freeport() { python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'; }

"$X/make-repo.sh" "$T/repo" >/dev/null
assert_eq "make-repo exits 0" "$?" 0
assert_eq "left on main" "$(git -C "$T/repo" rev-parse --abbrev-ref HEAD)" main
assert_not_has "main has no role check" "$(cat "$T/repo/server.mjs")" "403"
assert_has "fix answers 403" "$(git -C "$T/repo" show fix/notes-auth:server.mjs)" "403"

port=$(freeport)
serve() { # $1 = server file, $2 = side
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; fi
  NOTES_DB=$T/notes.json NOTES_OUTBOX=$T/outbox.log PORT=$port node "$1" >"$T/$2.log" 2>&1 &
  pid=$!
  i=0
  until curl -s --noproxy '*' -o /dev/null --max-time 1 "http://127.0.0.1:$port/"; do
    i=$((i + 1)); [ "$i" -lt 50 ] || break; sleep 0.1
  done
}
probe() { BA_RUN=$T BA_SIDE=$1 BA_PORT=$port bash "$X/probes.sh" "${@:2}"; }
del() { curl -s --noproxy '*' -o /dev/null -w '%{http_code}' -X POST -H 'X-Role: viewer' "http://127.0.0.1:$port/notes/2/delete"; }

bash "$X/reset.sh" "$T"
serve "$T/repo/server.mjs" before
assert_eq "seeded with 2 notes" "$(probe before note_count)" 2
assert_eq "outbox empty after reset" "$(probe before outbox_tail)" "(empty)"
assert_eq "main lets a viewer delete" "$(del)" 200
assert_eq "main: note gone" "$(probe before note_count)" 1
assert_has "main: mail written" "$(probe before outbox_tail)" "deleted by viewer"
assert_eq "main: server log line" "$(probe before log_grep 'deleted note')" 1

git -C "$T/repo" show fix/notes-auth:server.mjs > "$T/fixed.mjs"
bash "$X/reset.sh" "$T"
serve "$T/fixed.mjs" after
assert_eq "fix refuses a viewer" "$(del)" 403
assert_eq "fix: still 2 notes" "$(probe after note_count)" 2
assert_eq "fix: no mail" "$(probe after outbox_tail)" "(empty)"
assert_eq "fix: no delete in its log" "$(probe after log_grep 'deleted note')" 0
done_testing
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-notes-api.sh`
Expected: FAIL from `make-repo exits 0` onward (fixture missing).

- [ ] **Step 3: Create `examples/notes-api/buggy.mjs`**

```js
// notes-api fixture: a tiny JSON API. The X-Role header stands in for a real session.
// Bug on main: POST /notes/:id/delete has no role check, so a viewer can delete notes.
import http from 'node:http';
import { readFileSync, writeFileSync, appendFileSync } from 'node:fs';

const DB = process.env.NOTES_DB || 'notes.json';
const OUTBOX = process.env.NOTES_OUTBOX || 'outbox.log';
const load = () => JSON.parse(readFileSync(DB, 'utf8'));

http.createServer((req, res) => {
  const send = (code, body) => {
    res.writeHead(code, { 'content-type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  const role = req.headers['x-role'] || 'viewer';
  const del = req.url.match(/^\/notes\/(\d+)\/delete$/);
  if (req.method === 'GET' && req.url === '/') return send(200, { ok: true });
  if (req.method === 'GET' && req.url === '/notes') return send(200, load());
  if (req.method === 'POST' && del) {
    const id = Number(del[1]);
    writeFileSync(DB, JSON.stringify(load().filter((n) => n.id !== id)));
    appendFileSync(OUTBOX, `to=owner@example.test subject="note ${id} deleted by ${role}"\n`);
    console.log(`deleted note ${id} role=${role}`);
    return send(200, { deleted: id });
  }
  send(404, { error: 'not found' });
}).listen(Number(process.env.PORT) || 8000, '127.0.0.1');
```

- [ ] **Step 4: Create `examples/notes-api/fixed.mjs`**

Same file as `buggy.mjs` with two changes. Line 2 of the header becomes:

```js
// Fixed: only an admin may delete; anyone else gets 403 and nothing changes.
```

and the delete branch becomes:

```js
  if (req.method === 'POST' && del) {
    if (role !== 'admin') return send(403, { error: 'forbidden' });
    const id = Number(del[1]);
    writeFileSync(DB, JSON.stringify(load().filter((n) => n.id !== id)));
    appendFileSync(OUTBOX, `to=owner@example.test subject="note ${id} deleted by ${role}"\n`);
    console.log(`deleted note ${id} role=${role}`);
    return send(200, { deleted: id });
  }
```

- [ ] **Step 5: Create `examples/notes-api/make-repo.sh`**

```bash
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
```

- [ ] **Step 6: Create `examples/notes-api/reset.sh`**

```bash
#!/usr/bin/env bash
# Reset for the notes-api demo. Touches only <dir>/notes.json and <dir>/outbox.log.
# reset.sh <dir>   (the run's BA/run dir, where config points NOTES_DB and NOTES_OUTBOX)
set -euo pipefail
dir=${1:?usage: reset.sh <dir>}
printf '%s\n' '[{"id":1,"text":"first"},{"id":2,"text":"second"}]' > "$dir/notes.json"
: > "$dir/outbox.log"
```

- [ ] **Step 7: Create `examples/notes-api/probes.sh`**

```bash
#!/usr/bin/env bash
# probes for notes-api. Reads: BA_RUN/notes.json, BA_RUN/outbox.log, BA_RUN/<side>.log. Touches: nothing.
set -euo pipefail
case "${1:-}" in
  note_count)   # cmd: grep -o '"id"' notes.json | wc -l
    grep -o '"id"' "$BA_RUN/notes.json" | wc -l | tr -d ' ' ;;
  outbox_tail)  # cmd: tail -n 3 outbox.log
    if [ -s "$BA_RUN/outbox.log" ]; then tail -n 3 "$BA_RUN/outbox.log"; else echo "(empty)"; fi ;;
  log_grep)     # cmd: grep -c <pattern> <side>.log
    grep -c -- "${2:?pattern}" "$BA_RUN/$BA_SIDE.log" || true ;;
  *) echo "unknown probe: ${1:-}" >&2; exit 2 ;;
esac
```

- [ ] **Step 8: Create `examples/notes-api/flow.js`**

```js
// Reference scenario for examples/notes-api (built from templates/flow.js), recorded on a stage page.
// Gate: BEFORE status=200, notes 2->1, mailed=true, logged>=1; AFTER status=403, notes 2->2, mailed=false, logged=0.
// (logged counts across the dry-run and the recording: the side's server log is not reset.)
// Needs P.probe from scripts/probe.sh with examples/notes-api/probes.sh.
async (loader) => {
  const KIND = 'flow';
  loader.__ba = { ...loader.__ba, [KIND]: async ({ ui }) => {
    await ui.stage('notes-api', 'A viewer tries to delete note 2');
    await ui.chapter('1 - Starting state', 'Two notes, empty outbox', 2000);
    const before = await ui.console('note_count');
    await ui.chapter('2 - A viewer deletes note 2', 'Expected: 403 Forbidden, nothing changes', 2000);
    const r = await ui.request('POST', '/notes/2/delete', { headers: { 'X-Role': 'viewer' }, expect: 403 });
    await ui.chapter('3 - What changed', 'Notes, outbox and server log', 2000);
    const after = await ui.console('note_count');
    const mail = await ui.console('outbox_tail');
    const logged = await ui.console('log_grep', 'deleted note');
    return {
      status: r.status,
      notes: `${before.out}->${after.out}`,
      mailed: mail.out !== '(empty)',
      logged: Number(logged.out),
    };
  } };
  return `loaded page.__ba.${KIND}`;
}
```

Run: `chmod +x examples/notes-api/make-repo.sh examples/notes-api/reset.sh examples/notes-api/probes.sh`

- [ ] **Step 9: Include the fixture in the template and portability tests**

In `tests/test-template.sh`, change both file loops:

```bash
for f in "$ROOT/templates/harness.js" "$ROOT/templates/flow.js" "$ROOT/examples/counter/flow.js"; do
```
→
```bash
for f in "$ROOT/templates/harness.js" "$ROOT/templates/flow.js" "$ROOT/examples/counter/flow.js" "$ROOT/examples/notes-api/flow.js"; do
```
and
```bash
for f in "$ROOT/templates/flow.js" "$ROOT/examples/counter/flow.js"; do
```
→
```bash
for f in "$ROOT/templates/flow.js" "$ROOT/examples/counter/flow.js" "$ROOT/examples/notes-api/flow.js"; do
```

In `tests/test-portability.sh`, change:

```bash
files=("$ROOT"/scripts/*.sh "$ROOT"/examples/counter/*.sh)
```
→
```bash
files=("$ROOT"/scripts/*.sh "$ROOT"/examples/*/*.sh "$ROOT"/templates/*.sh)
```

- [ ] **Step 10: Run the tests**

Run: `bash tests/run-all.sh`
Expected: exit 0; `test-notes-api.sh` and `test-template.sh` end with `# all passed`.

- [ ] **Step 11: Commit**

```bash
git add examples/notes-api tests/test-notes-api.sh tests/test-template.sh tests/test-portability.sh
git commit -m "feat: add notes-api fixture for backend proof"
```

---

### Task 6: SKILL.md, config reference, README

**Files:**
- Modify: `SKILL.md` (lines 63-69, 98-112, 124, 129-142, 158, 171, 173-190)
- Modify: `references/config.md`
- Modify: `README.md`

- [ ] **Step 1: DoD template (SKILL.md §1)**

Replace:

```
| # | Criterion | BEFORE should show | AFTER should show |
|---|---|---|---|
| 1 | <item> | <observable in the browser> | <observable in the browser> |
```

with:

```
| # | Criterion | Proof | BEFORE should show | AFTER should show |
|---|---|---|---|---|
| 1 | <item> | ui · http · data · mail · log · none | <observable> | <observable> |
```

Replace `Not shown in video: <criteria a browser can't observe, e.g. "email is sent", or "none">` with `Not shown in video: <criteria with Proof none, or "none">`.

- [ ] **Step 2: Scenario (SKILL.md §1b)**

After the line `- Overlays that describe a request or response are built from what was actually sent and received (real path, encoded body, status), never a hand-written label.` add:

```markdown

Backend criteria (Proof column): `http` → `ui.request(method, path, { form | json, headers, expect })`, which shows the real request and response (redirects not followed, so a 302 to login is visible). `data`, `mail`, `log` → copy `SKILL_DIR/templates/probes.sh` to `BA/<slug>/probes.sh`, add one `case` branch per check (`# cmd:` = what the video shows; `# trigger` on branches that change state, e.g. running a cron job), and call `ui.console(name, ...args)` right after the action it proves. Probes read; async effects poll inside the branch for at most 8 s. No UI path at all (webhook, cron, internal API): start the scenario with `ui.stage(title, sub)` and one chapter per DoD item. `examples/notes-api/` in the skill dir is a complete example.
```

- [ ] **Step 3: Plan screen item 4 (SKILL.md §1c)**

Replace:

```
4. **Data** (when the scenario changes data): the reset target (choice, if not saved yet), what `reset.sh` touches, the test accounts or rows it will create.
```

with:

```
4. **Data** (when the scenario changes data or has probes): the reset target (choice, if not saved yet), what `reset.sh` touches, the test accounts or rows it will create, and `probes.sh` in full with its `# trigger` branches listed apart. Any `data` or `mail` probe makes a reset required (both sides share services); the reset also empties shared mailboxes (e.g. Mailpit `DELETE /api/v1/messages`).
```

- [ ] **Step 4: Provision (SKILL.md §2)**

After the two `provision.sh` command lines block (ending ```` ``` ````) and before `Port in use:`, add:

````markdown

When `BA/<slug>/probes.sh` exists, start the probe server after the sides:

```
SKILL_DIR/scripts/probe.sh --probes BA/<slug>/probes.sh --state BA/run --port <probe_port> [--mask-env <login user_env>,<login pass_env>]
```

Pass its `probe_url` and `probe_token` in every run call as `probe: { url, token }`.
````

- [ ] **Step 5: Gate (SKILL.md §3)**

Replace `Gate, judged against \`dod.md\`: BEFORE's returned facts must show the problem and AFTER's must not.` with `Gate, judged against \`dod.md\`: BEFORE's returned facts (UI, request and probe facts alike) must show the problem and AFTER's must not.`

- [ ] **Step 6: Teardown (SKILL.md §5)**

After `Then teardown: \`SKILL_DIR/scripts/teardown.sh --state BA/run --repo <git root> --keep <before sha> --keep <after sha>\` (the full shas resolve printed).` add ` It also stops the probe server (\`stopped=probe\`).`

- [ ] **Step 7: Report (SKILL.md §6)**

Replace:

```
Resolved by: <rule> · <MR link if any> · presets: <list> · durations: <s>
<!-- drop the videos here -->
```

with:

```
Resolved by: <rule> · <MR link if any> · presets: <list> · durations: <s>
<!-- drop the videos here -->

<details><summary>BEFORE evidence</summary>

```text
<the BEFORE run's transcript entries, in order, one blank line apart>
```
</details>

<details><summary>AFTER evidence</summary>

```text
<the AFTER run's transcript entries>
```
</details>
```

(Only when the runs returned a `transcript`; take it from the recording run, not the dry-run.)

- [ ] **Step 8: Config reference**

In `references/config.md`, after the `reset_target:` line of the schema add:

```yaml
probe_port: 47100               # optional. port for scripts/probe.sh when a scenario has probes; discover picks a free one
```

Add at the end of the file:

````markdown

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
reset: sh .playwright-mcp/ba/reset.sh .playwright-mcp/ba/run
reset_target: sandbox
probe_port: 47100
viewports: [desktop]
```
````

- [ ] **Step 9: README**

In `README.md`, after the line starting `Try it on the bundled demo:` add:

```markdown

Backend fixes get proven the same way: requests and their real responses, plus live output of named checks (a DB count, a mail outbox, a log grep), are shown as panels in the video. A ticket with no UI records on a plain stage page. Demo: `examples/notes-api/make-repo.sh /tmp/notes-api`, then ask for before/after of `fix/notes-auth`.
```

- [ ] **Step 10: Run the suite and commit**

Run: `bash tests/run-all.sh`
Expected: exit 0.

```bash
git add SKILL.md references/config.md README.md
git commit -m "docs: backend proof in the pipeline"
```

---

### Task 7: Manual end-to-end runs

No code; these runs are the harness helpers' real test (they only run inside the MCP).

- [ ] **Step 1: notes-api fixture**

```bash
examples/notes-api/make-repo.sh /tmp/notes-api
```

Open Claude Code in `/tmp/notes-api` and ask: "record before/after of fix/notes-auth: a viewer must get 403 deleting a note and nothing may change". Copy `examples/notes-api/reset.sh` to `BA/reset.sh` and `probes.sh` to `BA/<slug>/probes.sh` when the agent asks for them, or let it write its own and compare.

Expected:
- plan screen shows `dod.md` with Proof `http`, `data`, `mail`, `log`, and `probes.sh` in full;
- dry-run gate: BEFORE `status=200 notes=2->1 mailed=true logged>=1`, AFTER `status=403 notes=2->2 mailed=false logged=0`;
- both contact sheets show the stage page with request and console panels, not a blank page;
- `summary.md` has both evidence blocks; `grep -c '\*\*\*'` finds no unmasked values from `--mask-env`;
- `teardown.sh` prints `stopped=probe`.

- [ ] **Step 2: private testbed re-run (notes stay in `local/`)**

Re-run the testbed ticket with `ui.request` for the escalation and logged-out requests and a `user_role` probe instead of the hand-written panels. Compare with the earlier hand-made videos (see the testbed notes in `local/`). Write findings into the testbed notes in `local/`; anything that cost a failed run goes into `references/findings.md` (generic wording, nothing from the client project).

- [ ] **Step 3: Update CLAUDE.md "Where we are"**

Add one line: `- Backend proof (D20): request/console/stage helpers, probe server, notes-api fixture.` Commit:

```bash
git add CLAUDE.md references/findings.md
git commit -m "docs: backend proof done"
```
