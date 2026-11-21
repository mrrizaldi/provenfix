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
