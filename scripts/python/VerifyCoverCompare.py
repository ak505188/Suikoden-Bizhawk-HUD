# Compares scripts/verify/VerifyCover.lua's live log against a model of find_cover_target (0x800f79e0):
#   trigger: committed HP < floor(HPMax / 4)
#   pairs:   table 0x8016c814 in order; for a pair whose self-id is the target's roster id, the first
#            party member (index order) with the partner's roster id, != target, passing
#            check_combatant_alive (not busy, +0x45 clear, HP - pending > 0)
#   Phero:   target Rune.Id 26 -> scan target+1.. wrapping for +0x45 clear, not busy, and a
#            different classData+10 (gender) byte
# The actual cover ally = the party member whose cursor sits in the ally cover script
# (0x8016c270..0x8016c29b) on the attack's t0 frame. Also checks: ally and target busy from t0,
# damage on the ally at t0 + attacker damage, ally free at damage + reaction, target free at ally
# free + 11, and the PROBE classPtr bytes against data/04_play headers.
# Usage: python3 scripts/python/VerifyCoverCompare.py
import collections, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import VerifyMosquitoRedAntCompare as C
import AttackTimingWalker as W

C.LOG = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/VerifyCover.txt"
PAIRS = [(8, 2), (8, 6), (8, 1), (1, 6), (2, 3), (32, 38), (38, 32), (33, 63), (9, 4), (0, 30),
         (30, 0), (62, 0), (8, 23), (32, 45), (14, 80)]
ALLY_SCRIPT = (0x8016c270, 0x8016c29c)
REACTION = {"Mosquito": 36, "Red Solider Ant": 35}
HEADERS = {}
for f in os.listdir(W.ROOT + "data/04_play"):
    if f.endswith(".bin"):
        d = open(W.ROOT + "data/04_play/" + f, "rb").read(16)
        HEADERS.setdefault(d[0], []).append((f[:-4], d))


def parse_extra():
    """Per run: mode and PROBE lines (logged before the mode's edits)."""
    runs, cur = [], None
    for line in open(C.LOG):
        m = re.match(r"RUN (\d+) mode=(\w+)", line)
        if m:
            cur = {"mode": m.group(2), "probe": {}}
            runs.append(cur)
        m = re.match(r"PROBE (\d+) hpmax=(-?\d+) hp=(-?\d+) classPtr=0x(\w+) rune=(\d+) bytes=(.*)", line)
        if m and cur is not None:
            cur["probe"][int(m.group(1))] = {"hpmax": int(m.group(2)), "rune": int(m.group(5)),
                                             "bytes": bytes.fromhex(m.group(6).replace(" ", ""))}
    return runs


def predict(rnd, probe, mode, t0, tgt):
    s = C.state_at(rnd["hist"], tgt, t0 - 1)
    T = probe[tgt]["hpmax"] // 4
    if not s["hp"] < T:
        return None, "hp %d >= T %d" % (s["hp"], T)
    ids = {p: rnd["layout"][p]["id"] for p in range(1, rnd["party"] + 1)}
    ready = lambda p: (lambda q: q["busy"] == 0 and q["dead"] == 0 and q["hp"] > 0)(C.state_at(rnd["hist"], p, t0 - 1))
    tried = []
    for self_id, partner in PAIRS:
        if self_id != ids[tgt]:
            continue
        for p in range(1, rnd["party"] + 1):
            if p != tgt and ids[p] == partner:
                tried.append(p)
                if ready(p):
                    return p, "pair (tried %s)" % tried
    rune = 26 if (mode == "PHERO" and tgt == 3) else probe[tgt]["rune"]
    if rune == 26:
        n = rnd["party"]
        p = tgt + 1
        while p != tgt:
            if p > n:
                p = 1
                continue
            q = C.state_at(rnd["hist"], p, t0 - 1)
            if q["dead"] == 0 and q["busy"] == 0 and probe[p]["bytes"][10] != probe[tgt]["bytes"][10]:
                return p, "phero"
            p += 1
    return None, "no candidate (tried %s)" % tried


def main():
    extra = parse_extra()
    runs = C.parse()
    tally = collections.Counter()
    probe0 = extra[0]["probe"]
    print("PROBE: classPtr bytes vs 04_play headers")
    for i, pr in sorted(probe0.items()):
        cands = HEADERS.get(pr["bytes"][0], [])
        match = [c for c, d in cands if d[:16] == pr["bytes"]]
        print("  slot %d id %d hpmax %d rune %d gender %d -> %s" % (i, pr["bytes"][0], pr["hpmax"], pr["rune"],
                                                                  pr["bytes"][10], match or "NO MATCH %s" % pr["bytes"].hex()))
    for run, ex in zip(runs, extra):
        if ex["mode"] == "PROBE":
            continue
        print("\n" + run["hdr"])
        for rnd in run["rounds"]:
            for atk in C.attacks(rnd):
                if atk["move"] != "Attack" or atk["tgt"] > rnd["party"]:
                    continue
                t0, tgt = atk["t0"], atk["tgt"]
                actual = next((p for p in range(1, rnd["party"] + 1)
                               if (lambda s: s and ALLY_SCRIPT[0] <= s["cursor"] < ALLY_SCRIPT[1] and s["f"] == t0)(
                                   next((x for x in rnd["hist"][p] if x["f"] == t0), None))), None)
                path = "counter/miss" if atk.get("miss") and not atk.get("ally") else "hit/cover"
                if path != "hit/cover" and actual is None:
                    print("    t0=F%d A%d -> %d  %s (no cover check)" % (t0, atk["a"], tgt, path))
                    continue
                pred, why = predict(rnd, ex["probe"], ex["mode"], t0, tgt)
                ok = pred == actual
                tally[(ex["mode"], "who ok" if ok else "who MISMATCH")] += 1
                line = "    t0=F%d A%d(%s) -> %d hp=%d: cover by %s, predicted %s [%s]%s" % (
                    t0, atk["a"], atk["name"][:8], tgt, C.state_at(rnd["hist"], tgt, t0 - 1)["hp"], actual, pred,
                    why, "" if ok else "  <-- MISMATCH")
                if actual:
                    ah = rnd["hist"][actual]
                    th = rnd["hist"][tgt]
                    busy_t0 = [next(x for x in h if x["f"] == t0)["busy"] for h in (ah, th)]
                    dmg = atk.get("damage")
                    afree = next((x["f"] - t0 for x in ah if x["f"] > t0 + (dmg or 0) and not x["busy"] & 8), None)
                    tfree = next((x["f"] - t0 for x in th if x["f"] > t0 and x["busy"] == 0), None)
                    pd = C.PRED[(atk["name"], "Attack")]["damage"]
                    exp = (pd, pd + REACTION[atk["name"]])
                    # the target's 0x8016c2b4 polls the ally's busy in the animation pass; an attack
                    # that re-marks the ally in the next tick's turn coroutine hides the clear
                    final = afree
                    while final is not None and (C.state_at(rnd["hist"], actual, t0 + final + 1) or {}).get("busy"):
                        final = next((x["f"] - t0 for x in ah if x["f"] > t0 + final + 1 and x["busy"] == 0), None)
                    tok = dmg == exp[0] and afree == exp[1] and tfree == final + 11 and busy_t0 == [8, 8]
                    tally[(ex["mode"], "timing ok" if tok else "timing MISMATCH")] += 1
                    line += "\n        busy@t0 ally/tgt=%s dmg %s/%s allyFree %s/%s tgtFree %s/%s%s" % (
                        busy_t0, dmg, exp[0], afree, exp[1], tfree, None if final is None else final + 11,
                        "" if tok else "  <-- TIMING")
                print(line)
    print("\nSUMMARY")
    for k, v in sorted(tally.items()):
        print("  %-8s %-18s %d" % (k[0], k[1], v))


if __name__ == "__main__":
    main()
