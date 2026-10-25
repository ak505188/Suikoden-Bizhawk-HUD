# Compares scripts/CaptureAttackPaths.lua's live log against AttackTimingWalker.walk_path for
# every basic Attack in it: hit, crit, miss, counter (either side) and cover.
# For each attack (an actor's combatant_rec+0x50 becoming one of the executor's first
# continuations), checks relative to the dispatch frame:
#   - every continuation change on the attacker / target / cover ally (the chain steps, and so
#     the damage-roll frames)
#   - the frame each of them stops being busy (EnemyData+5 drops to 0 for the last time)
# Usage: python3 scripts/python/ComparePathTimings.py [-v]
import collections, json, os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import AttackTimingWalker as W

LOG = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CaptureAttackPaths.txt"
FIRST = {0x800f5960: "hit", 0x800f5abc: "crit", 0x800f5c1c: "miss", 0x800f5db4: "counter",
         0x800f5e90: "cover"}
NAMES = {v: k for k, v in W.CONT_ADDR.items()}
NAMES[0] = "-"
RUNE_PIECE_REACTION = {1: 0x8016c56c, 4: 0x8016c648}
WINDOW = 600


def parse():
    runs, cur = [], None
    for line in open(LOG):
        line = line.strip()
        if line.startswith("RUN"):
            m = re.match(r"RUN (\w+) (\d+) party=(\d+) total=(\d+)", line)
            if not m:
                continue
            cur = {"name": "%s%s" % (m.group(1), m.group(2)), "party": int(m.group(3)),
                   "total": int(m.group(4)), "who": {}, "ev": []}
            runs.append(cur)
        elif line.startswith("C ") and cur:
            m = re.match(r"C (\d+) party id=(\d+) runePiece=(-?\d+)", line)
            if m:
                cur["who"][int(m.group(1))] = ("party", int(m.group(2)), int(m.group(3)))
            m = re.match(r"C (\d+) enemy table=(0x[0-9a-f]+)", line)
            if m:
                cur["who"][int(m.group(1))] = ("enemy", m.group(2), None)
        elif line.startswith("F") and cur:
            m = re.match(r"F(\d+) (\d+) cont=([0-9a-f]+) busy=(\d+) fx=([0-9a-f]+) at=(\d+) hp=(\d+)", line)
            if m:
                cur["ev"].append((int(m.group(1)), int(m.group(2)), int(m.group(3), 16),
                                  int(m.group(4)), int(m.group(6)), int(m.group(5), 16),
                                  int(m.group(7))))
    return runs


def states(run):
    """Per actor: sorted list of (frame, cont, busy, at) snapshots."""
    h = collections.defaultdict(list)
    for fr, i, cont, busy, at, fx, hp in run["ev"]:
        h[i].append((fr, cont, busy, at, fx, hp))
    return h


def at_frame(hist, fr):
    cur = None
    for s in hist:
        if s[0] > fr:
            break
        cur = s
    return cur


def loaders():
    recs = json.load(open(W.BESTIARY))["enemies"]
    by_table = {}
    for r in recs:
        by_table.setdefault(r["actionScriptTableAddress"], r)
    by_id = {}
    for f in os.listdir(W.ROOT + "data/04_play"):
        if f.endswith(".bin"):
            by_id[W.party_identity(f[:-4])[0]] = f[:-4]
    cache = {}

    def load(who):
        kind, key, _ = who
        if (kind, key) not in cache:
            if kind == "party":
                cache[(kind, key)] = ("party:" + by_id[key], W.load_party(by_id[key]))
            else:
                r = by_table[key]
                cache[(kind, key)] = ("%s@%s" % (r["name"], key), W.load_monster(r))
        return cache[(kind, key)]
    return load


def main():
    verbose = "-v" in sys.argv
    load = loaders()
    tally = collections.Counter()
    for run in parse():
        h = states(run)
        attacks = []
        for i, hist in h.items():
            prev = 0
            for fr, cont, busy, at, *_ in hist:
                if cont in FIRST and cont != prev:
                    attacks.append((fr, i, FIRST[cont]))
                prev = cont
        attacks.sort()
        for n, (f0, a, path) in enumerate(attacks):
            t = at_frame(h[a], f0)[3]
            actors = {"attacker": a, "target": t}
            if path == "cover":
                actors["ally"] = at_frame(h[t], f0)[3]
            # each actor's window ends at the next attack that involves IT (as attacker, target
            # or cover pair), so another actor's later turn doesn't cut it short
            involved = [(f, {x, at_frame(h[x], f)[3]}) for f, x, _ in attacks[n + 1:] if f > f0]
            ends = {}
            for role, idx in actors.items():
                nx = [f for f, who in involved if idx in who]
                ends[role] = min(nx) if nx else f0 + WINDOW
            nxt = any(e < f0 + WINDOW for e in ends.values())
            live_tr, live_busy, init_fx, killed = [], {}, {}, set()
            for role, idx in actors.items():
                prev = at_frame(h[idx], f0 - 1) or (0, 0, 0, 0, 0, 0)
                pb, changes = prev[2], []
                init_fx[role] = prev[4]
                for fr, cont, busy, at, fx, hp in h[idx]:
                    if fr < f0 or fr >= ends[role]:
                        continue
                    if fr > f0 and cont != prev[1]:
                        live_tr.append((fr - f0, role, cont))
                    if bool(busy) != bool(pb):
                        changes.append((fr - f0, "set" if busy else "clear"))
                    if hp == 0 and fr - f0 < 300:
                        killed.add(role)
                    pb, prev = busy, (fr, cont, busy, at, fx, hp)
                live_busy[role] = changes
            try:
                (an, att), (tn, tgt) = load(run["who"][a]), load(run["who"][t])
                ally = load(run["who"][actors["ally"]])[1] if path == "cover" else None
                rp = run["who"][a][2] if run["who"][a][0] == "party" else None
                order = sorted(actors, key=lambda r: actors[r])
                w = W.walk_path(att, tgt, path, ally, a < t,
                                reaction_script=RUNE_PIECE_REACTION.get(rp)
                                if path in ("hit", "crit") else None,
                                index_order=order, init_fx=init_fx, lethal=killed,
                                party_roles={r for r in actors if actors[r] <= run["party"]})
            except (W.Unresolvable, TypeError, KeyError) as e:
                print("%s F%d %-7s %s -> %s: walker failed: %s" % (run["name"], f0, path, a, t, e))
                tally[(path, "walker failed")] += 1
                continue
            w_tr = [x for x in w["transitions"] if x[0] > 0]
            # compare each actor's busy set/clear sequence, live cut to the walker's length:
            # after the attack's own transitions, the actor may go busy for unrelated reasons
            # (its own turn, a spell), which the walker doesn't simulate
            w_busy = {r: [x for x in w[r + "_busy"] if x[0] < ends[r] - f0] for r in actors}
            cut = {r: live_busy[r][:len(w_busy[r])] for r in actors}
            live_tr.sort()
            w_tr = sorted(w_tr)
            # walker steps past an actor's window can't be seen live
            w_tr = [x for x in w_tr if x[0] < ends[x[1]] - f0]
            tr_ok = w_tr == [x for x in live_tr if x[0] <= (w_tr[-1][0] if w_tr else 0)]
            busy_ok = all(w_busy[r] == cut[r] for r in actors)
            status = "OK" if tr_ok and busy_ok else "DIFF"
            if status != "OK" and killed:
                status += " (killed: %s)" % ",".join(sorted(killed))
            elif status != "OK" and nxt:
                status += " (overlap)"
            tally[(path, status)] += 1
            print("%s F%-4d %-7s %-24s -> %-24s %s" % (run["name"], f0, path, an, tn, status))
            if verbose or status != "OK":
                fmt = lambda tr: " ".join("%d:%s=%s" % (f, r[0], NAMES.get(c, hex(c))) for f, r, c in tr)
                print("    walker chain %s" % fmt(w_tr))
                print("    live   chain %s" % fmt(live_tr))
                print("    walker busy  %s" % w_busy)
                print("    live   busy  %s" % {r: live_busy[r][:len(w_busy[r]) + 2] for r in actors})
    print()
    for k in sorted(tally):
        print("%-8s %-18s %d" % (k[0], k[1], tally[k]))


if __name__ == "__main__":
    main()
