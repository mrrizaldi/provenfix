// provenfix scenario. The agent copies this file to <project>/.playwright-mcp/ba/<slug>/flow.js
// (walkthrough: <slug>/walkthrough.js with KIND = 'walkthrough') and replaces the body.
// Load it with browser_run_code_unsafe { filename } after harness.js, and again after every edit.
// It runs inside page.__ba.run(page, KIND, params), which opens a fresh context per phase:
//   page   the phase's page, already on params.base + params.startPath
//   ui     ui.chapter(title, desc, ms), ui.banner(html, ms, bg), ui.fillSecret(locator, value), ui.esc(text),
//          ui.request(method, path, { form | json | multipart, headers, expect, maxRedirects, ms }) -> { status, body, url, sent, redirect? },
//          (React Router single fetch: a redirect answers 202; the panel and `redirect` show the real { status, to }, and expect: 302 matches it)
//          (body is raw, for the scenario's own checks: never return it or secrets from it as a fact, facts end up in summary.md)
//          ui.console(probeName, ...args) -> { code, out } (needs P.probe), ui.stage(title, sub) for no-UI tickets
//          (better: params.stage = '<title>' in the run call draws the stage before recording starts)
//          multipart files are { name, mimeType, buffer }; Buffer may be missing in the MCP VM, so pass small files as text or check typeof Buffer first
//   P      the params of the run call (base, label, sub, preset, out, plus scenario params such as credentials)
//   preset the preset name ('desktop', 'tablet', 'mobile' or 'custom'), for UI that differs per device
// Return observed facts for the dry-run gate, e.g. { skipped: true }.
async (loader) => {
  const KIND = 'flow';
  loader.__ba = { ...loader.__ba, [KIND]: async ({ page, ui, P, preset }) => {
    throw new Error('scenario body not filled in');
  } };
  return `loaded page.__ba.${KIND}`;
}
