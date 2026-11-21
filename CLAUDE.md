# before-after

Claude Code skill (to be published on the owner's GitHub) that records a BEFORE and an AFTER browser video of a feature or bug fix with Playwright MCP, through one pipeline, and uploads them to a GitHub or GitLab issue/PR/MR only when asked.

## Where we are

- Built per `docs/superpowers/plans/2026-11-20-before-after.md`. `docs/design.md` = decisions (why); the spec = contract (what); `SKILL.md` = the pipeline the agent runs.
- Milestone 1 done: the counter demo runs end to end and a first real project run passed. Milestone 2 in progress: scenario/harness split, README, CI, manual runs for uncommitted, walkthrough and both modes.
- `bash tests/run-all.sh` runs every script test. CI runs it on ubuntu and macOS (bash 3.2).
- `templates/` holds the recording harness (loaded once per MCP browser; each phase is a one-line call) and the scenario files.
- Next: upload (D10) as its own spec (GitHub, GitLab, S3-compatible).

## Ground rules

- Recording uses Playwright's native screencast only. No wf-recorder, x11grab or OBS. It must behave the same on Hyprland, Cinnamon X11, headless and CI.
- Upload is never automatic. It runs only when the user explicitly asks.
- Nothing from a client project goes into git. App-specific trial material lives in `local/` (gitignored). The repo will be public.
- Read `references/findings.md` before touching the recording flow. Each item there cost a failed run.

Machine notes and the private test project live in `CLAUDE.local.md` (gitignored).
