#!/usr/bin/env python3
"""Replays the Teo 2 brute-force sheet through WarSim and writes the sim's results as JSON (or CSV by extension).

Per row: actions, the sim's result (win, outcome, rand_index, rng, enemy_counts) and per-round state (`rounds`).
Only rows the sim reproduces are written: `exact: true` (counts, rand index and final seed all match the sheet), or,
with the gap search enabled, `exact: false` plus `gap_round`/`gap_frames` (early confirm needed). Others are dropped.
Usage: WarTeo2Export.py <sheet> <out.json|out.csv> [--no-search]
"""
import csv
import json
import sys
import WarSim
import WarTeo2Check as C


def replay(acts):
    b = WarSim.start_battle('teo2', C.REC, 0x42)
    rounds = []
    for v in acts:
        C.run_one(b, v, None)
        rounds.append(dict(action=v, enemy=b.e, player=b.p, rand_index=b.calls, seed=f'0x{b.rng:08x}'))
        if b.outcome is not None:
            break
    return b, rounds


def main():
    path, out = sys.argv[1], sys.argv[2]
    search = '--no-search' not in sys.argv
    delim = '\t' if path.endswith('.tsv') else ','
    result = []
    for f in list(csv.reader(open(path), delimiter=delim))[1:]:
        if len(f) < 6 or not f[0].strip():
            continue
        acts = [int(x) for x in f[0].split()]
        ref = [int(x) for x in f[5].split()]
        idx, rng = int(f[3]), int(f[4], 16)
        b, rounds = replay(acts)
        counts = [r['enemy'] for r in rounds]
        row = dict(actions=acts, win=b.outcome == 0, outcome=b.outcome, rand_index=b.calls, rng=f'0x{b.rng:08x}',
                   enemy_counts=counts, rounds=rounds)
        if counts == ref and b.calls == idx and b.rng == rng:
            row['exact'] = True
        else:
            g = C.find_gap(acts, idx, rng) if search and counts == ref else None
            if not g:
                print('skip', f[0], flush=True)
                continue
            row['exact'] = False
            row['gap_round'], row['gap_frames'] = g[0] + 1, g[1]
        result.append(row)
        print('ok', f[0], flush=True)
    if out.endswith('.csv'):
        with open(out, 'w', newline='') as fh:
            w = csv.writer(fh)
            w.writerow(['actions', 'exact', 'win', 'rand_index', 'rng', 'enemy_counts'])
            for r in result:
                w.writerow([' '.join(map(str, r['actions'])), r['exact'], r['win'], r['rand_index'], r['rng'],
                            ' '.join(map(str, r['enemy_counts']))])
    else:
        json.dump(result, open(out, 'w'), indent=1)


if __name__ == '__main__':
    main()
