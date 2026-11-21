# React Router 7 (single fetch)

Read this when an `http` proof targets a React Router 7 app: `react-router` 7 or `@react-router/*` in package.json, or the app posts actions to `<route>.data`. The generic `ui.request` contract is in `references/backend-proofs.md`.

- Single fetch answers a `.data` request whose loader or action redirects with **202**, not 302. The real redirect (status and target) is in the turbo-stream body.
- The harness decodes it. The panel shows `202  (single-fetch redirect: 302 -> /login)`, and `expect: 302` matches it.
- The result carries `redirect: { status, to }`. Use that as the fact (e.g. `redirect: r.redirect?.to`), not `status`.
- Turbo-stream bodies are masked like JSON: secret-looking keys are hidden in the panel.
- Post actions the way the app's forms do: `form: { intent: '<action intent>', ... }` to `<route>.data`, so the panel shows the real path and encoded body.
