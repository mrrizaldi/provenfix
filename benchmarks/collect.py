#!/usr/bin/env python3
"""Measure one provenfix run: agent time, tokens, cost from the Claude Code session log,
and size/length of every video in the run directory.

  python3 benchmarks/collect.py --session ~/.claude/projects/<proj>/<id>.jsonl [--since <ISO>] [--until <ISO>] [--run <BA/slug dir>]...

Prints JSON. Needs python3 and ffprobe. Reads only; nothing is written.
"""
import argparse, glob, json, os, re, subprocess, sys
from datetime import datetime

SKILL = r'provenfix|before-after'
# ponytail: Opus 5.5 $/token (input, 1h cache write, cache read, output), 2026-11. Reads 5-10% under the
# session's own cost-state, which also bills side calls; update when the model or prices change.
PRICE = {'input_tokens': 4e-6, 'cache_creation_input_tokens': 8e-6, 'cache_read_input_tokens': 0.2e-6, 'output_tokens': 20e-6}
PHASES = ('resolve.sh', 'provision.sh', 'postprocess.sh', 'teardown.sh', 'upload.sh', 'probe.sh')


def ts(s):
    return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()


def is_human(e):
    if e.get('type') != 'user' or e.get('isMeta') or e.get('isSidechain'):
        return False
    c = e['message'].get('content')
    if isinstance(c, list):
        if any(b.get('type') == 'tool_result' for b in c):
            return False
        c = ' '.join(b.get('text', '') for b in c if b.get('type') == 'text')
    # slash-command echoes and hook output are not prompts
    return bool(c) and not c.lstrip().startswith(('<command-', '<local-command', 'Caveat:'))


def session(path, since=None, until=None):
    ev = [json.loads(l) for l in open(path)]
    ev = [e for e in ev if 'timestamp' in e and not e.get('isSidechain') and (not since or e['timestamp'] >= since) and (not until or e['timestamp'] < until)]
    ev.sort(key=lambda e: e['timestamp'])
    # measure from the prompt that loaded the skill; earlier work in the same session is not the skill's
    for k, e in enumerate(ev):
        if e.get('type') == 'assistant' and any(b.get('type') == 'tool_use' and b['name'] == 'Skill'
                                                and re.search(SKILL, json.dumps(b.get('input')))
                                                for b in e['message'].get('content') or []):
            ev = ev[max([j for j in range(k) if is_human(ev[j])], default=0):]
            break
    t = [ts(e['timestamp']) for e in ev]

    prompts = [i for i, e in enumerate(ev) if is_human(e)]
    # agent time: from each prompt to the last event before the next prompt (human think time excluded)
    # a turn ends at its last assistant message or tool result; system/attachment lines arrive while idle
    work = [i for i, e in enumerate(ev) if e.get('type') in ('assistant', 'user')]
    agent = 0.0
    for k, i in enumerate(prompts):
        nxt = prompts[k + 1] if k + 1 < len(prompts) else len(ev)
        end = max([j for j in work if i <= j < nxt], default=i)
        agent += t[end] - t[i]

    # time a question waits for its answer is the human's, not the agent's
    asked = {}
    for e in ev:
        c = (e.get('message') or {}).get('content')
        for b in c if isinstance(c, list) else []:
            if b.get('type') == 'tool_use' and b['name'] == 'AskUserQuestion':
                asked[b['id']] = ts(e['timestamp'])
            elif b.get('type') == 'tool_result' and b.get('tool_use_id') in asked:
                agent -= ts(e['timestamp']) - asked.pop(b['tool_use_id'])

    usage, tools, phases, reads = {}, {}, {}, []
    skill_msg = None
    for e in ev:
        if e.get('type') != 'assistant':
            continue
        m = e['message']
        usage[m.get('id')] = m.get('usage') or {}  # one message is split over several lines: keep one
        for b in m.get('content') or []:
            if b.get('type') != 'tool_use':
                continue
            n = b['name']
            if n == 'Skill' and skill_msg is None and re.search(SKILL, json.dumps(b.get('input'))):
                skill_msg = m.get('id')
            key = 'playwright' if n.startswith('mcp__playwright__') else n
            tools[key] = tools.get(key, 0) + 1
            cmd = (b.get('input') or {}).get('command', '')
            # skill files the run pulled in (D21): agents read them with Read, or with cat / cp in Bash
            text = (b.get('input') or {}).get('file_path', '') if n == 'Read' else cmd if n == 'Bash' else ''
            for f in re.findall(r'(?<![\w.-])((?:references|templates|examples)/[\w./-]*\.\w+)', text):
                if f not in reads:
                    reads.append(f)
            for p in PHASES:
                if p in cmd and p not in phases:
                    phases[p] = round(ts(e['timestamp']) - t[prompts[0]] if prompts else 0)
    tok = {k: sum(u.get(k, 0) for u in usage.values())
           for k in ('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens', 'output_tokens')}
    # context per request = everything the model read for it; requests are in call order
    ctx = [u.get('input_tokens', 0) + u.get('cache_creation_input_tokens', 0) + u.get('cache_read_input_tokens', 0)
           for u in usage.values()]
    ids = list(usage)
    k = ids.index(skill_msg) if skill_msg in ids else -1
    # what loading SKILL.md added: context of the request after the Skill call minus the one that made it
    skill_load = ctx[k + 1] - ctx[k] if 0 <= k < len(ctx) - 1 else None

    cost = [e for e in ev if e.get('type') == 'cost-state'] or \
           [json.loads(l) for l in open(path) if '"cost-state"' in l]  # cost-state lines may lack a timestamp
    cost = cost[-1] if cost and not (since or until) else {}  # cost-state is a session total: no use for a --since window
    return {
        'session': os.path.basename(path),
        'start': ev[0]['timestamp'] if ev else None,
        'wall_min': round((t[-1] - t[0]) / 60, 1) if t else 0,
        'agent_min': round(agent / 60, 1),
        'human_prompts': len(prompts),
        'api_calls': len(usage),
        'tool_calls': tools,
        'phase_first_call_s': phases,
        'skill_files_read': reads,  # seconds after the first prompt
        'tokens': tok,
        'tokens_total': sum(tok.values()),
        'context_first': ctx[0] if ctx else 0,
        'context_peak': max(ctx) if ctx else 0,
        'skill_load_tokens': skill_load,
        'cost_usd': round(cost['totalCostUSD'], 2) if 'totalCostUSD' in cost else None,
        'cost_est_usd': round(sum(tok[k] * PRICE[k] for k in tok), 2),
        'api_min': round(cost['totalAPIDuration'] / 60000, 1) if 'totalAPIDuration' in cost else None,
        'tool_min': round(cost['totalToolDuration'] / 60000, 1) if 'totalToolDuration' in cost else None,
    }


def probe(f):
    out = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                          '-show_entries', 'format=duration,size:stream=width,height,codec_name',
                          '-of', 'json', f], capture_output=True, text=True).stdout
    j = json.loads(out or '{}')
    s, fm = (j.get('streams') or [{}])[0], j.get('format', {})
    dur = float(fm['duration']) if fm.get('duration') not in (None, 'N/A') else None
    size = int(fm.get('size') or os.path.getsize(f))
    return {'file': os.path.basename(f), 'codec': s.get('codec_name'), 'res': f"{s.get('width')}x{s.get('height')}",
            'dur_s': round(dur, 1) if dur else None, 'size_kb': round(size / 1024),
            'kbps': round(size * 8 / dur / 1000) if dur else None}


def run(d):
    vids = sorted(glob.glob(os.path.join(d, '*.mp4')) + glob.glob(os.path.join(d, '*.webm')))
    return {'dir': os.path.basename(os.path.normpath(d)), 'videos': [probe(v) for v in vids]}


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--session')
    ap.add_argument('--run', action='append', default=[])
    ap.add_argument('--since', help='ISO time: measure only from here (a run inside a longer session)')
    ap.add_argument('--until', help='ISO time: measure only up to here')
    a = ap.parse_args()
    if not a.session and not a.run:
        ap.error('give --session and/or --run')
    json.dump({'session': session(a.session, a.since, a.until) if a.session else None, 'runs': [run(d) for d in a.run]},
              sys.stdout, indent=1)
    print()
