# provenfix

A Claude Code skill that proves a bug fix or feature with browser videos: **BEFORE** (old code) and **AFTER** (new code) from the same scenario, or a step-by-step **walkthrough** of a new feature. Recorded with Playwright's own screencast, so it behaves the same on Wayland, X11, macOS and headless machines.

- Works out what BEFORE and AFTER are: your branch, uncommitted edits, a fix committed straight on `main`, or an MR/PR you opened earlier.
- Starts the old code in a cached git worktree (`~/.cache/provenfix/`), leaving your checkout alone, and drives both through one scenario.
- Refuses to hand over a BEFORE video that doesn't show the bug.
- Desktop (1440x900) by default; tablet, mobile or all three ("responsive") on request.
- Small H.264 mp4s plus contact sheets and a paste-ready summary.

## What's different

Recording a before/after video pair for a PR is not new: [PR Preview](https://pr-preview.com) and a few Claude Code skills already do it. provenfix is about making sure the video proves the right thing. A survey of about 30 similar tools (November 2026, listed under [Prior art](docs/design.md#prior-art)) found none of these:

1. BEFORE and AFTER come from git state. Uncommitted edits, a fix committed straight on `main`, a squash or fast-forward merged MR: each resolves to the right pair of commits, and an unclear case is asked, never guessed. The other tools stash the fix, check out the base branch, or take a URL you type.
2. No Definition of Done, no start. The criteria come from the issue, the MR or your own words, and all of it (criteria, commits, setup, data reset, scenario) is confirmed on one plan screen before anything runs.
3. A BEFORE that doesn't show the bug is refused. A dry run checks that BEFORE fails the criteria and AFTER meets them; otherwise nothing is recorded. The closest tool only checks that the new feature works.
4. GitLab MRs are a full target, not only GitHub PRs. The one GitLab tool in the survey takes screenshots.
5. Your data stays your call. When the scenario changes data, provenfix asks once whether resets hit a sandbox copy or your local dev database, and never resets a database that isn't on your machine.

## How a run goes

1. Claude finds the Definition of Done (DoD): in the issue or MR/PR you name, or in your own words. No DoD, no start: it asks for steps, what happens now and what should happen.
2. It explores read-only, then shows one plan screen: the DoD, the BEFORE/AFTER code, the setup, the data reset and the scenario. Nothing starts until you say yes.
3. After the yes it runs to the end and stops only if a step fails or the dry-run shows BEFORE does not have the bug.

## Requirements

- Claude Code with Playwright MCP: `claude mcp add playwright -s user -- npx @playwright/mcp@latest`
- Playwright's ffmpeg, matching the MCP's Playwright version: `npx -y playwright@$(npm view @playwright/mcp@latest dependencies.playwright) install ffmpeg`
- git, curl, ffmpeg/ffprobe with an H.264 encoder (Fedora: ffmpeg from RPM Fusion; macOS: `brew install ffmpeg`)
- Linux (any glibc distro) or macOS. Windows through WSL2 should work but is untested.
- The bundled demo also needs `python3` (it serves the page with `python3 -m http.server`).

## Install

```bash
git clone https://github.com/mrrizaldi/provenfix ~/.claude/skills/provenfix
```

## Use

In your project, ask Claude things like:

- "record before/after for this fix"
- "make a proof video for MR !42"
- "record the counter fix on mobile" / "...responsive"
- "make a walkthrough video of the new export feature"

The first run explores the project (how it starts, databases, ports) and puts a local config, `.playwright-mcp/ba/config.yml`, on the plan screen. It is never committed.

Try it on the bundled demo: `examples/counter/make-repo.sh /tmp/counter`, open Claude Code in `/tmp/counter`, and ask for before/after of `fix/counter`.

Backend fixes get proven the same way: requests and their real responses, plus live output of named checks (a DB count, a mail outbox, a log grep), are shown as panels in the video. A ticket with no UI records on a plain stage page. Demo: `examples/notes-api/make-repo.sh /tmp/notes-api`, then ask for before/after of `fix/notes-auth`.

## Good to know

- Each phase records in its own headless Chrome, so videos are exactly the viewport size on any window manager. The Chrome window Playwright MCP opens (headed by default) stays blank during a run. To hide it, add `--headless` to the MCP command (optional).
- If the scenario changes data, Claude asks once per project whether resets hit a sandbox copy or your local dev database, and saves the answer in `.playwright-mcp/ba/config.yml`. It never resets a database that is not on your machine.
- Credentials never land in a file: config holds env var names only, and the values are passed at run time and typed without showing in the video.
- Upload is not built yet. The mp4s and summary are ready to drag into the PR/MR. Nothing is uploaded, pushed or commented unless you ask.

## Development

`bash tests/run-all.sh` runs the script tests (no browser or LLM needed). CI runs them on Ubuntu and macOS. Design: `docs/design.md`; spec: `docs/superpowers/specs/`.

## License

MIT, see `LICENSE`.
