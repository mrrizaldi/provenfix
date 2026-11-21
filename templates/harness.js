// before-after recording harness (spec: "templates contract"). Shared by every scenario.
// The agent copies it to <project>/.playwright-mcp/ba/harness.js and loads it once per MCP browser
// with browser_run_code_unsafe { filename }: that only registers page.__ba.run and records nothing.
// Scenarios (flow.js, walkthrough.js) are small files loaded the same way; they register page.__ba[kind].
// Each phase is then one short call (why the split: findings #13):
//   async (page) => page.__ba.run(page, 'flow', { base, label, sub, preset, out, ...params })
async (loader) => {
  // Loading the harness resets page.__ba, so scenarios from an earlier run can't answer for this one:
  // load it first, then the scenarios.
  loader.__ba = { run: async (page0, kind, P) => {
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
    const MARK = '--before-after-recorder'; // lets the agent find a phase still running after a rejected call (findings #15)

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
      };

      await page.screencast.showActions(ACTIONS);
      await ui.chapter(P.label || '', P.sub || '', 2200);

      const result = await scenario({ page, ui, P, preset: preset.name });
      return { label: P.label, preset: preset.name, ...result };
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
