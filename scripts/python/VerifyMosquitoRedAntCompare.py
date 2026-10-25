# Compares scripts/verify/VerifyMosquitoRedAnt.lua's live per-frame log against the static predictions:
#   - attack timings (outputs/AttackTimingsClean.json for basic Attack; the walker's DoubleStrike
#     walk for Red Solider Ant's script 0x800a5460 + reaction 0x800a5550)
#   - AI target/move choice, by replaying the LCG from each decision tick's RNG value through
#     the decompiled scan: per eligible (alive, formationPos<4, not busy) party member in slot
#     order, rand()%100 > 50 accepts; Red Solider Ant then rolls ((r*100)/0x7fff)%100 < 77 ->
#     Attack, else DoubleStrike.
# Usage: python3 scripts/python/VerifyMosquitoRedAntCompare.py
import collections, functools, json, os, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import AttackTimingWalker as W

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/VerifyMosquitoRedAnt.txt"
A_DATA = "/mnt/Shared/ISOs/Suikoden/Suikoden Files/data/01_area.a/a_data.bin"
CLEAN = json.load(open(os.path.join(HERE, "..", "..", "outputs", "AttackTimingsClean.json")))

MOSQ_TABLE, ANT_TABLE, DS_SCRIPT = 0x800a0e74, 0x800a5388, 0x800a5460
adata = open(A_DATA, "rb").read()
u32 = lambda a: struct.unpack_from("<I", adata, a - 0x80080000)[0]
SLOT1 = {MOSQ_TABLE: u32(MOSQ_TABLE + 4), ANT_TABLE: u32(ANT_TABLE + 4)}


def pred_basic(name):
    e = next(v for v in CLEAN["enemies"].values() if v["name"] == name)
    a, r = e["attack"], e["recover"]
    d = a["damage_roll"][0]
    return {"impact": a["impact"][0], "damage": d, "tfree": d + e["reaction"]["hit"]["default"],
            "afree": a["attacker_fx4_set"] + 1 + r["self_busy1_clear"]}


PRED = {("Mosquito", "Attack"): pred_basic("Mosquito"),
        ("Red Solider Ant", "Attack"): pred_basic("Red Solider Ant"),
        ("Red Solider Ant", "DoubleStrike"): {"impact": 28, "damage": 29, "tfree": 63, "afree": 145}}


def lcg(s):
    return (s * 0x41c64e6d + 0x3039) & 0xffffffff


def parse():
    runs, run, rnd = [], None, None
    for line in open(LOG):
        line = line.strip()
        if line.startswith("RUN"):
            run = {"hdr": line, "rounds": []}
            runs.append(run)
        elif line.startswith("ROUND ") and "party=" in line:
            m = re.match(r"ROUND (\d+) party=(\d+) total=(\d+)", line)
            rnd = {"n": int(m.group(1)), "party": int(m.group(2)), "total": int(m.group(3)),
                   "layout": {}, "hist": collections.defaultdict(list), "rng": [], "cur": []}
            run["rounds"].append(rnd)
        elif line.startswith("LAYOUT"):
            m = re.match(r"LAYOUT (\d+) id=(-?\d+) table=0x([0-9a-f]+) hp=(-?\d+)/(-?\d+) form=(\d+) dead=(\d+)", line)
            rnd["layout"][int(m.group(1))] = {"id": int(m.group(2)), "table": int(m.group(3), 16),
                                              "form": int(m.group(6))}
        elif line.startswith("F ") and rnd is not None:
            m = re.match(r"F (\d+) A (\d+) busy=(\d+) fx=0x([0-9a-f]+) hp=(-?\d+) tag=(\d+) tgt=(\d+) "
                         r"cursor=0x([0-9a-f]+) dead=(\d+)", line)
            if m:
                g = m.groups()
                rnd["hist"][int(g[1])].append({"f": int(g[0]), "busy": int(g[2]), "fx": int(g[3], 16),
                                               "hp": int(g[4]), "tag": int(g[5]), "tgt": int(g[6]),
                                               "cursor": int(g[7], 16), "dead": int(g[8])})
                continue
            m = re.match(r"F (\d+) RNG 0x([0-9a-f]+) -> 0x([0-9a-f]+) steps=(-?\d+)", line)
            if m:
                rnd["rng"].append((int(m.group(1)), int(m.group(2), 16), int(m.group(3), 16), int(m.group(4))))
                continue
            m = re.match(r"F (\d+) CURRENT (\d+) gate=(-?\d+)", line)
            if m:
                rnd["cur"].append((int(m.group(1)), int(m.group(2)), int(m.group(3))))
    return runs


def state_at(hist, i, f):
    """End-of-frame state of actor i at frame f (last logged change at or before f)."""
    s = None
    for x in hist[i]:
        if x["f"] > f:
            break
        s = x
    return s


def attacks(rnd):
    out = []
    names = {i: {MOSQ_TABLE: "Mosquito", ANT_TABLE: "Red Solider Ant"}.get(l["table"])
             for i, l in rnd["layout"].items()}
    for i, name in names.items():
        if not name:
            continue
        h = rnd["hist"][i]
        prev = 0
        for x in h:
            if x["busy"] & 1 and not prev & 1:
                c = x["cursor"]
                move = ("DoubleStrike" if DS_SCRIPT <= c < DS_SCRIPT + 0xf0 else
                        "Attack" if SLOT1[rnd["layout"][i]["table"]] <= c < SLOT1[rnd["layout"][i]["table"]] + 0x200
                        else "other@0x%08x" % c)
                out.append({"a": i, "name": name, "t0": x["f"], "move": move, "tgt": x["tgt"]})
            prev = x["busy"]
    for atk in out:
        a, t0, tgt = atk["a"], atk["t0"], atk["tgt"]
        after = [x for x in rnd["hist"][a] if x["f"] >= t0]
        atk["impact"] = next((x["f"] - t0 for x in after if x["fx"] & 0x2), None)
        atk["afree"] = next((x["f"] - t0 for x in after if x["f"] > t0 and x["busy"] == 0), None)
        th = rnd["hist"].get(tgt, [])
        hp0 = state_at(rnd["hist"], tgt, t0)
        dmg = None
        prev_hp = hp0["hp"] if hp0 else None
        for x in th:
            if x["f"] > t0 and x["hp"] != prev_hp:
                dmg = x
                break
            if x["f"] <= t0:
                prev_hp = x["hp"]
        if dmg and atk["impact"] is not None and dmg["f"] - t0 <= atk["impact"] + 1:
            atk["damage"] = dmg["f"] - t0
            atk["dmg_amount"] = prev_hp - dmg["hp"]
            atk["tfree"] = next((x["f"] - t0 for x in th if x["f"] >= dmg["f"] and not x["busy"] & 8), None)
        else:
            atk["damage"] = None
            atk["miss"] = True
            # cover: another party member takes the hit instead (low-HP target)
            for p in range(1, rnd["party"] + 1):
                if p == tgt or atk["impact"] is None:
                    continue
                ph = rnd["hist"][p]
                php = state_at(rnd["hist"], p, t0)["hp"]
                hit = next((x for x in ph if t0 + atk["impact"] <= x["f"] <= t0 + atk["impact"] + 1 and x["hp"] < php), None)
                if hit:
                    atk["ally"] = p
                    atk["damage"] = hit["f"] - t0
                    atk["dmg_amount"] = php - hit["hp"]
                    atk["allyfree"] = next((x["f"] - t0 for x in ph if x["f"] >= hit["f"] and not x["busy"] & 8), None)
                    atk["acode"] = PARTY_CODE.get(rnd["layout"][p]["id"])
            # counter: the attacker itself loses HP before it's free again
            ah0 = state_at(rnd["hist"], a, t0)["hp"]
            atk["counter"] = next((x["f"] - t0 for x in after if x["hp"] < ah0), None)
            atk["tfree"] = next((x["f"] - t0 for x in th if x["f"] > t0 and x["busy"] == 0), None)
            s0 = state_at(rnd["hist"], tgt, t0 - 1)
            atk["tfx0"] = s0["fx"] if s0 else 0
            atk["tcode"] = PARTY_CODE.get(rnd["layout"][tgt]["id"])
    return sorted(out, key=lambda x: x["t0"])


RECS = json.load(open(W.BESTIARY))["enemies"]
PARTY_CODE = {}
for c in sorted(f[:-4] for f in os.listdir(W.ROOT + "data/04_play") if f.endswith(".bin")):
    PARTY_CODE.setdefault(W.party_identity(c)[0], c)


@functools.lru_cache(None)
def path_pred(name, code, path, fx0, acode=None):
    att = W.load_monster(next(r for r in RECS if r["name"] == name))
    r = W.walk_path(att, W.load_party(code), path, attacker_first=False,
                    ally=W.load_party(acode) if acode else None,
                    init_fx={"target": fx0} if fx0 else None)
    d = next((x["frame"] for x in r["damage"] if x["on"] == "attacker"), None)
    dmg = next((x["frame"] for x in r["damage"] if x["on"] != "attacker"), None)
    return {"afree": r["attacker_free"], "tfree": r["target_free"], "counter": d,
            "damage": dmg, "allyfree": r.get("ally_free")}


def replay_ai(rnd, atk):
    """Replays every RNG event while this enemy is the current actor, up to its attack start."""
    a, t0 = atk["a"], atk["t0"]
    start = max((f for f, c, g in rnd["cur"] if c == a and f <= t0), default=None)
    if start is None:
        return "no CURRENT frame"
    notes = []
    for f, frm, to, steps in rnd["rng"]:
        if f < start or f > t0:
            continue
        elig = []
        for p in range(1, rnd["party"] + 1):
            s = state_at(rnd["hist"], p, f - 1)
            if s and s["dead"] == 0 and rnd["layout"][p]["form"] < 4 and s["busy"] == 0:
                elig.append(p)
        seed, used, target = frm, 0, None
        for p in elig:
            seed = lcg(seed); used += 1
            if ((seed >> 16) & 0x7fff) % 100 > 50:
                target = p
                break
        move = None
        if target:
            move = "Attack"
            if atk["name"] == "Red Solider Ant":
                seed = lcg(seed); used += 1
                r = (seed >> 16) & 0x7fff
                move = "Attack" if ((r * 100) // 0x7fff) % 100 < 77 else "DoubleStrike"
        if target is None:
            ok = steps == used
            notes.append("F%d retry elig=%s used=%d steps=%d%s" % (f, elig, used, steps, "" if ok else " MISMATCH"))
        else:
            ok = target == atk["tgt"] and move == atk["move"] and steps >= used
            notes.append("F%d pick tgt=%d %s elig=%s used=%d steps=%d%s"
                         % (f, target, move, elig, used, steps, "" if ok else " MISMATCH"))
            atk["ai_ok"] = ok
            return "; ".join(notes)
    atk["ai_ok"] = False
    return "; ".join(notes) + " (no pick found)"


def main():
    runs = parse()
    tally = collections.Counter()
    for run in runs:
        print("\n" + run["hdr"])
        for rnd in run["rounds"]:
            print("  round %d" % rnd["n"])
            for atk in attacks(rnd):
                key = (atk["name"], atk["move"])
                pred = PRED.get(key)
                ai = replay_ai(rnd, atk)
                cells = []
                good = True
                keys = ("impact", "damage", "tfree", "afree")
                if atk.get("miss"):
                    path = ("cover" if atk.get("ally") else
                            "counter" if atk["counter"] is not None else "miss")
                    key = key + (path,)
                    pp = path_pred(atk["name"], atk["tcode"], path, atk["tfx0"], atk.get("acode"))
                    pred = dict(pred, **pp)
                    keys = ("impact", "tfree", "afree") + (("counter",) if path == "counter" else ()) \
                        + (("damage", "allyfree") if path == "cover" else ())
                    cells.append("%s(%s fx0=0x%x%s)" % (path, atk["tcode"], atk["tfx0"],
                                                      " by " + atk["acode"] if atk.get("acode") else ""))
                for k in keys:
                    m, p = atk.get(k), pred and pred[k]
                    cells.append("%s %s/%s%s" % (k, m, p, "" if m == p else "!"))
                    good &= m == p
                tally[(key, "timing ok" if good else "timing MISMATCH")] += 1
                tally[(key, "AI ok" if atk.get("ai_ok") else "AI MISMATCH")] += 1
                print("    A%d %-15s %-12s t0=F%-5d tgt=%d %s dmg=%s | AI: %s"
                      % (atk["a"], atk["name"], atk["move"], atk["t0"], atk["tgt"], "  ".join(cells),
                         atk.get("dmg_amount"), ai))
    print("\nSUMMARY")
    for k, v in sorted(tally.items()):
        if v:
            print("  %-44s %-16s %d" % (" ".join(k[0]), k[1], v))


if __name__ == "__main__":
    main()
