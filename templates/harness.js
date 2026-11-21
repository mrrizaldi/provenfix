// provenfix recording harness (spec: "templates contract"). Shared by every scenario.
// The agent copies it to <project>/.playwright-mcp/ba/harness.js and loads it once per MCP browser
// with browser_run_code_unsafe { filename }: that only registers page.__ba.run and records nothing.
// Scenarios (flow.js, walkthrough.js) are small files loaded the same way; they register page.__ba[kind].
// Each phase is then one short call (why the split: findings #13):
//   async (page) => page.__ba.run(page, 'flow', { base, label, sub, preset, out, ...params })
async (loader) => {
  // Masks what a request or console panel may show. Lives out here so tests/test-template.sh can call it.
  // Secret-looking keys: a whole word part (so "authorized", "footprint" stay visible), plural allowed.
  // camelCase is split first, so accessToken and newPassword count like access_token and new_password.
  const SECRET_KEY = /(^|[^a-z])(pass(word|wd)?|pwd|secret|token|api[-_]?key|private[-_]?key|authorization|auth|credentials?|otp|session|sid|cookie|csrf|xsrf|jwt|bearer|signature|refresh)s?([^a-z]|$)/i;
  const isSecret = (k) => SECRET_KEY.test(String(k).replace(/([a-z0-9])([A-Z])/g, '$1_$2'));
  // Numbers stay visible only under counter-like keys (session_count, token_ttl); a numeric otp/pin is masked.
  const COUNTER_KEY = /count|length|len|ttl|expir|max|min|age|size|_at$/i;
  const keep = (k, v) => v === null || v === 'null' || typeof v === 'boolean' || v === 'true' || v === 'false' || ((typeof v === 'number' || /^\d+$/.test(v)) && COUNTER_KEY.test(k));
  const hideText = (s) => String(s)
    .replace(/\b(Bearer|Basic)\s+[\w.~+/-]+=*/g, '$1 ***')
    .replace(/([?&#;])([\w.-]+)=([^&#\s"]*)/g, (m, sep, k, v) => (isSecret(k) && !keep(k, v) ? `${sep}${k}=***` : m))
    .replace(/((?:"[^"\n]*"|(?<![\w.-])[A-Za-z_][\w.-]*)\s*[:=]\s*)("(?:[^"\\\n]|\\.)*"|[^"&\s,}\]]+)/g, (m, k, v) => {
      const raw = v.startsWith('"') ? v.slice(1, -1) : v;
      return isSecret(k) && !keep(k, raw) ? k + (v.startsWith('"') ? '"***"' : '***') : m;
    });
  // JSON bodies are masked structurally: a secret key hides its whole value (arrays, objects included).
  const hideJson = (k, v) => {
    if (k && isSecret(k) && !keep(k, v)) return '***';
    return typeof v === 'string' ? hideText(v) : v;
  };
  // React Router single fetch ("turbo-stream") bodies are one flat JSON array where each object is
  // {"_<key slot>": <value slot>}: a key and its value sit in separate slots, so key masking can't pair
  // them. Mask the slot a secret key points to. Later lines (streamed promises) go through hideText.
  const turbo = (t) => {
    const nl = t.indexOf('\n');
    try {
      const a = JSON.parse(nl < 0 ? t : t.slice(0, nl));
      const slotObj = (x) => x && typeof x === 'object' && !Array.isArray(x) && Object.keys(x).length > 0 && Object.keys(x).every((k) => /^_\d+$/.test(k));
      return Array.isArray(a) && a.some(slotObj) ? { a, slotObj, tail: nl < 0 ? '' : t.slice(nl) } : null;
    } catch { return null; }
  };
  const hideTurbo = ({ a, slotObj, tail }) => {
    const out = a.slice();
    for (const x of a.filter(slotObj)) {
      for (const [k, j] of Object.entries(x)) {
        const name = a[Number(k.slice(1))];
        if (typeof j === 'number' && j >= 0 && typeof name === 'string' && isSecret(name) && !keep(name, a[j])) out[j] = '***';
      }
    }
    return JSON.stringify(out.map((v) => (typeof v === 'string' ? hideText(v) : v))) + hideText(tail);
  };
  // A single-fetch redirect answers 202 and carries { redirect, status } in the body: read it from there.
  const singleFetchRedirect = (s) => {
    const ts = turbo(String(s));
    if (!ts) return null;
    for (const x of ts.a.filter(ts.slotObj)) {
      const f = {};
      for (const [k, j] of Object.entries(x)) f[ts.a[Number(k.slice(1))]] = ts.a[j];
      if (typeof f.redirect === 'string' && typeof f.status === 'number') return { status: f.status, to: f.redirect };
    }
    return null;
  };
  const hideSecrets = (s) => {
    const t = String(s);
    const ts = turbo(t);
    if (ts) { const m = hideTurbo(ts); return m === JSON.stringify(ts.a) + ts.tail ? t : m; }
    try {
      const j = JSON.parse(t);
      // re-serialize only when something was hidden: a round trip rewrites ids above 2^53 and key order
      if (j && typeof j === 'object') { const m = JSON.stringify(j, hideJson); return m === JSON.stringify(j) ? t : m; }
    } catch { /* not JSON */ }
    return hideText(t);
  };
  // Loading the harness resets page.__ba, so scenarios from an earlier run can't answer for this one:
  // load it first, then the scenarios.
  loader.__ba = { hideSecrets, singleFetchRedirect, run: async (page0, kind, P) => {
    if (!P || !P.base) throw new Error('page.__ba.run(page, kind, params): params.base is required');
    const scenario = kind !== 'run' && page0.__ba && page0.__ba[kind];
    if (typeof scenario !== 'function') throw new Error(`page.__ba.${kind} is not loaded: load BA/<slug>/${kind}.js first`);

    const PRESETS = {
      desktop: { width: 1440, height: 900, dpr: 1, mobile: false },
      tablet: { width: 820, height: 1180, dpr: 2, mobile: true, ua: 'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1' },
      mobile: { width: 390, height: 844, dpr: 3, mobile: true, ua: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1' },
    };
    const preset = P.preset && typeof P.preset === 'object'
      ? { name: 'custom', ...P.preset }
      : { name: P.preset || 'desktop', ...PRESETS[P.preset || 'desktop'] };
    if (!preset.width || !preset.height) throw new Error(`unknown preset: ${JSON.stringify(P.preset)}`);
    const size = { width: preset.width, height: preset.height }; // video = CSS size, never x DPR (D14)

    // Own headless browser per phase (findings #14): a headed window gets whatever size the window
    // manager gives it, and the screencast records that window, not the emulated viewport.
    // Fresh context inside it: clean cookies and storage, real device emulation (findings #5, #9).
    const mcpBrowser = page0.context().browser();
    if (!mcpBrowser) throw new Error('Playwright MCP gave no browser handle (persistent context): restart it with --isolated');
    const bt = mcpBrowser.browserType();
    // lets the agent find a phase still running after a rejected call (findings #15); the side's port
    // scopes it, so another project recording at the same time doesn't match (findings #19)
    const MARK = `--provenfix-recorder=${new URL(P.base).port || 'default'}`;

    const quiet = async (fn) => { try { await fn(); } catch { /* already gone */ } };
    const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
    const LINK_ICON = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" style="vertical-align:-2px;margin-right:6px"><path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/></svg>';
    const url = P.base.replace(/\/+$/, '') + '/' + String(P.startPath || '').replace(/^\/+/, '');

    let browser;
    let ctx;
    let page;
    try {
      browser = await bt.launch({ channel: 'chrome', headless: true, args: [MARK] }).catch(() => bt.launch({ headless: true, args: [MARK] }));
      ctx = await browser.newContext({
        viewport: size,
        deviceScaleFactor: preset.dpr || 1,
        isMobile: !!preset.mobile,
        hasTouch: !!preset.mobile,
        ignoreHTTPSErrors: true, // local dev servers often use self-signed certs
        ...(preset.ua ? { userAgent: preset.ua } : {}),
      });
      page = await ctx.newPage();
      await page.goto(url);
      // findings #4: let the dev server settle; capped because long-polling/SSE apps never go idle
      await page.waitForLoadState('networkidle', { timeout: 10000 }).catch(() => {});
      // Stage page for tickets with no UI path: title on top, panels centred below it.
      // P.stage draws it before recording starts, so the raw page never shows on camera.
      let staged = false;
      const renderStage = async (title, sub) => {
        await page.setContent(`<!doctype html><title>${esc(title)}</title><body style="margin:0;height:100vh;box-sizing:border-box;padding-top:12vh;display:flex;flex-direction:column;align-items:center;background:#0b0b0c;color:#e5e5e5;font:600 34px/1.3 system-ui,sans-serif;text-align:center"><div>${esc(title)}</div><div style="font:400 19px/1.4 system-ui,sans-serif;opacity:.6;margin-top:10px">${esc(sub)}</div></body>`);
        staged = true;
      };
      if (P.stage) await renderStage(P.stage, P.stageSub || '');
      if (P.out) await page.screencast.start({ path: P.out, size });

      // URL pill (D2): the screencast has no browser chrome, so show where we are.
      // Updates are chained so a redirect or pushState burst never leaves two pills,
      // and never reject (an unhandled rejection could take down the MCP server).
      let pill;
      let pillChain = Promise.resolve();
      const showPill = () => (pillChain = pillChain.then(async () => {
        await pill?.dispose();
        const u = new URL(page.url());
        pill = await page.screencast.showOverlay(`<div style="position:fixed;left:12px;bottom:12px;padding:7px 14px;border-radius:999px;background:rgba(17,17,17,.8);color:#fff;font:500 15px/1.2 ui-monospace,monospace;max-width:70vw;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${LINK_ICON}<span style="opacity:.6">${esc(u.host)}</span>${esc(u.pathname + u.search)}</div>`);
      }).catch(() => { /* page already closed */ }));
      page.on('framenavigated', (f) => { if (f === page.mainFrame()) showPill(); });
      await showPill();

      const ACTIONS = { position: 'top-right', duration: 700 };
      // Request and console panels (spec: backend proof). Text comes only from what was really sent,
      // received or printed; it is escaped here, kept in `transcript` for summary.md, and held on
      // screen for ms so the viewer can read it.
      const transcript = [];
      const panel = async (text, color, ms) => {
        transcript.push(text);
        // On the stage page the panel is the content: centred and larger. Over an app it stays in a corner.
        const box = staged
          ? 'left:50%;top:56%;transform:translate(-50%,-50%);max-width:min(1100px,92vw);max-height:60vh;padding:20px 26px;font:20px/1.5 ui-monospace,monospace'
          : 'right:16px;bottom:56px;max-width:min(760px,92vw);max-height:62vh;padding:12px 16px;font:13px/1.45 ui-monospace,monospace';
        await page.screencast.showOverlay(`<pre style="position:fixed;${box};overflow:hidden;margin:0;border-radius:10px;border-left:6px solid ${color};background:rgba(24,24,27,.96);color:#e5e5e5;white-space:pre-wrap;word-break:break-all;box-shadow:0 4px 16px rgba(0,0,0,.35)">${esc(text)}</pre>`, { duration: ms }).catch(() => {});
        await page.waitForTimeout(ms + 200);
      };
      const ui = {
        esc,
        chapter: async (title, description, ms = 2500) => {
          await page.screencast.showChapter(title, { description, duration: ms });
          await page.waitForTimeout(ms + 200);
        },
        // fills without the action overlay, which would print the value on camera (findings #17)
        fillSecret: async (locator, value) => {
          await page.screencast.hideActions();
          try { await locator.fill(value); } finally { await page.screencast.showActions(ACTIONS); }
        },
        // html goes in as-is: wrap any text taken from the page in ui.esc()
        banner: (html, ms = 3000, bg = '#b91c1c') => page.screencast.showOverlay(`<div style="position:fixed;top:16px;left:50%;transform:translateX(-50%);max-width:90vw;padding:10px 18px;border-radius:10px;background:${bg};color:#fff;font:600 16px/1.3 system-ui,sans-serif;box-shadow:0 4px 16px rgba(0,0,0,.35)">${html}</div>`, { duration: ms }).catch(() => {}), // never reject: an un-awaited banner must not crash the MCP
        // Sends through page.request (the page's cookies: acts as the user signed in on camera).
        // opts: { form } | { json } | { multipart }, headers, expect (status: green when it matches, red when not),
        // maxRedirects, ms. Non-GET gets the app's Origin like a browser would (Origin/CSRF checks are common).
        // Bearer apps: read the token with page.evaluate and pass headers.Authorization; headers are never shown.
        request: async (method, path, opts = {}) => {
          if (!path.startsWith('/')) path = `/${path}`;
          const hasOrigin = Object.keys(opts.headers || {}).some((k) => /^origin$/i.test(k));
          const origin = /^(GET|HEAD)$/i.test(method) || hasOrigin ? {} : { Origin: new URL(P.base).origin };
          const o = { method, headers: { ...origin, ...opts.headers }, failOnStatusCode: false, maxRedirects: opts.maxRedirects ?? 0 };
          let sent = '';
          if (opts.multipart) {
            o.multipart = opts.multipart;
            sent = Object.entries(opts.multipart).map(([k, v]) => `${k}=${v && typeof v === 'object' ? `<file: ${v.name || 'blob'}>` : isSecret(k) && !keep(k, v) ? '***' : v}`).join('&');
          } else if (opts.form) {
            o.form = opts.form;
            sent = new URLSearchParams(Object.entries(opts.form).map(([k, v]) => [k, isSecret(k) && !keep(k, v) ? '***' : String(v)])).toString();
          } else if (opts.json !== undefined) {
            o.data = opts.json;
            sent = JSON.stringify(opts.json, hideJson);
          }
          const sentUrl = new URL(P.base.replace(/\/+$/, '') + path);
          let r, body;
          try {
            r = await page.request.fetch(sentUrl.href, o);
            body = await r.text();
          } catch (e) {
            throw new Error(`request to ${P.base} failed: ${String(e && e.message).split('\n')[0]}`); // first line only: the call log can print headers
          }
          const sentPath = hideSecrets(sentUrl.pathname + sentUrl.search);
          const fin = new URL(r.url());
          const loc = r.headers().location;
          const lines = hideSecrets(body.slice(0, 20000)).replace(/\n\s*\n+/g, '\n').split('\n'); // mask first (20 KB bounds the cost), then cut
          const clipped = lines.slice(0, 20).join('\n').slice(0, 600);
          const cut = lines.length > 20 || lines.join('\n').length > 600;
          const sfr = r.status() === 202 ? singleFetchRedirect(body) : null;
          const status = `${r.status()}${r.statusText() ? ` ${r.statusText()}` : ''}${sfr ? `  (single-fetch redirect: ${sfr.status} -> ${hideSecrets(sfr.to)})` : ''}`;
          const hdrs = Object.entries(opts.headers || {}).filter(([k]) => !isSecret(k) && !/^origin$/i.test(k)).map(([k, v]) => `\n   ${k}: ${hideSecrets(String(v))}`).join('');
          const text = `-> ${method} ${sentPath}${hdrs}${sent ? `\n   ${sent}` : ''}\n<- ${status}${fin.href !== sentUrl.href ? `  (final: ${hideSecrets(fin.pathname + fin.search)})` : ''}${loc ? `  Location: ${hideSecrets(loc)}` : ''}${body ? `\n   ${clipped}${cut ? ' ...' : ''}` : ''}`;
          // expect may name the real redirect status (302) of a single-fetch redirect as well as the 202
          const match = opts.expect === undefined ? null : r.status() === opts.expect || (sfr && sfr.status === opts.expect);
          await panel(text, match === null ? '#737373' : match ? '#16a34a' : '#dc2626', opts.ms || 4200);
          return { status: r.status(), body, url: sentPath, sent, ...(sfr ? { redirect: sfr } : {}) };
        },
        // Runs a named probe from BA/<slug>/probes.sh through scripts/probe.sh's server.
        console: async (name, ...args) => {
          if (!P.probe) throw new Error('ui.console needs P.probe { url, token }: start scripts/probe.sh and pass its output');
          const side = P.side || ({ BEFORE: 'before', AFTER: 'after', WALKTHROUGH: 'after' })[String(P.label || '').trim().toUpperCase()]; // WALKTHROUGH runs on the AFTER server
          if (!side) throw new Error(`ui.console: cannot tell the side from label "${P.label}": pass P.side ('before' or 'after')`);
          const b = new URL(P.base);
          const port = b.port || (b.protocol === 'https:' ? '443' : '80');
          const q = new URLSearchParams([['side', side], ['port', port], ...args.map((a) => ['a', String(a)])]);
          let r, errText = '';
          try {
            r = await page.request.get(`${P.probe.url}/${name}?${q}`, { headers: { 'X-Probe-Token': P.probe.token }, failOnStatusCode: false });
            if (r.status() !== 200) errText = await r.text();
          } catch (e) {
            throw new Error(`probe server unreachable at ${P.probe.url}: ${String(e && e.message).split('\n')[0]}`); // first line only: the call log can print the token
          }
          if (r.status() !== 200) throw new Error(`probe ${name}: HTTP ${r.status()} ${errText}`);
          const raw = await r.json();
          const { code, cmd } = raw;
          const out = hideSecrets(raw.out);
          await panel(`$ ${cmd}\n${out.replace(/\n$/, '')}${code ? `\n[exit ${code}]` : ''}`, '#a3a3a3', 3500);
          return { code, out: out.trim() };
        },
        // Plain canvas for tickets with no UI path; the URL pill keeps the page URL (base + startPath).
        stage: async (title, sub = '') => {
          await renderStage(title, sub);
          await showPill(); // setContent replaces the DOM and framenavigated may not fire
        },
      };

      await page.screencast.showActions(ACTIONS);
      await ui.chapter(P.label || '', P.sub || '', 2200);

      const result = await scenario({ page, ui, P, preset: preset.name });
      return { label: P.label, preset: preset.name, ...result, ...(transcript.length ? { transcript } : {}) };
    } finally {
      if (page) {
        await quiet(() => page.screencast.hideActions());
        if (P.out) await quiet(() => page.screencast.stop());
      }
      await quiet(() => ctx?.close());
      await quiet(() => browser?.close());
    }
  } };
  return 'loaded page.__ba.run';
}
