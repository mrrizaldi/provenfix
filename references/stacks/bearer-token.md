# Bearer token in localStorage

Read this when an `http` proof targets an app that keeps its auth token in localStorage and sends it as `Authorization: Bearer <token>` (typical for SPAs talking to a separate API). The generic `ui.request` contract is in `references/backend-proofs.md`.

- Sign in through the UI first, so the token is the one a real session gets.
- Read it in the scenario: `const token = await page.evaluate(() => localStorage.getItem('<key>'))`. Find `<key>` in the app's auth code.
- Pass it per request: `ui.request('DELETE', path, { headers: { Authorization: `Bearer ${token}` }, expect: 403 })`.
- Request headers are never drawn on the panel, and Bearer values are masked anywhere they appear in a body. Never return the token as a fact.
