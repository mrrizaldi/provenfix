#!/usr/bin/env python3
"""Does the installed provenfix skill trigger on each prompt in evals.json?

  python3 benchmarks/triggers/run.py [--ids p01,n03] [--runs 3] [--workers 8] [--model <id>] [--out results.json]

Each run is `claude -p "<prompt>"` in a throwaway git repo with default permissions (nothing gets
approved, so nothing runs or changes). A run counts as triggered when Claude loads provenfix anywhere
in its first response: a Skill call naming it, or a Read of its SKILL.md. See README.md for why this
is not skill-creator's detection. Needs the claude CLI and the skill installed as `provenfix`.
"""
import argparse, collections, json, os, re, subprocess, tempfile, time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
HIT = re.compile(r'provenfix')


def once(query, workdir, timeout, model):
    cmd = ['claude', '-p', query, '--output-format', 'stream-json', '--verbose', '--permission-mode', 'default']
    if model:
        cmd += ['--model', model]
    env = {k: v for k, v in os.environ.items() if k != 'CLAUDECODE'}  # allow running from inside Claude Code
    p = subprocess.Popen(cmd, cwd=workdir, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    t0, first_skill, triggered = time.time(), None, False
    try:
        for line in p.stdout:
            if time.time() - t0 > timeout:
                break
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if e.get('type') == 'assistant':
                for b in e['message'].get('content') or []:
                    if b.get('type') != 'tool_use':
                        continue
                    inp = json.dumps(b.get('input') or {})
                    if b['name'] == 'Skill' and first_skill is None:
                        first_skill = (b.get('input') or {}).get('skill')
                    if (b['name'] == 'Skill' and HIT.search(inp)) or (b['name'] == 'Read' and 'provenfix/SKILL.md' in inp):
                        triggered = True
                if triggered:
                    break
            if e.get('type') == 'result':
                break
    finally:
        if p.poll() is None:
            p.kill()
        p.wait()
    return triggered, first_skill


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ids', help='comma-separated prompt ids (default: all)')
    ap.add_argument('--runs', type=int, default=3)
    ap.add_argument('--workers', type=int, default=8)
    ap.add_argument('--timeout', type=int, default=90, help='seconds per run')
    ap.add_argument('--model', help="model id for claude -p (default: the user's)")
    ap.add_argument('--out', help='write per-run results as JSON here')
    a = ap.parse_args()
    evals = json.load(open(os.path.join(HERE, 'evals.json')))
    if a.ids:
        want = set(a.ids.split(','))
        evals = [e for e in evals if e['id'] in want]
    jobs = [(e, n) for e in evals for n in range(a.runs)]
    with tempfile.TemporaryDirectory(prefix='provenfix-triggers-', ignore_cleanup_errors=True) as workdir:
        subprocess.run(['git', 'init', '-q', workdir], check=True)
        with ThreadPoolExecutor(a.workers) as ex:
            res = list(ex.map(lambda j: (j[0]['id'], *once(j[0]['query'], workdir, a.timeout, a.model)), jobs))
    if a.out:
        json.dump([{'id': i, 'triggered': t, 'first_skill': f} for i, t, f in res], open(a.out, 'w'), indent=1)
    hits, firsts = collections.Counter(), collections.defaultdict(collections.Counter)
    for i, t, f in res:
        hits[i] += t
        firsts[i][f] += 1
    good = 0
    for e in evals:
        rate = hits[e['id']] / a.runs
        ok = (rate >= 0.5) == e['should_trigger']
        good += ok
        print(f"{e['id']}  {'should    ' if e['should_trigger'] else 'should not'}  {e['lang']}  "
              f"{hits[e['id']]}/{a.runs}  {'ok  ' if ok else 'MISS'}  first skill: {dict(firsts[e['id']])}  {e['query'][:60]}")
    print(f'{good}/{len(evals)} prompts on the right side (threshold 50% of runs)')


if __name__ == '__main__':
    main()
