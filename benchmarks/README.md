# Benchmarks

What a provenfix run costs (agent time, tokens, money) and what it produces (video length and size), measured from real runs. Use it to judge whether a change to the skill made runs faster, cheaper or smaller.

## How to measure a run

```sh
python3 benchmarks/collect.py \
  --session ~/.claude/projects/<project dir>/<session id>.jsonl \
  [--since <ISO time>] [--until <ISO time>] \
  --run <app>/.playwright-mcp/ba/<slug>
```

It prints JSON and changes nothing. It needs `python3` and `ffprobe`. Find the session file with `ls -t ~/.claude/projects/<project dir>/*.jsonl | head`. When a run shares a session with other work, cut it out with `--since` / `--until` (the timestamp of its first prompt).

| Field | Meaning |
|---|---|
| `wall_min` | From the prompt that loaded the skill to the last log line, idle time included |
| `agent_min` | Sum of each prompt → last assistant message or tool result of that turn. Excludes the time between turns and AskUserQuestion waits. Includes waits on permission prompts, which the log can't separate |
| `human_prompts` | Prompts the user typed (tool results and slash-command echoes excluded) |
| `api_calls`, `tool_calls` | Model requests (deduplicated by message id), and tool uses by name. `playwright` = every `mcp__playwright__*` call |
| `phase_first_call_s` | Seconds from the skill prompt to the first call of each pipeline script |
| `skill_files_read` | `references/…`, `templates/…` and `examples/…` paths the agent opened with Read or named in a Bash command (it often reads with `cat` and copies with `cp`): checks that each "read it when" trigger fired only when it should (D21) |
| `tokens` | Main-thread usage, summed over requests: `input_tokens` (uncached), `cache_creation_input_tokens` (written to cache), `cache_read_input_tokens` (re-read from cache), `output_tokens` |
| `tokens_total` | All four added up: everything the model read and wrote in the run |
| `context_first`, `context_peak` | Context size of the first request and of the largest one. A run that starts in a session with earlier work has a large `context_first` |
| `skill_load_tokens` | Context growth from the request that called the skill to the next one: SKILL.md plus the agent's text on that turn (about ±1k noise) |
| `cost_est_usd` | Main-thread usage at Opus 5.5 rates. The estimate is 5–10% under Claude Code's own `cost_usd`, which also bills side calls. `cost_usd` is filled only when the log has a `cost-state` line |
| `videos[]` | Per file: codec, resolution, duration, size, average bitrate |

Raw JSON of each run goes in `local/benchmarks/` (gitignored): private runs name client paths.

## Baseline, 2026-11-20 → 21

All on Hyprland/Wayland, Opus 5.5, effort high, desktop preset 1440×900 unless noted. "Private app" is the real project testbed (React Router, Postgres), not named here.

**Read these as upper bounds.** Every one of these sessions also worked on the skill itself: fixes were made mid-run, the harness was re-copied, and the private-app run 1 went through three recorded versions over a night. A clean run measured after Milestone 2 is the real baseline.

### Sessions

| Run | Mode | Wall | Agent | Prompts | API calls | Playwright | Bash | Output tok | Cache read | Cost |
|---|---|---|---|---|---|---|---|---|---|---|
| counter, `fix-counter-skipping-3` | before-after × desktop, tablet, mobile | 45.7 min | 11.7 min | 7 | 49 | 26 | 23 | 29.4k | 5.01M | ~$2.49 |
| counter, `verify-load-once` | AFTER only, mobile (harness check) | 11.4 min | 5.7 min | 7 | 23 | 4 | 11 | 11.0k | 1.97M | $1.41 |
| notes-api, `viewer-cannot-delete-notes` | before-after + backend proof | 31.3 min | 16.4 min | 5 | 54 | 14 | 30 | 22.1k | 5.75M | $2.66 |
| private app, run 1 (UI role checks) | before-after, 3 versions after 2 user corrections | 604 min | 31.2 min | 8 | 88 | 21 | 69 | 62.8k | 12.19M | ~$6.60 |
| private app, run 2 (same fix, backend proof) | before-after + probes | 39.7 min | 12.2 min | 2 | 42 | 6 | 29 | 25.3k | 4.83M | ~$2.41 |

`~` = estimated from tokens.

### Pipeline timeline (seconds after the skill prompt)

| Run | resolve | provision | postprocess | teardown |
|---|---|---|---|---|
| counter, 3 presets | 34 | 58 | 154 | 166 |
| counter, harness check | 37 | 77 | 458 | 480 |
| notes-api | 17 | 59 | 347 | 347 |
| private app, run 2 | 30 | 1673 | 2130 | 2169 |

Private app run 1 is left out: the first script calls landed ~7 h in, after the three versions.

### Videos

The raw `.webm` is Playwright's screencast (VP9). The `.mp4` is the output of `postprocess.sh` (H.264, idle frames trimmed).

| Run | Side × preset | Resolution | Raw webm | Final mp4 | Trimmed | Smaller by |
|---|---|---|---|---|---|---|
| counter | before × desktop | 1440×900 | 21.0 s, 523 KB | 17.7 s, 77 KB | 3.3 s | 85% |
| counter | before × tablet | 820×1180 | 21.0 s, 464 KB | 17.7 s, 73 KB | 3.3 s | 84% |
| counter | before × mobile | 390×844 | 21.0 s, 367 KB | 17.7 s, 59 KB | 3.3 s | 84% |
| counter smoke | after × desktop | 1440×900 | 23.5 s, 563 KB | 20.0 s, 75 KB | 3.5 s | 87% |
| notes-api | before × desktop | 1440×900 | 64.7 s, 912 KB | 60.6 s, 178 KB | 4.1 s | 80% |
| notes-api | after × desktop | 1440×900 | 64.7 s, 911 KB | 60.7 s, 167 KB | 4.0 s | 82% |
| private app run 1, v3 | before / after × desktop | 1440×900 | ~14–16 MB (deleted) | 72.2 s, 1.58 MB / 73.2 s, 1.86 MB | – | ~88% |
| private app run 2 | before × desktop | 1440×900 | 94.8 s, 21.5 MB | 90.2 s, 1.71 MB | 4.6 s | 92% |
| private app run 2 | after × desktop | 1440×900 | 95.9 s, 23.2 MB | 91.0 s, 1.98 MB | 4.9 s | 91% |

Final mp4 bitrate: 22–36 kbps on the fixtures, 159–213 kbps on the private app (a real UI with more pixels changing).

### What the numbers say

- **The scripts are not the slow part.** resolve runs within 37 s of the prompt, and provision within 77 s when no human wait comes between them. Most of the time goes to writing the flow, the dry-run, and recording (provision → postprocess: 1.6–7.6 min).
- **The human is the biggest wait.** Private app run 2 spent 27 of its 40 minutes between resolve and provision, waiting on the DoD/plan screen. Run 1's 604 min wall time is mostly overnight. Agent time is the number to compare across runs.
- **Corrections cost the most.** Run 1's three versions came from two user corrections (a hand-written request label, a flow that skipped the real logout). They cost about 2.7× run 2's money (2.5× its tokens), and run 2 got it right first time.
- **Cost splits roughly evenly between cache reads and cache writes.** Cache reads are 95–98% of tokens but 31–46% of cost. Cache writes are 36–52% and output 17–24%. Every byte of SKILL.md and the reference files it loads is written once and then read on every turn, so trimming them pays twice.
- **Videos are small enough to upload anywhere.** 1.6–2.0 MB per side on a real app at ~90 s. postprocess cuts 80–92% off the raw screencast and 3–5 s of idle per side.

## Trial after D21 (progressive disclosure), 2026-11-21

Same machine and model. SKILL.md 17.0 KB (was 20.8 KB). Fresh fixture repos (`make-repo.sh /tmp/pf-*`), so discover and the first-time reset choice ran too. Counter and notes-api ran at the same time. The private app ran in the session of its morning run (warm context), cut out with `--since`.

| Run | Mode | Wall | Agent | Prompts | API calls | Playwright | Bash | Output tok | Cache write | Cache read | Cost |
|---|---|---|---|---|---|---|---|---|---|---|---|
| counter, `fix-counter-skipping-3` | before-after, desktop, UI only | 6.4 min | 2.9 min | 2 | 16 | 6 | 7 | 5.3k | 64k | 1.22M | $0.89 |
| notes-api, `viewer-delete-403` | before-after, http + data + mail + log | 6.9 min | 6.7 min | 2 | 22 | 6 | 15 | 10.0k | 83k | 1.91M | $1.24 |
| private app, MR by number | before-after, http + data, `--mr` (squash-merged) | 12.9 min | 10.8 min | 3 | 30 | 6 | 16 | 17.7k | 172k | 5.25M | ~$2.78 |

| Run | resolve | provision | postprocess | teardown |
|---|---|---|---|---|
| counter | 16 | 67 | 180 | 191 |
| notes-api | 24 | 63 | 363 | 398 |
| private app | 34 | 188 | 716 | 746 |

| Run | Side × preset | Raw webm | Final mp4 | Smaller by |
|---|---|---|---|---|
| counter | before / after × desktop | 23.5 s, 590 KB / 23.6 s, 565 KB | 20.1 s, 81 KB each | 86% |
| notes-api | before / after × desktop | 64.6 s, 1199 KB / 1145 KB | 60.4 s, 198 KB / 194 KB | 83% |
| private app | before / after × desktop | 94.5 s, 21.1 MB / 95.0 s, 23.1 MB | 90.0 s, 1.75 MB / 90.3 s, 2.04 MB | 92% / 91% |

Triggers (`skill_files_read`):
- counter: `findings.md`, `config.md`, `templates/dod.md`, `summary.md`, harness, the bundled counter example. No backend, reset or stack file.
- notes-api: the same plus `reset.md` and `backend-proofs.md`, probes template and the bundled notes-api example. No `stacks/`.
- private app: `backend-proofs.md`, `reset.md`, `stacks/react-router-7.md`, all templates. `findings.md` and `config.md` were already in context from the morning run.

What it says:
- Zero corrections: each run was the request plus one "yes" on the plan screen. The private app's third prompt answered the port rule (2. Provision): notes-api's probe server, running at the same time, held 47100, and the agent asked before moving to 47101. All three dry-run gates passed first time.
- The new scripts held on the real project: `context.sh --mr` read the MR on a self-hosted GitLab and found its issue, and `resolve.sh --mr` printed `rule=mr-squash` with the same BEFORE/AFTER the first run worked out by hand.
- Cost per run fell to $0.89 / $1.24 (baseline notes-api: $2.66, 16.4 min agent). Not like-for-like: the baseline sessions also fixed the skill mid-run.
- Cache writes fell to 64k / 83k tokens (baseline 112k / 115k): the smaller SKILL.md and the unread references are written once per session.
- **Caveat:** both fixtures are the bundled examples, and the agent recognised them and copied `examples/*/flow.js` (and the notes-api `probes.sh` / `reset.sh`). Scenario authoring is not measured here. The private-app run measures it.
- Agents read skill files with `cat` and copy them with `cp` more often than with the Read tool; `collect.py` counts both.

### Tokens

All main-thread tokens, baseline and trial. "Total" = input + cache write + cache read + output.

| Run | SKILL.md | API calls | Total | Output | Cache write | Cache read | Context first → peak | Skill load |
|---|---|---|---|---|---|---|---|---|
| counter, 3 presets (baseline) | pre-D21 | 49 | 5.15M | 29.4k | 112k | 5.01M | 63k → 142k | 5.0k |
| counter, harness check (baseline) | pre-D21 | 23 | 2.07M | 11.0k | 83k | 1.97M | 54k → 113k | 14.1k |
| notes-api (baseline) | pre-D21 | 54 | 5.88M | 22.1k | 115k | 5.75M | 62k → 146k | 7.9k |
| private app, run 1 (baseline) | pre-D21 | 88 | 12.62M | 62.8k | 363k | 12.19M | 57k → 221k | 11.6k |
| private app, run 2 (baseline) | pre-D21, 20.8 KB | 42 | 4.97M | 25.3k | 117k | 4.83M | 62k → 147k | 9.1k |
| counter (trial) | D21, 17.0 KB | 16 | 1.29M | 5.3k | 64k | 1.22M | 62k → 93k | 6.7k |
| notes-api (trial) | D21 | 22 | 2.00M | 10.0k | 83k | 1.91M | 61k → 111k | 7.8k |
| private app (trial, warm) | D21 | 30 | 5.44M | 17.7k | 172k | 5.25M | 149k → 201k | 7.0k |

Baseline sessions ran several SKILL.md versions as the skill was built; only private app run 2 used the final pre-D21 file.

- **Same project, same day:** loading the skill took 9.1k tokens before D21 and 7.0k after (−23%).
- **Total tokens follow API calls × context size.** Each request re-reads the whole context from cache, so cache reads are 95–98% of all tokens. Fewer calls (16 vs 49 on counter) and a smaller context cut totals by 3–4×. That's why trimming what every turn carries matters more than trimming output.
- **Warm sessions cost more tokens.** The private app trial started at 149k context because the morning run was still in the session: every one of its 30 calls re-read that history. Started fresh (~61k), it would have read about 2.6M fewer tokens. Start a new session per recording.
- Output stays small (5–63k): the agent writes little; it reads a lot.

## Milestone 2 E2E (Task 13), 2026-11-21

Counter fixture, desktop unless noted, SKILL.md after D21. Steps 3, 4 and 6 ran as headless `claude -p` sessions at the same time; step 5 ran interactively. Wall time of the headless runs includes the gap before each scripted reply.

| Run | Prompts | Wall | Agent | API calls | Playwright | Total tokens | Output | Cache write | Cache read | Context first → peak | Cost |
|---|---|---|---|---|---|---|---|---|---|---|---|
| walkthrough (step 5) | 2 | 5.8 min | 2.7 min | 17 | 4 | 1.39M | 5.9k | 63k | 1.32M | 61k → 93k | $0.88 |
| responsive, 3 presets (step 3) | 3 | 6.8 min | 6.4 min | 25 | 14 | 1.78M | 9.0k | 81k | 1.69M | 43k → 95k | $1.17 |
| uncommitted, R3 (step 4) | 2 | 3.0 min | 2.8 min | 16 | 6 | 1.04M | 5.4k | 65k | 0.97M | 43k → 77k | $0.82 |
| both modes (step 6) | 2 | 5.0 min | 4.5 min | 17 | 9 | 1.24M | 7.1k | 77k | 1.15M | 44k → 90k | $0.99 |

| Run | Videos | Size |
|---|---|---|
| walkthrough | 32.6 s | 122 KB |
| responsive | 6 × 20 s: desktop 1440×900, tablet 820×1180, mobile 390×844 | 66–89 KB each |
| uncommitted | 2 × 20.1 s | 86 / 88 KB |
| both | 2 × 20 s + walkthrough 40.1 s | 87 / 87 / 190 KB |

- Every run read only `findings.md` and `config.md` from `references/`: no backend, reset or stack file in a UI-only run.
- Responsive took 3 prompts by design: its request had no DoD, so the agent asked the bug slots first. Its first try ($0.49 until stopped) drafted a DoD from the commit title and diff instead; SKILL.md step 1 now says those are not a source, and the second try asked.
- Three presets cost 1.4× one preset ($1.17 vs $0.82–0.89): the scenario is written once, each extra preset is two more browser calls.
- Headless sessions start smaller (43k vs ~61k context): no interactive-session extras in the system prompt.

## Compare next time

For each new run, add a row to the tables above (or a dated section if the setup changed), and check:

1. Agent time, total tokens and cost for the same fixture went down, or the change explains why not. Compare `skill_load_tokens` when SKILL.md changed.
2. Final mp4 size per second of video stays in the same band for the same app.
3. Prompts per run: user corrections should trend to zero. Note each one and its cause.
