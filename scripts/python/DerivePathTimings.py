# Derives the per-combatant miss / counter / cover / kill timing fields from full
# AttackTimingWalker.walk_path simulations, and verifies the composition formulas against every
# simulated pair. Writes outputs/AttackPathTimings.json (enemies in Bestiary order, party keyed
# by 04_play code), which scripts/python/CleanAttackTimings.py merges into AttackTimingsClean.json.
#
# The formulas (all frames from the attack's t0; P = attacker dodgePoint, D = damage,
# F = free, RS = recover; R = F - RS):
#   hit / crit   roll D; attacker F; target D + reaction
#   miss         attacker missFree ?? F; target max(P + dodge.afterPoint,
#                                                  RS + dodge.afterRecover)   (null: no 2nd term)
#   counter      roll max(P + c.afterPoint, D + c.afterDamage), or P + c.primed when the
#                retaliator already holds flag 0x2; retaliator roll + c.free; attacker
#                roll + c.attackerDelay + R (R < 0: F, the attack script cleared busy itself)
#   cover        roll D; attacker F; ally D + reaction; target ally + COVER_TARGET_AFTER_ALLY
#   kill         enemy: its free + death (as target, after its reaction; as a countered
#                attacker, after its counter-path free); party: + 0
# Every combatant only ever needs its own side's role fields: enemies dodge / counter party
# attacks, party members dodge / counter enemy attacks.
#
# Usage: python3 scripts/python/DerivePathTimings.py   (several minutes; uses every CPU)
import collections, json, os, sys
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import AttackTimingWalker as W

OUT = os.path.join(HERE, "..", "..", "outputs", "AttackPathTimings.json")
RECS = json.load(open(W.BESTIARY))["enemies"]
CODES = sorted(f[:-4] for f in os.listdir(W.ROOT + "data/04_play") if f.endswith(".bin"))
REC = W.CONT_ADDR["recover"]
COVER_TARGET_AFTER_ALLY = 11
COVER_ALLY = ("gre", "shu")                             # any ally works: its timing is the
                                                        # attacker's reaction (checked)


def summarize(r):
    tr = r["transitions"]
    on = [f for f, k, a in tr if k == "attacker" and a == REC]
    fire = [f for f, k, a in tr if k == "attacker" and a == 0 and f > 0 and (not on or f > on[-1])]
    return {"blocked": r["blocked"], "roll": r["damage"][0]["frame"] if r["damage"] else None,
            "af": r["attacker_free"], "tf": r["target_free"], "lf": r.get("ally_free"),
            "P": r["attacker_dodge_point"], "RS": fire[0] if fire else None}


def job(args):
    side, ai, ti, path, variant = args                  # side: attacker's side, P or E
    out = {"side": side, "a": ai, "t": ti, "path": path, "variant": variant}
    try:
        if side == "P":
            att, tgt, first = W.load_party(CODES[ai]), W.load_monster(RECS[ti]), True
            ally = None
        else:
            att, tgt, first = W.load_monster(RECS[ai]), W.load_party(CODES[ti]), False
            ally = (W.load_party(COVER_ALLY[0] if CODES[ti] != COVER_ALLY[0] else COVER_ALLY[1])
                    if path == "cover" else None)
        kw = {}
        if variant == "lethal":
            kw["lethal"] = {"attacker"} if path == "counter" else {"target"}
        if variant == "primed":
            kw["init_fx"] = {"target": 2}
        out.update(summarize(W.walk_path(att, tgt, path, ally, first, **kw)))
    except (W.Unresolvable, TypeError) as e:
        out["error"] = str(e)[:80]
    return out


def jobs():
    for ai in range(len(CODES)):
        for ti, r in enumerate(RECS):
            for p in ("hit", "miss"):
                yield ("P", ai, ti, p, "")
            yield ("P", ai, ti, "hit", "lethal")
            if r["speciesFlags"]["raw"] & 2:
                yield ("P", ai, ti, "counter", "")
                yield ("P", ai, ti, "counter", "primed")
    for ai in range(len(RECS)):
        for ti in range(len(CODES)):
            for p in ("hit", "miss", "counter", "cover"):
                yield ("E", ai, ti, p, "")
            yield ("E", ai, ti, "counter", "primed")
            yield ("E", ai, ti, "counter", "lethal")


def good(r):
    return (r and "error" not in r and not r["blocked"] and r["af"] not in (None, "stuck")
            and r["tf"] != "stuck" and r.get("lf") != "stuck")


def mode(xs):
    return collections.Counter(xs).most_common(1)[0][0] if xs else None


def fit_max(items, key1, key2, allow_none):
    """Best (k1, k2) for obs == max(lm[key1] + k1, lm[key2] + k2) over items [(lm, obs)];
    k2 None = no second term. Candidates come from the observations themselves."""
    c1 = {o - lm[key1] for lm, o in items}
    c2 = {o - lm[key2] for lm, o in items} | ({None} if allow_none else set())
    best = (-1, None)
    for k1 in c1:
        for k2 in c2:
            n = sum(1 for lm, o in items
                    if max(lm[key1] + k1, lm[key2] + k2 if k2 is not None else -10 ** 9) == o)
            if n > best[0]:
                best = (n, (k1, k2))
    return best


def main():
    js = list(jobs())
    print(len(js), "simulations", flush=True)
    with Pool(os.cpu_count()) as pool:
        rows = pool.map(job, js, chunksize=64)
    idx = {(r["side"], r["a"], r["t"], r["path"], r["variant"]): r for r in rows}
    get = lambda *k: idx.get(k) if good(idx.get(k)) else None
    opp = {"P": "E", "E": "P"}
    n_of = {"P": len(CODES), "E": len(RECS)}
    fields = {"P": collections.defaultdict(dict), "E": collections.defaultdict(dict)}

    # attacker-side fields, from the hit path (constant over targets; checked below)
    for side in ("P", "E"):
        for a in range(n_of[side]):
            hits = [get(side, a, t, "hit", "") for t in range(n_of[opp[side]])]
            hits = [h for h in hits if h and h["roll"] is not None and h["RS"] is not None]
            if not hits:
                continue
            f = fields[side][a]
            for k, src in (("damage", "roll"), ("free", "af"), ("dodgePoint", "P"), ("recover", "RS")):
                f[k] = mode([h[src] for h in hits])
            f["reaction"] = mode([h["tf"] - h["roll"] for h in hits])
            misses = [get(side, a, t, "miss", "") for t in range(n_of[opp[side]])]
            mf = mode([m["af"] for m in misses if m])
            if mf is not None and mf != f["free"]:
                f["missFree"] = mf

    # target-side fields, fitted over every attacker of the other side
    for side in ("P", "E"):
        tside = opp[side]
        A = fields[side]
        for t in range(n_of[tside]):
            lm = lambda a: dict(P=A[a]["dodgePoint"], D=A[a]["damage"], RS=A[a]["recover"],
                                F=A[a]["free"])
            atts = [a for a in range(n_of[side]) if "damage" in A[a]]
            miss = [(lm(a), m["tf"]) for a in atts for m in [get(side, a, t, "miss", "")] if m]
            if miss:
                _, (k1, k2) = fit_max(miss, "P", "RS", True)
                fields[tside][t]["dodge"] = {"afterPoint": k1, "afterRecover": k2}
            ctr = [(a, lm(a), c) for a in atts for c in [get(side, a, t, "counter", "")]
                   if c and c["roll"] is not None]
            if ctr:
                _, (k1, k2) = fit_max([(l, c["roll"]) for a, l, c in ctr], "P", "D", False)
                primed = [c["roll"] - l["P"] for a, l, _ in ctr
                          for c in [get(side, a, t, "counter", "primed")] if c and c["roll"] is not None]
                fields[tside][t]["counter"] = {
                    "afterPoint": k1, "afterDamage": k2, "primed": mode(primed),
                    "free": mode([c["tf"] - c["roll"] for a, l, c in ctr]),
                    "attackerDelay": mode([c["af"] - c["roll"] - (l["F"] - l["RS"])
                                           for a, l, c in ctr if l["F"] >= l["RS"]])}
            if tside == "E":
                kills = [k["tf"] - h["tf"] for a in atts
                         for h, k in [(get(side, a, t, "hit", ""), get(side, a, t, "hit", "lethal"))]
                         if h and k]
                if kills:
                    fields["E"][t]["death"] = mode(kills)

    # ---- verification: every formula against every simulated pair ----
    ver, misfits = collections.OrderedDict(), collections.defaultdict(list)

    def check(name, obs, pred, who):
        v = ver.setdefault(name, [0, 0])
        v[1] += 1
        if obs == pred:
            v[0] += 1
        elif len(misfits[name]) < 12:
            misfits[name].append(who)

    for (side, a, t, path, variant), r in idx.items():
        if not good(r):
            continue
        A, T = fields[side].get(a, {}), fields[opp[side]].get(t, {})
        if "damage" not in A:
            continue
        who = "%s -> %s" % ((CODES[a], "%s@%s" % (RECS[t]["name"], RECS[t]["actionScriptTableAddress"]))
                            if side == "P" else ("%s@%s" % (RECS[a]["name"], RECS[a]["actionScriptTableAddress"]), CODES[t]))
        R = A["free"] - A["recover"]
        if path == "hit" and variant == "":
            check(side + " hit roll", r["roll"], A["damage"], who)
            check(side + " hit attacker free", r["af"], A["free"], who)
            check(side + " hit target free", r["tf"], A["damage"] + A["reaction"], who)
        elif path == "hit" and variant == "lethal" and "death" in T:
            check("P kill target free", r["tf"], A["damage"] + A["reaction"] + T["death"], who)
        elif path == "miss" and "dodge" in T:
            d = T["dodge"]
            check(side + " miss attacker free", r["af"], A.get("missFree", A["free"]), who)
            check(side + " miss target free", r["tf"],
                  max(A["dodgePoint"] + d["afterPoint"],
                      A["recover"] + d["afterRecover"] if d["afterRecover"] is not None else -10 ** 9), who)
        elif path == "counter" and "counter" in T and r["roll"] is not None:
            c = T["counter"]
            roll = (A["dodgePoint"] + c["primed"] if variant == "primed"
                    else max(A["dodgePoint"] + c["afterPoint"], A["damage"] + c["afterDamage"]))
            af = A["free"] if R < 0 else roll + c["attackerDelay"] + R
            tag = side + " counter" + (" primed" if variant == "primed" else "")
            if variant == "lethal":
                check("E killed by counter attacker free", r["af"],
                      af + fields["E"].get(a, {}).get("death", 0), who)
                continue
            check(tag + " roll", r["roll"], roll, who)
            check(tag + " retaliator free", r["tf"], roll + c["free"], who)
            check(tag + " attacker free", r["af"], af, who)
        elif path == "cover" and r["roll"] is not None:
            check("E cover roll", r["roll"], A["damage"], who)
            check("E cover attacker free", r["af"], A["free"], who)
            check("E cover ally free", r["lf"], A["damage"] + A["reaction"], who)
            check("E cover target free", r["tf"], A["damage"] + A["reaction"] + COVER_TARGET_AFTER_ALLY, who)

    for name, (ok, tot) in ver.items():
        print("%-40s %6d / %6d%s" % (name, ok, tot, "" if ok == tot else "   misfits: %s" % misfits[name][:3]))

    out = {
        "_meta": {
            "description": "Per-combatant miss / counter / cover / kill timing fields, derived from "
                           "full AttackTimingWalker.walk_path sweeps (see the header of "
                           "scripts/python/DerivePathTimings.py for the formulas). enemies: Bestiary order; "
                           "party: 04_play code.",
            "constants": {"coverTargetAfterAlly": COVER_TARGET_AFTER_ALLY,
                          "buddhaHealAfterReaction": 113, "buddhaFreeAfterReaction": 123},
            "verification": {k: {"exact": v[0], "total": v[1], "misfits": misfits.get(k, [])}
                             for k, v in ver.items()},
            "simulations": len(js),
            "errors_or_blocked": sum(1 for r in rows if not good(r)),
        },
        "enemies": [fields["E"].get(i, {}) for i in range(len(RECS))],
        "party": {c: fields["P"].get(i, {}) for i, c in enumerate(CODES)},
    }
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
