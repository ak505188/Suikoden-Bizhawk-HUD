#!/usr/bin/env python3
"""Replays the Teo 2 brute-force sheet (CSV/TSV: Actions,Win,Time,Index,RNG,Unit Counts,...) through WarSim and checks
the enemy counts after each action, the total rand() index and the final seed.

A row that differs only in the index/seed is retried with an early confirm: the next command was confirmed while
sprites were still walking back (`Battle.gap` = frames between a round's end and the next resolver). For each round
boundary the gaps that can matter are the frame counts at which a sprite arrives, so only those are tried.

Usage: WarTeo2Check.py <sheet> [--no-search]
"""
import copy
import csv
import sys
import WarSim

REC = [0, 3, 4, 5, 7, 8, 9, 11, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 38, 39, 40,
       44, 45, 46, 48, 67, 74, 83, 90, 92]


def run_one(b, v, gap):
    """Plays a Charge unit of power v (using the Strategist first if v is a buffed power)."""
    b.gap = gap
    pick = next((g for g in b.units(0) if b.unit_power(g) == v), None)
    if pick is None:
        for g in b.units(0):
            base = b.unit_power(g)
            if b.strat == 0 and base + base // 2 == v:
                b.use_strategist(32)
                pick = g
                break
    if pick is None:
        raise ValueError('no unit for %d' % v)
    b.play(0, pick)


def run(actions):
    b = WarSim.start_battle('teo2', REC, 0x42)
    counts = []
    for v in actions:
        run_one(b, v, None)
        counts.append(b.e)
        if b.outcome is not None:
            break
    return counts, b


def find_gap(acts, idx, rng):
    for k in range(len(acts) - 1):
        base = WarSim.start_battle('teo2', REC, 0x42)
        for i in range(k):
            run_one(base, acts[i], None)
        probe = copy.deepcopy(base)
        probe.arrivals = []
        run_one(probe, acts[k], None)
        for g in sorted(set(probe.arrivals)):
            c = copy.deepcopy(base)
            run_one(c, acts[k], g)
            for i in range(k + 1, len(acts)):
                if c.outcome is not None:
                    break
                run_one(c, acts[i], None)
            if c.calls == idx and c.rng == rng:
                return k, g
    return None


def main():
    path = sys.argv[1]
    search = '--no-search' not in sys.argv
    delim = '\t' if path.endswith('.tsv') else ','
    rows = list(csv.reader(open(path), delimiter=delim))[1:]
    exact = fixed = bad = 0
    for f in rows:
        if len(f) < 6 or not f[0].strip():
            continue
        acts = [int(x) for x in f[0].split()]
        ref_counts = [int(x) for x in f[5].split()]
        idx, rng = int(f[3]), int(f[4], 16)
        counts, b = run(acts)
        if counts == ref_counts and b.calls == idx and b.rng == rng:
            exact += 1
            continue
        found = find_gap(acts, idx, rng) if search and counts == ref_counts else None
        if found:
            fixed += 1
            print('early confirm', f[0], 'after round', found[0] + 1, 'gap', found[1], flush=True)
        else:
            bad += 1
            print('DIFF', f[0], 'counts ok' if counts == ref_counts else 'counts differ',
                  'index sim', b.calls, 'ref', idx, flush=True)
    print(f'{exact} exact, {fixed} exact with an early confirm gap, {bad} differ')


if __name__ == '__main__':
    main()
