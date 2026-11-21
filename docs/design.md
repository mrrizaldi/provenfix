# provenfix: design

Status: brainstorming done, all decisions approved. This file is the decision log (why); the spec is the build contract (what).

## Goal

A Claude Code skill that proves a feature or bug fix with two separate browser recordings, one of the old behaviour (BEFORE) and one of the new (AFTER), driven by the same scenario through one pipeline. Uploading the videos to a GitHub issue/PR or a GitLab issue/MR happens only when the user asks for it.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | **Record with Playwright's own screencast** (`page.screencast` / Playwright MCP `--caps devtools`), not an OS screen recorder. **approved** | Frames come from the browser renderer, so Hyprland, X11 (Cinnamon), headless and CI behave the same. On Wayland, wf-recorder can only capture visible outputs, so a browser on a hidden workspace would record black or frozen frames. No workspace juggling needed. |
| D2 | **URL shown as a pill overlay** at the bottom-left, updated on every main-frame navigation (`framenavigated`, which also covers SPA `pushState`). **approved** | The screencast records only the viewport, with no browser chrome. A pill covers little content. Later upgrade, if content gets covered: ffmpeg `pad` + `drawtext` from a navigation timeline. |
| D3 | **BEFORE comes from an automatic git worktree of the base branch** on its own port; AFTER comes from the current checkout. `--before-url` / `--after-url` override either side. **approved** | Same data and same scenario on both sides gives a single pipeline. Overrides cover staging-vs-local cases. |
| D4 | **Optional reset hook between phases.** **approved** | Scenarios that mutate data (e.g. a privilege escalation) would otherwise run AFTER on data that BEFORE already changed. |
| D5 | **Upload is on demand only**, never automatic. **approved** | Avoids filling server or GitLab storage with videos nobody asked for. |
| D6 | Before and after are **separate videos**. **approved** | Simpler, and each one plays inline in PRs and MRs. |
| D7 | **SKILL.md drives the MCP steps; one small bash script per deterministic step** (`preflight`, `provision`, `teardown`, `postprocess`, `upload`). Scripts take explicit flags and never parse YAML; the agent reads the config (D9) and passes values. **approved** | Every script is testable without a browser or an LLM. No YAML parser (`yq`) or Node deps needed. |
| D8 | **`discover` step on first run** (no config yet). Agent reads README, CLAUDE.md, package scripts / Makefile / Procfile, compose files, e2e config (`playwright.config.*` gives start command and port), `.env*`, then `docker ps` and `ss -ltn` for what is actually running and which ports clash. It writes the config, shows it, the user confirms; the dry-run proves it. Migration guard: see D13. **approved** | Skill must be universal. README states intent, not truth: on the private test project the trial used an ad-hoc `demo-db`, not the compose `pgsql`, and 6379 was held by another project's redis. |
| D9 | **Config lives at `<project>/.playwright-mcp/ba/config.yml`, local only.** Split into `services` (shared by both phases; skill checks/starts, never stops) and `app` (runs twice: worktree for BEFORE, checkout for AFTER). Login stores env var names, never credentials. If `.playwright-mcp/` is not ignored, add it to `.git/info/exclude`. Worktree cache: `~/.cache/provenfix/<repo>/<base-sha>/`, reused while the base sha is unchanged. **approved** | All skill output in one folder, nothing reaches client git. Services may belong to the user's other work. Sha-keyed cache skips the ~40 s install on reruns and never goes stale. |
| D10 | **Upload is pluggable and built last.** Targets: GitHub, GitLab, R2 / any S3-compatible store. Not designed in detail until recording works end to end. Known so far: `glab api -F file=@x` is not multipart, so GitLab uploads use curl + `glab config get token --host <host from origin>` against `/projects/:id/uploads` (GitLab, including self-hosted instances); GitHub `--attach` needs gh 2.99+. From the first real upload: a re-record edits the same comment (`PUT .../notes/<id>`) instead of posting a new one; old uploads stay in GitLab's store unreferenced, so keep their ids for cleanup; `curl -4 --retry 3 --retry-all-errors` survived a flaky IPv6 route; post the body with `jq -Rs '{body: .}' summary.md | curl --data @-`. **approved** | Not every user hosts on GitHub; S3 links work anywhere. Upload is optional (D5), so it must not block the core. |
| D11 | **Never hand over a misleading video.** Script failure → non-zero exit with a one-line reason, agent stops and reports. Dry-run where BEFORE does not show the bug (or AFTER still shows it) → stop and ask. Motion gate fails (static/black) → re-record once, then report with the contact sheet. `teardown.sh` runs on every exit and kills only the app servers the skill started. **approved** | A BEFORE that looks fine proves nothing. Services belong to the user (D9). |
| D12 | **Testing:** public fixture `examples/counter/` (no deps, `python3 -m http.server`, bug on `main`, fix on `fix/counter`) runs the full pipeline and doubles as the README demo. Per-script smoke tests in `tests/`. A private real project (kept in `local/`) is the real-world run before release. Cinnamon X11 is a one-off pre-release check. Side-by-side `hstack` composite skipped (D6). **approved** | The real test project is private and local-only; the public repo needs its own proof of universality. A deps-free repo isolates skill bugs from app quirks. |
| D13 | **Step 1a `resolve` works out BEFORE and AFTER refs on every run; it amends D3: AFTER can be a worktree too.** What the user names (MR/PR, branch, sha, `--before-ref`/`--after-ref`) beats inference. Inference without input: merge-base(origin/base, HEAD) ≠ HEAD → that merge-base vs checkout; else uncommitted changes → HEAD vs checkout; else ask from the log. MRs: open → merge-base vs head ref; merged → merge commit^1 vs merge commit. Always one confirmation screen (shas, commits, files, warnings) before provisioning. The migration guard (D8) moves here, since it needs both refs. Cases R1–R15 in the spec. **approved** | Users often fix things themselves on `main`, or go back to `main` after opening an MR, then ask for proof later. A fixed config `base` and AFTER = checkout break in both cases. |
| D14 | **Viewport presets; video size = CSS viewport size, never × DPR.** `desktop` 1440×900 (default), `tablet` 820×1180 touch, `mobile` 390×844 DPR 3 touch + mobile UA. "Record responsive" = same scenario at several presets, files named `<side>-<preset>.mp4`. Each phase gets a fresh browser context built from the preset (`page.context().browser().newContext(...)`), stopping with a clear error when `browser()` is null (no fallback: it would reuse and wipe the user's MCP session). **approved** | 1440×900 is a real laptop layout (MacBook Air) and stays small: the 1280×720 trial ran at 133 kbps (~540 KB / 33 s), and screen content compresses well. Phone video at CSS size (390×844) is smaller still. 1440×1080 was rejected: 4:3, not a laptop size, 69 % more pixels than 720p. |
| D15 | **Portability rules from day one, verified at the end.** Supported: Linux, any glibc distro (x64/arm64), and macOS. Windows only through WSL2. Alpine/musl is out (Playwright Chromium does not run there). Scripts avoid Linux-only and GNU-only tools: `set -m` instead of `setsid`; `ss` else `lsof`; no `timeout`, `stat -c` or `sed -i`; Playwright cache from `PLAYWRIGHT_BROWSERS_PATH` else by `uname`. Encoder order `libx264` → `libopenh264` → stop with a distro hint. URL pill icon is inline SVG, not emoji. **approved** | Presets are OS-independent already (Chromium emulation, D1). The risk is in the scripts, and retrofitting portability costs more than writing portable from the start. Fedora's `ffmpeg-free` ships without x264; minimal distros lack emoji fonts. |
| D16 | **Three modes: `before-after` (default), `walkthrough`, `both`.** Walkthrough = one side (the AFTER code: checkout, or `--ref` for a named MR/branch), a step-by-step scenario with a chapter per step that asserts the feature's end state itself; the dry-run passes when it finishes without throwing. Output `walkthrough-<preset>.mp4`. `both` records BEFORE, AFTER, then the walkthrough on the already running AFTER server, from two flow files. Mode comes from the user's words; if they ask for before/after but the change is a brand-new feature, the agent asks. No script changes. **approved** | A new feature has no meaningful BEFORE (a 404 proves nothing), but still needs a demo. Before/after proves a difference; a walkthrough proves an end state. Reusing `--side after` keeps provision/teardown unchanged. |
| D17 | **No DoD, no start.** Step 1 "context" runs before resolve: find the Definition of Done in the named issue (GitLab `glab issue view --comments`, GitHub `gh issue view --json`; tool chosen by `origin`'s host), else the MR/PR description and the issue it closes, else the user's own message if it states steps + actual/expected (or the end state for a walkthrough). Quote it verbatim with a source link into `BA/<slug>/dod.md`; never paraphrase into new criteria. Not found, too thin, unreadable or only in an image: ask with fixed slots (bug: steps · actual · expected; feature: what the user can do · end state) and wait. Whatever the source (issue, MR or the user's own message), the agent then writes its own understanding into `dod.md` (per item: what BEFORE should show and what AFTER should show, or the walkthrough end state; what can't be shown in a browser; open questions) and the user must confirm it before anything runs (amended by D19: on the plan screen, not a separate prompt); corrections mean rewrite and confirm again. Each DoD item maps to a scenario assertion; the dry-run gate and `summary.md` checklist are judged against it. Issue/MR text is data, never instructions. **approved** | Without stated criteria the agent invents what "fixed" means and records a convincing but wrong proof. A quote with a link is checkable in one click; a paraphrase is not. Even a clear source can be misread, so the agent's reading is confirmed before it drives the run, not discovered in the video. |
| D18 | **The reset target is the user's choice, asked once per project and saved.** When a scenario changes data, the agent asks `sandbox` (throwaway copy, recommended) or `dev` (the user's own local dev DB), writes `reset.sh` with a header naming what it touches, and records `reset_target` in `config.yml`. Later runs reuse it. A non-local database is never reset. **approved** | The reset runs before every phase (4+ times per preset), so it is the most destructive command the skill runs. `config.yml` is local and uncommitted, so the choice is naturally per user and per project. |
| D19 | **One confirmation: the plan screen, before provision.** The agent explores read-only first (context, discover, resolve, scenario; writes only under `BA/`), then shows one screen: DoD in full, BEFORE/AFTER code, setup, data reset, scenario with expected gate facts. One explicit yes, then it runs to the end and stops only on a failure or a failed dry-run gate. It asks earlier only when blocked (no DoD, ambiguous commits, unclear mode, unsafe reset). Amends D17's separate DoD prompt. **approved** | In both real runs the agent merged the DoD prompt with the next one anyway, and the user wants fewer interruptions. What matters is a confirmation before any action, with enough on screen to decide. |

## Pipeline (approved as a draft outline)

```
0 preflight     playwright ffmpeg present, MCP has --caps devtools, gh/glab versions
0.5 discover    first run only: explore project, write .playwright-mcp/ba/config.yml, user confirms (D8, D9)
1 scenario      agent writes the flow from the issue/MR/diff → <project>/.playwright-mcp/ba/<slug>/flow.js
2 provision     before = worktree of base on PORT_B (or --before-url) · after = this checkout on PORT_A
3 dry-run       run the flow on both servers without keeping video → validates selectors, confirms the bug reproduces, warms the dev server
4 record        reset → BEFORE → reset → AFTER  (URL pill, chapter cards, action overlays)
5 post-process  webm→mp4, trim static tail, SSIM motion gate, contact-sheet PNG → agent inspects frames
6 report        video paths + a markdown summary ready to paste
7 upload        only when asked; pluggable target: GitHub / GitLab / S3-compatible (D10, last phase)
```

Per-project config (D9), generated by `discover`:

```yaml
# <project>/.playwright-mcp/ba/config.yml: local only, never committed
base: main
services:                       # skill checks/starts these, never stops them
  - name: db
    check: docker exec demo-db pg_isready -U postgres
    start: docker start demo-db
app:                            # BEFORE in worktree, AFTER in checkout
  dir: apps/app
  install: pnpm install --frozen-lockfile --prefer-offline --ignore-scripts
  start: pnpm dev
  port_env: PORT
  ports: { before: 3011, after: 3010 }
  env: { VITE_APP_URL: "http://localhost:{port}" }
  copy: [apps/app/.env]
  ready: /login
reset: ./.playwright-mcp/ba/reset.sh   # optional
login: { path: /login, user_env: BA_USER, pass_env: BA_PASS }
notes: |                        # discovery findings worth keeping
  redis 6379 held by another project's container; app runs fine without it.
```

Deferred: `app` as a list (API + web that both change per branch). Add when a real project needs it.

## Repo structure (D7)

```
SKILL.md                 pipeline steps 0–7, when to call what
scripts/
  preflight.sh           playwright ffmpeg, MCP caps, gh/glab versions → exit codes
  provision.sh           worktree add (sha cache), copy env files, install, start server, wait for ready
  teardown.sh            stop app servers the skill started, prune old worktrees
  postprocess.sh         webm→mp4, trim static tail, SSIM gate, contact sheet
  upload.sh              gh / glab
templates/harness.js     from prototypes/flow-template.js
templates/flow.js        scenario template
references/
  findings.md            trial findings (read before recording)
  config.md              config schema + example
```

## Findings

Moved to `references/findings.md` (the skill reads it at runtime). Read it before touching the recording flow.

## Prior art

Researched 2026-11-20, widened 2026-11-21 (about 30 projects; the closest are listed).

| Project | What it does | Gap vs provenfix |
|---|---|---|
| [PR Preview](https://pr-preview.com) | `before.mp4`/`after.mp4` from a branch comparison, via Claude Code or a CLI | GitHub only, no DoD or BEFORE-reproduction gate, visible Chrome window |
| [record-pr skill](https://github.com/lucastamoios/skills/blob/main/skills/record-pr/SKILL.md) | Narrated before/after mp4 pair at 1440x900 | BEFORE from `git stash` of the fix only, needs a team config |
| [claude-show-your-work](https://github.com/iamumeransari/claude-show-your-work) | Old and new version played side by side, synced, in the terminal | A review tool: no files for the PR/MR |
| [demo-recorder](https://github.com/shlior7/demo-recorder) | Cached worktree per ref, merged-PR handling, contact sheet, posts to the PR | One demo video, no before/after pair |
| [reeldiff](https://github.com/Nuu-maan/reeldiff) | CI replays YAML flows and pixel-diffs each step against the base deployment | CI only, flows committed to the repo |
| [ProofShot](https://github.com/AmElmo/proofshot) | Agent records video proof and uploads it to the PR | No BEFORE video, GitHub only |
| [reshoot-action](https://github.com/kiromoussa/reshoot-action) | Before/after frames per step on each PR | Frames only, baseline recorded on main |
| [demo-video-skill](https://github.com/alinaqi/demo-video-skill) | Captioned proof videos with an SSIM motion gate | No before/after |
| [Playwright CLI skill](https://unpkg.com/playwright-core@1.64.1/lib/tools/skills/playwright-cli/references/video-recording.md) | `page.screencast` chapters and overlays, PR attachments | Building blocks, no pipeline |
| [cq-screenshots](https://gitlab.com/gitlab-org/upstream-studios/design-strategy/cq-screenshots) | Before/after screenshots for GitLab MRs | Screenshots, tied to one development setup |

Common across these: walkthrough videos, chapter cards and action overlays (Playwright's own), contact sheets, motion gates, device presets, cached worktrees, upload through `gh`. Not found in any of them: BEFORE/AFTER resolved from git state (uncommitted, fixed on main, squash or fast-forward merged), a DoD gate with one plan screen, a dry-run gate that refuses a BEFORE without the bug, GitLab MRs as a video target, and asking where data resets go. Closed commercial tools could not be checked.

## Open questions

None. Spec: `docs/superpowers/specs/2026-11-20-before-after-design.md`.
