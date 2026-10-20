# E449: time breakdowns -> data.json (prompt: "strata prefill timing" request lines; decode: DECODE_TIMING totals from
# the t arms, GPU-stage shares from the v arms).  Usage: python3 parse.py [arm-dir ...]
import json, os, re, statistics as st, sys

E = os.path.dirname(os.path.abspath(__file__))
PT = (4096, 32768, 128000)
PROMPT_CAT = {   # 6 groups, in stack order
    'hc read': ['hc read'],
    'GDN': ['gdn', 'gdn conv+gates', 'gdn recurrence', 'gdn out proj'],
    'QSA proj': ['qsa proj'],
    'QSA select+attn': ['qsa indexer', 'qsa select', 'qsa attn'],
    'experts': ['router+shared', 'host grouping', 'gather', 'dequant', 'gemm gate/up', 'gemm down', 'combine'],
    'other': ['embed+steps', 'wait copy', 'ple', 'kv stage'],
}
DEC_CAT = {
    'hc read': ['hc-read0', 'hc-read1+router', 'router+plan+bell', 'hc0 norm', 'hc0 down', 'hc0 up', 'hc1 norm', 'hc1 down', 'hc1 up'],
    'dense GEMV': ['q8+qkv/q-idx gemv', 'z', 'out-proj', 'q8+kv-idx', 'k/v+norm-rope', 'q+q-idx', 'gate', 'shared+quant',
                   'head'],
    'attn + GDN rec': ['conv', 'ab', 'rec', 'kv+idx append', 'scores+topk', 'kv-resolve', 'attention'],
    'routed experts': ['VRAM hits', 'copy+combine', 'PCIe grp'],
    'waits': ['waitA', 'waitB', 'waitCPU', '(gap)'],
    'draft + commit': [],   # host side, from the v arm's decode timing line
}


def log(a):
    return open(f'{E}/{a}/engine.log', errors='replace').read().splitlines()


def prompt(a):   # per request: card 0's whole-prompt line + card 1's chunk lines (pipelined), phases summed
    lines = []
    for l in log(a):
        m = re.match(r'strata prefill timing: (\d+) tokens, GPU timeline (\d+) ms, wall (\d+) ms.*?: (.*)', l)
        if m:
            parts = dict((k.strip(), float(v)) for k, v in re.findall(r'([a-z+/ ]+?) (\d+) \([\d.]+%\)', m[4]))
            lines.append((int(m[1]), int(m[2]), parts))
    reqs, g0, g1 = [], None, []
    for n, gpu, parts in lines:
        is_whole = any(abs(n - t) <= 0.01 * t for t in PT) and (g0 is None) and (n > 8192 or not g1)
        if is_whole:
            g0 = (n, gpu, parts)
        else:
            g1.append((n, gpu, parts))
        if g0 and sum(x[0] for x in g1) == g0[0]:
            reqs.append((g0, g1)); g0, g1 = None, []
    ttft = {}
    for r in json.load(open(f'{E}/{a}/results.json')):
        t = r.get('expected_prompt_tokens')
        if t in PT:
            ttft.setdefault(t, []).append(r['client_ttft_s'] * 1000)
    by = {t: [] for t in PT}
    for g0, g1 in reqs:
        t = next(t for t in PT if abs(g0[0] - t) <= 0.01 * t)
        tot = {}
        for _, _, p in [g0] + g1:
            for k, v in p.items():
                tot[k] = tot.get(k, 0) + v
        g = {c: sum(tot.get(k, 0) for k in ks) for c, ks in PROMPT_CAT.items()}
        g['_unassigned'] = sum(tot.values()) - sum(g.values())
        g['_gpu0'] = g0[1]; g['_gpu1'] = sum(x[1] for x in g1); g['_tokens'] = g0[0]
        g['_ttft'] = ttft[t][len(by[t])] if len(ttft.get(t, [])) > len(by[t]) else None
        by[t].append(g)
    return by


def timing(a):   # decode timing lines with >= 60 windows, in request order
    out = []
    for l in log(a):
        m = re.match(r'strata decode timing: (\d+) windows, avg T [\d.]+, ([\d.]+) tokens/window, ([\d.]+) ms/window = '
                     r'verify ([\d.]+).*?\+ commit/emit ([\d.]+) \+ draft ([\d.]+)', l)
        if m and int(m[1]) >= 60:
            out.append(dict(win=float(m[3]), tpw=float(m[2]), commit=float(m[5]), draft=float(m[6]),
                            ms_tok=float(m[3]) / float(m[2])))
    return out


def stages(a):   # per request: stage 0 + stage 1 GPU ms/window per category
    lines = [l for l in log(a) if l.startswith('strata decode GPU stages')]
    reqs, cur = [], None
    for l in lines:
        body = l.split(':', 1)[1].split('| total')[0]
        d = {}
        for k, v in re.findall(r'([A-Za-z0-9+/()\- ]+?) ([\d.]+)(?= |$)', body.replace('|', ' ')):
            k = k.strip().split(': ')[-1]
            if k.startswith('total') or k.endswith('layers'):
                continue
            d[k] = d.get(k, 0) + float(v)
        nwin = int(re.search(r'over (\d+) windows', l)[1])
        if 'stage 1' not in l:
            cur = dict(d=d, n=nwin); reqs.append(cur)
        else:
            for k, v in d.items():
                cur['d'][k] = cur['d'].get(k, 0) + v
    return [r for r in reqs if r['n'] >= 60]


def main(arms):
    res = {}
    for a in arms:
        if not os.path.exists(f'{E}/{a}/engine.log'):
            continue
        r = {}
        if '-t' in a:
            r['prompt'] = prompt(a)
            r['decode'] = timing(a)
        if '-v' in a:
            tt = timing(a)
            rs = stages(a)
            r['stages'] = []
            for i, q in enumerate(rs):
                g = {c: sum(q['d'].get(k, 0) for k in ks) for c, ks in DEC_CAT.items()}
                if i < len(tt):
                    g['draft + commit'] = tt[i]['draft'] + tt[i]['commit']
                g['_unassigned'] = sum(q['d'].values()) - sum(v for c, v in g.items() if c not in ('_unassigned',
                                                                                                     'draft + commit'))
                known = {k for ks in DEC_CAT.values() for k in ks}
                g['_keys'] = sorted(k for k in q['d'] if k not in known)
                r['stages'].append(g)
            r['decode'] = tt
        res[a] = r
    json.dump(res, open(f'{E}/data.json', 'w'), indent=1)
    for a, r in res.items():
        print('==', a)
        for t, L in r.get('prompt', {}).items():
            if L:
                print(f'  prompt {t}: n={len(L)} card0 {[x["_gpu0"] for x in L]} card1 {[round(x["_gpu1"]) for x in L]} '
                      f'ttft {[round(x["_ttft"]) for x in L]} unassigned {[round(x["_unassigned"]) for x in L]}')
        for d in r.get('decode', []):
            print(f'  decode win {d["win"]:.2f} ms  tok/win {d["tpw"]:.2f}  ms/tok {d["ms_tok"]:.2f}')
        for s in r.get('stages', []):
            print('  stages', {k: round(v, 2) for k, v in s.items() if k != '_keys'})


if __name__ == '__main__':
    main(sys.argv[1:] or ['s-t1', 'p-t1', 's-v', 'p-v', 'p-t2', 's-t2', 's-v128', 'p-v128'])
