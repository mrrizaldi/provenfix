# Trigger check

Does the skill load when it should, and stay out of the way when it shouldn't? `evals.json` holds realistic prompts, English and Indonesian, each marked `should_trigger`. The negatives are near misses: Playwright tests, screenshots, screen and terminal recording, ffmpeg, code review, "before/after" tables.

## Run it

```sh
python3 benchmarks/triggers/run.py                    # every prompt, 3 runs each
python3 benchmarks/triggers/run.py --ids n03,p04,p11  # a subset
```

Options: `--runs`, `--workers` (default 8 in parallel), `--timeout` (seconds per run, default 90), `--model`, `--out results.json`.

Needs the `claude` CLI and this skill installed as `provenfix` (e.g. `~/.claude/skills/provenfix` linking to this checkout). It tests the installed skill, so edit the description in `SKILL.md` and run again. Each run is `claude -p "<prompt>"` in a throwaway git repo under the system temp directory, with default permissions: nothing gets approved, so nothing runs or changes. A full round is 3 runs × every prompt; on Opus 5.5 that cost about $13 for 29 prompts.

A prompt passes when it triggers in at least half its runs (should trigger) or in fewer than half (should not).

## Why not skill-creator's `run_eval.py`

It installs a temporary copy of the description under a random command name and looks only at the **first** tool call. Two things break that here:

- The real skill is installed with the same description. When Claude picks the real one, the copy counts as "not triggered".
- Session hooks (for example a "check skills first" plugin) often make Claude load another skill before this one. Stopping at the first tool call then scores a real trigger as a miss.

So this runner tests the installed skill itself and counts a trigger anywhere in Claude's first response. It also reports which skill loaded first, so a competing skill shows up.

## Results

| Date | Description | Should trigger | Should not | Notes |
|---|---|---|---|---|
| 2026-11-21 | "… Never uploads unless explicitly asked." | 15/15 (all 3/3) | 14/14 | n03 ("record my screen … i'll narrate it") triggered 1/3: borderline |
| 2026-11-21 | adds "with Claude driving the browser itself", "Not for recording the user's own screen or terminal", "Doesn't upload; leaves the files for you to attach" | p04, p05, p10, p11: 3/3 | n03, n05: 0/3 | recheck of the prompts the change could move |

When upload (D10) is built, add an upload prompt (e.g. "upload the two mp4s in ./videos to MR !318 as a comment") as should-trigger and run again.
