#!/usr/bin/env python3
"""ab_compare.py - compare benchmark.py arms request by request, text first.

    ab_compare.py <experiment dir> <armA> <armB> [<armA2> <armB2> ...]

For every request label it prints prompt tok/s, decode tok/s, drafts accepted/offered and a short hash of the
generated text, then the per-pair change of the medians.  Decode speed is only comparable between requests that
produced the SAME text: with MTP/speculative decoding the accepted-draft count follows the text (E346: #1240's
"+7.6% decode" was entirely a different text after an engine restart; the same prompt, binary and config gave
different text across starts).  Rows whose texts differ are marked "text≠".
"""
import hashlib, json, statistics as st, sys
from pathlib import Path


def rows(d: Path):
    out = {}
    for r in json.load(open(d / 'results.json')):
        e = r.get('engine') or {}
        if not r.get('label', '').startswith('tokens-') or not e.get('prompt_ms'):
            continue
        out[r['label'][7:]] = {
            'p': e['prompt_read'] / e['prompt_ms'] * 1000,
            'd': e['decode_tok_s'],
            'acc': f"{e.get('drafts_accepted')}/{e.get('drafts_offered')}",
            'h': hashlib.sha256((r.get('text') or '').encode()).hexdigest()[:6],
        }
    return out


def main():
    base = Path(sys.argv[1]); arms = sys.argv[2:]
    if len(arms) < 2 or len(arms) % 2:
        sys.exit(__doc__)
    for a, b in zip(arms[::2], arms[1::2]):
        ra, rb = rows(base / a), rows(base / b)
        print(f'== {a} vs {b}')
        for lab in sorted(set(ra) & set(rb), key=lambda s: (int(s.split('-')[0]), s)):
            x, y = ra[lab], rb[lab]
            same = 'same  ' if x['h'] == y['h'] else 'text≠ '
            print(f"  {lab:14s} {same} prompt {x['p']:7.0f} -> {y['p']:7.0f} ({(y['p']/x['p']-1)*100:+5.1f}%)   "
                  f"decode {x['d']:5.1f} -> {y['d']:5.1f} ({(y['d']/x['d']-1)*100:+5.1f}%)   acc {x['acc']} / {y['acc']}")
        for size in sorted({l.split('-')[0] for l in ra}, key=int):
            for k, name in (('p', 'prompt'), ('d', 'decode')):
                va = [v[k] for l, v in ra.items() if l.startswith(size + '-')]
                vb = [v[k] for l, v in rb.items() if l.startswith(size + '-')]
                if va and vb:
                    print(f"  median {size:>6} {name:6s}: {st.median(va):7.1f} -> {st.median(vb):7.1f} "
                          f"({(st.median(vb)/st.median(va)-1)*100:+.1f}%)")


if __name__ == '__main__':
    main()
