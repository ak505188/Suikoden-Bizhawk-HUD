# Offline check of scripts/TraceAinGide.lua's output against the decompiled AI formula
# (vac.bin 0x80013b1c): front-row scan with rand2 % 100 > 50 per candidate (retry fresh if none),
# then one move roll, (roll*100)//32767 < 0x33 -> Attack, else Special. Also prints per-move timing
# statistics relative to T0 (Ain Gide's first frame as current actor).
# Usage: python3 scripts/python/CheckAinGideTrace.py [trace.txt]
import re, sys, collections

OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceAinGide.txt"
M = 0x100000000


def nxt(s):
    return (s * 0x41c64e6d + 0x3039) % M


def rng2(s):                      # lib/RNG.lua getRNG2: (seed >> 16) & 0x7fff
    return (s >> 16) & 0x7fff


def simulate(seed, cands):
    calls = 0
    while True:
        for c in cands:
            seed = nxt(seed); calls += 1
            if rng2(seed) % 100 > 50:
                tgt = c
                break
        else:
            continue
        break
    seed = nxt(seed); calls += 1
    r = rng2(seed)
    move = "Attack" if (r * 100) // 32767 < 0x33 else "Special"
    return move, tgt, calls, seed


def parse(path):
    rounds, cur = [], None
    for line in open(path):
        line = line.rstrip("\n")
        m = re.match(r"(s\d+ r\d+): me=#(\d+) round=(\d+)", line)
        if m:
            cur = {"label": m.group(1), "me": int(m.group(2)), "ev": [], "roster": []}
            rounds.append(cur)
            continue
        if cur is None:
            continue
        if line.startswith("  roster"):
            for r in re.finditer(r"#(\d+) pos(\d+) dead(\d)", line):
                cur["roster"].append((int(r.group(1)), int(r.group(2)), int(r.group(3))))
            continue
        m = re.match(r"  T\+(-?\d+) (.*)", line)
        if m:
            t = int(m.group(1))
            if "becomes current actor" in m.group(2):
                cur["seed"] = int(re.search(r"=([0-9a-f]{8}) round", m.group(2)).group(1), 16)
            cur["ev"].append((t, m.group(2)))
    return rounds


def first(ev, pat, after=-1):
    for t, w in ev:
        if t > after and re.search(pat, w):
            return t
    return None


def main():
    rounds = parse(sys.argv[1] if len(sys.argv) > 1 else OUT)
    ok = bad = 0
    stats = collections.defaultdict(lambda: collections.defaultdict(list))
    for r in rounds:
        if "seed" not in r:
            print(r["label"], "no T0"); continue
        cands = [i for i, pos, dead in r["roster"] if not dead and pos < 4]
        move, tgt, calls, _ = simulate(r["seed"], cands)
        ev = r["ev"]
        actual = "Special" if first(ev, r"battle\+0x0c .*-> 80013d08") is not None else "Attack"
        atgt = None
        for t, w in ev:
            m = re.match(r"AG TargetIdx\(\+0x49\) 0 -> (\d+)", w)
            if m:
                atgt = int(m.group(1)); break
        # rolls up to the frame the move is committed: Special = continuation set, Attack = script
        # start (busy set). A fully rejected scan retries on the NEXT tick, so rolls span frames.
        end = first(ev, r"battle\+0x0c .*-> 80013d08") if actual == "Special" else first(ev, r"AG busy 0 -> 1")
        n1 = sum(int(re.match(r"rand x(\d+)", w).group(1)) for t, w in ev
                 if 0 < t <= end and re.match(r"rand x(\d+)", w))
        good = move == actual and tgt == atgt and n1 == calls + (1 if move == "Attack" else 0)  # Attack: + the hit roll
        ok += good; bad += not good
        if not good:
            print("MISMATCH", r["label"], "pred", move, tgt, calls, "actual", actual, atgt, n1)
        s = stats[actual]
        s["busy_set"].append(first(ev, r"AG busy 0 -> 1"))
        s["busy_clear"].append(first(ev, r"AG busy 1 -> 0"))
        s["gate30"].append(first(ev, r"gate reset .* -> 30"))
        if actual == "Special":
            s["plus42_1"].append(first(ev, r"\+0x42 0 -> 1"))
            s["plus42_2"].append(first(ev, r"\+0x42 1 -> 2"))
            rolls = [t for t, w in ev if re.match(r"rand x2", w) and 40 < t < 200]
            s["S"].append(rolls[0] - 32 if rolls else None)
            s["nparticle_frames"].append(len(rolls))
            d = first(ev, r"damage:")
            s["dmg_vis"].append(d)
            s["p99"].append(first(ev, r"\+0x42 2 -> 99"))
        else:
            s["fx1"].append(first(ev, r"AG fx 0000 -> 0001"))
            s["fx2"].append(first(ev, r"AG fx 0001 -> 0003"))
            s["dmg_vis"].append(first(ev, r"damage:"))
            s["fx4"].append(first(ev, r"AG fx 0013 -> 0017"))
    print("move+target+roll-count matches: %d / %d" % (ok, ok + bad))
    for mv, s in stats.items():
        print(mv, "n=%d" % len(s["busy_set"]))
        for k, v in s.items():
            v = [x for x in v if x is not None]
            if v:
                print("   %-18s min %d max %d  %s" % (k, min(v), max(v), sorted(collections.Counter(v).items())))


main()
