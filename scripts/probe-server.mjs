// provenfix probe server (spec: docs/superpowers/specs/2026-11-21-backend-proof-design.md).
// Start it with probe.sh, not directly. It binds 127.0.0.1, needs BA_PROBE_TOKEN, and runs only
// named branches of the probes file, as argv without a shell.
import http from 'node:http';
import { spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import os from 'node:os';

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
// Secret masking. A name is secret when one of its "_" parts is a secret word and none is a
// "not secret" word: VALKEY_HOST has no KEY part, AWS_ACCESS_KEY_ID and SUPABASE_ANON_KEY are public.
// Implicit secrets skip booleans, numbers and paths (JWT_TOKEN_EXPIRY_MINUTES=10080 must not turn a row
// count into ***) and values that a plain env var also holds (dev setups reuse the user name as password).
// --mask-env names are always masked (4+ chars). Credentials inside any URL (scheme://user:pass@) too.
const SECRET_PART = new Set(['TOKEN', 'SECRET', 'PASSWORD', 'PASS', 'PWD', 'KEY', 'APIKEY', 'COOKIE', 'DSN', 'CREDENTIALS', 'PRIVATE']);
const PUBLIC_PART = new Set(['ID', 'PUBLIC', 'ANON', 'SITE', 'TTL', 'EXPIRY', 'EXPIRES', 'MIN', 'LENGTH', 'ENABLED', 'ALLOW', 'PATH', 'FILE']);
const secretName = (k) => {
  const parts = k.toUpperCase().split('_');
  return parts.some((p) => SECRET_PART.has(p)) && !parts.some((p) => PUBLIC_PART.has(p));
};
const env = Object.entries(process.env).filter(([, v]) => v);
const plainValues = new Set(env.filter(([k]) => !maskNames.includes(k) && !secretName(k)).map(([, v]) => v));
const secrets = env
  .filter(([k, v]) => (maskNames.includes(k)
    ? v.length >= 4
    : secretName(k) && v.length >= 6 && !/^(true|false|yes|no|on|off|\d+)$/i.test(v) && !/^\.?\//.test(v) && !plainValues.has(v)))
  .map(([, v]) => v)
  .sort((a, b) => b.length - a.length);
const URL_CREDS = /(\b[a-z][a-z0-9+.-]*:\/\/[^:/@\s]+:)[^@\s]+@/gi;
const mask = (text) => secrets.reduce((t, v) => t.split(v).join('***'), text).replace(URL_CREDS, '$1***@');

const live = new Set();
const killGroup = (pid) => { try { process.kill(-pid, 'SIGKILL'); } catch { /* already gone */ } };
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => { for (const pid of live) killGroup(pid); process.exit(0); });
}

const childEnv = { ...process.env };
delete childEnv.BA_PROBE_TOKEN;

const server = http.createServer((req, res) => {
  const send = (code, body) => {
    if (res.headersSent || res.writableEnded) return;
    res.writeHead(code, { 'content-type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  if (req.headers['x-probe-token'] !== token) return send(401, { error: 'bad or missing X-Probe-Token' });
  let u;
  try { u = new URL(req.url, 'http://127.0.0.1'); } catch { return send(400, { error: 'bad url' }); }
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
  // "# cmd:" text shows bash positionals ($1 = name, $2.. = args), $BA_SIDE and $BA_PORT as they really were
  const vars = { BA_SIDE: side, BA_PORT: port };
  const pos = [name, ...args];
  const cmd = cmdLine
    ? cmdLine[1].trim().replace(/\$(?:\{(\d|BA_SIDE|BA_PORT)\}|(\d|BA_SIDE|BA_PORT)\b)/g, (m, a, b) => { const k = a || b; return /^\d$/.test(k) ? (k === '0' ? m : pos[k - 1] ?? '') : vars[k]; })
    : ['probes.sh', ...pos].join(' ');

  // detached: own process group, so a kill also reaches the probe's children (sleep, curl, psql)
  let child;
  try {
    child = spawn('bash', [opt.probes, name, ...args], {
      env: { ...childEnv, BA_SIDE: side, BA_PORT: port, BA_RUN: opt.run },
      stdio: ['ignore', 'pipe', 'pipe'],
      detached: true,
    });
  } catch (e) {
    return send(500, { error: `spawn failed: ${e.message}` }); // EAGAIN and friends throw instead of emitting 'error'
  }
  live.add(child.pid);
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  let out = '';
  const take = (d) => { if (out.length <= LIMIT + 512) out += d; }; // a little past the cut, so masking sees a secret that straddles it
  child.stdout.on('data', take);
  child.stderr.on('data', take);
  let timedOut = false;
  let exitCode = null;
  const timer = setTimeout(() => {
    if (exitCode === null) timedOut = true;
    killGroup(child.pid);
  }, KILL_MS);
  child.on('error', (e) => {
    clearTimeout(timer);
    live.delete(child.pid);
    send(500, { error: `cannot run probe: ${e.message}` });
  });
  // leftover background processes would hold the pipes open; kill them once the probe itself is done
  child.on('exit', (code, signal) => {
    exitCode = timedOut ? 124 : code ?? 128 + (os.constants.signals[signal] || 0);
    killGroup(child.pid);
  });
  child.on('close', () => {
    clearTimeout(timer);
    live.delete(child.pid);
    out = mask(out); // mask first, then cut: a secret on the boundary must not leave a prefix
    const cut = out.length > LIMIT;
    out = (cut ? out.slice(0, LIMIT) : out) + (cut ? '\n...[cut]' : '');
    send(200, { code: exitCode, out, cmd: mask(cmd) });
  });
});
server.on('error', (e) => { console.error(`probe-server: ${e.message}`); process.exit(1); });
server.listen(Number(opt.port), '127.0.0.1');
