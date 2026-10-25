# Compares scripts/verify/VerifyAttackTimings.lua's live per-frame log against the static predictions
# in outputs/AttackTimings.json (scripts/python/AttackTimingWalker.py).
# Usage: python3 scripts/python/AttackTimingCompare.py
import json, os, re, struct, sys

OUT_DIR = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/"
LOG = OUT_DIR + "VerifyAttackTimings.txt"
PLAY = "/mnt/Shared/ISOs/Suikoden/Suikoden Files/data/04_play/"
HERE = os.path.dirname(os.path.abspath(__file__))
TIMINGS = json.load(open(os.path.join(HERE, "..", "..", "outputs", "AttackTimings.json")))


def match_party_file(dump_path):
    """Party files are loaded with pointers relocated by +L, so compare only words that aren't
    small file offsets; the best-scoring file wins."""
    live = open(dump_path, "rb").read()
    best = (0, None)
    for f in os.listdir(PLAY):
        if not f.endswith(".bin"):
            continue
        d = open(PLAY + f, "rb").read()[:len(live)]
        score = 0
        for o in range(0, min(len(d), len(live)) - 3, 4):
            w = struct.unpack_from("<I", d, o)[0]
            if w < len(d):                              # likely a relocated pointer, skip
                continue
            score += d[o:o + 4] == live[o:o + 4]
        if score > best[0]:
            best = (score, f[:-4])
    return best[1]


def parse():
    runs, cur = [], None
    for line in open(LOG):
        line = line.strip()
        if line.startswith("RUN"):
            cur = {"hdr": line, "ev": []}
            runs.append(cur)
        elif line.startswith("ACTOR"):
            m = re.match(r"ACTOR (\d+) .* id=(-?\d+)", line)
            runs[0].setdefault("actors", {})[int(m.group(1))] = int(m.group(2))
        elif line.startswith("F ") and cur is not None:
            m = re.match(r"F (\d+) A (\d+) busy=(\d+) fx=0x([0-9a-f]+) hp=(-?\d+) slot1=(\d) tag=(\d+)", line)
            if m:
                cur["ev"].append(("A", int(m.group(1)), int(m.group(2)), int(m.group(3)),
                                  int(m.group(4), 16), int(m.group(5)), int(m.group(6))))
    return runs


def timeline(ev, total):
    """Per-actor state at every logged frame -> list of attacks with measured frames."""
    state = {i: None for i in range(1, total + 1)}
    hist = {i: [] for i in range(1, total + 1)}          # (frame, busy, fx, hp, slot1)
    for _, fr, a, busy, fx, hp, s1 in ev:
        hist[a].append((fr, busy, fx, hp, s1))
    attacks = []
    for a, h in hist.items():
        prev_busy = 0
        for k, (fr, busy, fx, hp, s1) in enumerate(h):
            # the attack script's first opcode sets the attacker's busy bit 1
            if busy & 1 and not prev_busy & 1 and s1 == 1:
                attacks.append({"attacker": a, "start": fr})
            prev_busy = busy
    for atk in attacks:
        a, t0 = atk["attacker"], atk["start"]
        after = [x for x in hist[a] if x[0] >= t0]
        atk["impact"] = next((x[0] for x in after if x[2] & 0x2), None)
        atk["applied"] = next((x[0] for x in after if x[2] & 0x10), None)
        atk["fx4"] = next((x[0] for x in after if x[2] & 0x4), None)
        atk["busy1_clear"] = next((x[0] for x in after if x[0] > t0 and not x[1] & 1), None)
        # target = whoever loses HP first at/after impact
        hit = None
        if atk["impact"] is not None:
            for t, ht in hist.items():
                if t == a:
                    continue
                for (fr, busy, fx, hp, s1), prevx in zip(ht[1:], ht):
                    if fr >= atk["impact"] and hp < prevx[3]:
                        if hit is None or fr < hit[1]:
                            hit = (t, fr)
                        break
        if hit and atk["impact"] is not None and hit[1] > atk["impact"] + 1:
            hit = None                                  # no HP change on the damage frame: a miss
            atk["miss"] = True
        if hit:
            atk["target"], atk["damage"] = hit
            th = [x for x in hist[hit[0]] if x[0] >= hit[1]]
            atk["tgt_busy8_clear"] = next((x[0] for x in th if not x[1] & 8), None)
    return sorted(attacks, key=lambda x: x["start"])


def main():
    runs = parse()
    actors = runs[0]["actors"]
    total = len(actors)
    party_codes = {}
    for i in range(1, total):
        path = OUT_DIR + "VerifyAttackTimings_run1_actor%d.bin" % i
        party_codes[i] = match_party_file(path)
    zd = next(e for e in TIMINGS["enemies"] if e["name"] == "Zombie Dragon")
    party = {e["key"]: e for e in TIMINGS["party"]}
    print("party files:", party_codes)
    for run in runs:
        print("\n" + run["hdr"])
        for atk in timeline(run["ev"], total):
            a = atk["attacker"]
            if a == total:
                pred_atk, key = zd["attack"], "ZD"
                pred_rec = zd["recover"]
                tcode = party_codes.get(atk.get("target"))
                pred_react = TIMINGS["reaction"]["enemy_hit"][zd["key"]].get(tcode) if tcode else None
            else:
                code = party_codes[a]
                pred_atk, pred_rec, key = party[code]["attack"], party[code]["recover"], code
                pred_react = TIMINGS["reaction"]["party_hit"][code][zd["key"]]
            t0 = atk["start"]
            rel = lambda k: None if atk.get(k) is None else atk[k] - t0
            pi = pred_atk["impact"][0] if pred_atk["impact"] else None
            pd = pred_atk["damage_roll"][0] if pred_atk["damage_roll"] else None
            pf4 = pred_atk.get("attacker_fx4_set")
            pb1 = (pf4 + 1 + pred_rec["self_busy1_clear"]) if pf4 is not None and pred_rec.get("self_busy1_clear") is not None else None
            dmg = rel("damage")
            react = None if atk.get("tgt_busy8_clear") is None or atk.get("damage") is None else atk["tgt_busy8_clear"] - atk["damage"]
            def cell(meas, pred):
                ok = "" if meas == pred else "  <-- MISMATCH"
                return "%s/%s%s" % (meas, pred, ok)
            print("  actor %d %-4s start F%-4d impact %s  damage %s  fx4 %s  selfFree %s  target %s react %s"
                  % (a, key, t0, cell(rel("impact"), pi), cell(dmg, pd), cell(rel("fx4"), pf4),
                     cell(rel("busy1_clear"), pb1), atk.get("target"), cell(react, pred_react))
                  + ("  (miss: no HP change)" if atk.get("miss") else ""))


if __name__ == "__main__":
    main()
