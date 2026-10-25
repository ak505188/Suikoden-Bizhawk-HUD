# Static item-use timing per party character: simulates the shared item-use scripts (main.exe
# 0x8016c194 on the user; Medicine's 0x8016c1c0 on the user and 0x8016c2f0 on the target) on each
# data/04_play/<code>.bin sprite sheet with AttackTimingWalker's script interpreter, plus the
# native Medicine / Antitoxin effect handlers (0x800f215c, 0x800f2838 chains) modelled below.
#   itemDone           frame (from R, the "uses" line) the target's busy goes 0 -> 1: the user's
#                      anim 13 + anim 14 length, where the script sets its flag 0x8
#   itemUserFreeAlly   frame the user's busy drops 1 -> 0 after an ally-targeted use
#   self-use user free and target free are done + 64 (checked for every character)
# Writes outputs/CharacterItemTimings.json (keys / ids match Suikoden-RNG-lib's
# characterAttackTimings.json). HP change = done + 32 (the sim's frame is one earlier: the
# pending HP commits on the next tick). See notes/Item_Use_Timing.md.
# Usage: python3 scripts/python/ItemUseTimings.py
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import AttackTimingWalker as W

def heal_setup(sim, a):            # 0x800f215c: variant chosen from phase, then phase = 0
    a.counter = 30; a.bright = 255; a.vfx = 0x800f24e0; a.phase = 0
def heal_tick(sim, a):             # 0x800f24e0
    if a.phase == 0:
        a.counter -= 1
        if a.counter < 1:
            a.vfx = 0x800f26cc
def heal_fade(sim, a):             # 0x800f26cc
    if a.phase == 0:
        sim.log(a, "HP CHANGE"); a.phase = 1
    elif a.phase == 1:
        a.bright -= 4
        if a.bright < 0x81: a.phase = 99
    elif a.phase == 99:
        a.vfx = None
def cure_setup(sim, a):            # 0x800f2838 (Antitoxin)
    a.counter = 30; a.vfx = 0x800f297c; a.phase = 0
def cure_tick(sim, a):             # 0x800f297c
    if a.phase == 0:
        a.counter -= 1
        if a.counter < 1: a.vfx = 0x800f2c54
def cure_fade(sim, a):             # 0x800f2c54
    if a.phase == 0:
        a.phase = 99
    elif a.phase == 99:
        sim.log(a, "STATUS CLEARED"); a.vfx = None
W.HANDLERS.update({0x800f215c:heal_setup,0x800f24e0:heal_tick,0x800f26cc:heal_fade,
                   0x800f2838:cure_setup,0x800f297c:cure_tick,0x800f2c54:cure_fade})


# Needle (0x800f2d7c setup, 0x800f2eb8 tick, 0x800f3084 finish). The tick plays sequence 5 of the
# shared effect sheet (word 0 of battle.bin, the sheet the status sprites are built from) once and
# waits for it to stop: 10 frames. Inferred: that the status sprite's sequence 5 is this sheet's.
def _seq5():
    m = W.Mem(W.ROOT + "data/00_init/battle.bin", W.SHARED_BATTLE_LOAD)
    an = W.Anim(m, m.u32(W.SHARED_BATTLE_LOAD)); an.start(5)
    return an


def needle_setup(sim, a):
    a.vfx = 0x800f2eb8; a.phase = 0


def needle_tick(sim, a):
    if a.phase == 0:
        a.nanim = _seq5(); a.phase = 1
    elif a.phase == 1 and not a.nanim.playing:
        a.phase = 0; a.vfx = 0x800f3084
        return
    a.nanim.update()


def needle_finish(sim, a):
    if a.phase == 0:
        sim.log(a, "STATUS BIT CLEARED"); a.phase = 99
    elif a.phase == 99:
        a.vfx = None


W.HANDLERS.update({0x800f2d7c: needle_setup, 0x800f2eb8: needle_tick, 0x800f3084: needle_finish})

USER, USER2 = 0x8016c194, 0x8016c1c0
TARGET_SCRIPTS = {"medicine": 0x8016c2f0, "mega": 0x8016c314, "antitoxin": 0x8016c390,
                  "needle": 0x8016c3b8}


def run(item, ucode, tcode, self_use, verbose=False):
    ul = W.load_party(ucode)
    tl = ul if self_use else W.load_party(tcode)
    user = W.Actor("user", *ul)
    tgt = user if self_use else W.Actor("target", *tl)
    sim = W.Sim(verbose); sim.attacker = user; user.target = tgt
    sim.actors = [user] if self_use else [user, tgt]
    sim.play(user, USER)
    started, ev, fr = False, {}, 0
    while fr < 800:
        sim.frame = fr
        if not started and user.fx & 8:      # the handler sees the flag the frame after it is set
            started = True; ev["done"] = fr
            sim.play(user, USER2); tgt.target = user
            sim.play(tgt, TARGET_SCRIPTS[item])
        tb, ub = tgt.busy, user.busy
        sim.tick()
        if tgt.busy != tb: ev.setdefault("tb", []).append((fr, tb, tgt.busy))
        if user.busy != ub: ev.setdefault("ub", []).append((fr, ub, user.busy))
        fr += 1
        if not any(x.cursor is not None and x.saved not in (0, 1) for x in sim.actors):
            break
    ev["hp"] = [f for f, _, w in sim.events if w == "HP CHANGE"]
    return ev, sim


def item_table(ucode="shu"):
    """Per-item frames from done for one user (target free / user free, self and ally use) when
    the target HAS the status. Without it Antitoxin / Needle play nothing and the user is free at
    itemUserFreeAlly either way. Incense is not simulated here (see Turn_Order.md)."""
    rows = {}
    for item in TARGET_SCRIPTS:
        s, _ = run(item, ucode, ucode, True)
        a, _ = run(item, ucode, "cre" if ucode != "cre" else "shu", False)
        d = s["done"]
        rows[item] = {"targetFree": s["tb"][-1][0] - d, "userFreeSelf": s["ub"][-1][0] - d,
                      "userFreeAlly": a["ub"][-1][0] - d}
    return rows


def incense(ucode="shu"):
    """Dragon Seal Incense: the handler 0x800f09f0 returns -1 until no living party slot is busy
    (the user's own script 0x8016c194 included), then plays 0x8016c3dc on every living slot.
    Frames: fire (one tick after the user's busy clears), member free, HP change, from fire."""
    others = [W.Actor("m1", *W.load_party("gre")), W.Actor("m2", *W.load_party("pan"))]
    user = W.Actor("user", *W.load_party(ucode))
    sim = W.Sim(); sim.attacker = user; user.target = user
    sim.actors = [user] + others
    sim.play(user, USER)
    fr, fired, clears = 0, None, {}
    while fr < 900:
        sim.frame = fr
        if fired is None and user.fx & 8 and all(x.busy == 0 for x in sim.actors):
            fired = fr
            for x in sim.actors:
                x.target = user; sim.play(x, 0x8016c3dc)
        before = {x.name: x.busy for x in sim.actors}
        sim.tick()
        for x in sim.actors:
            if before[x.name] and not x.busy and fired is not None:
                clears[x.name] = fr
        fr += 1
        if fired is not None and len(clears) == len(sim.actors):
            break
    hp = [f for f, _, w in sim.events if w == "HP CHANGE"][0]
    return {"fire": fired, "memberFreeAfterFire": clears["user"] - fired,
            "hpChangeAfterFire": hp - fired + 1}      # +1: the HP commits a tick later


def constants():
    """Engine-ready constants, with where each comes from (see docs Items.md)."""
    t = item_table("shu")
    inc = incense("shu")
    return {
        "healEffect": {"countdownFrames": [30, "code 0x800f215c"], "fadeFrames": [32, "code 0x800f26cc"],
                       "targetFreeAfterDone": [t["medicine"]["targetFree"], "simulated"],
                       "hpChangeAfterDone": [32, "simulated + live (McDohl)"]},
        "cureAntitoxin": {"targetFreeAfterDone": [t["antitoxin"]["targetFree"], "simulated"],
                          "statusBitClearedAfterDone": [31, "simulated"]},
        "cureNeedle": {"sequenceFrames": [10, "inferred: shared effect sheet seq 5"],
                       "targetFreeAfterDone": [t["needle"]["targetFree"], "simulated"],
                       "statusBitClearedAfterDone": [12, "simulated"]},
        "incense": {"fireAfterUserFree": [1, "code 0x800f09f0"],
                    "memberFreeAfterFire": [inc["memberFreeAfterFire"], "simulated"],
                    "hpChangeAfterFire": [inc["hpChangeAfterFire"], "simulated"],
                    "healAmount": [50, "code 0x800f215c variant 2"]},
        "noStatusUserFree": ["itemUserFreeAlly (script 0x8016c194 runs to its end)",
                             "simulated, equal for all 78"],
    }


def main():
    old = os.path.join(W.ROOT, "data/04_play")
    out = {}
    for code in sorted(f[:-4] for f in os.listdir(old) if f.endswith(".bin")):
        rid, name = W.party_identity(code)
        s, _ = run("medicine", code, code, True)
        a, _ = run("medicine", code, "shu" if code != "shu" else "cre", False)
        assert s["ub"][-1][0] - s["done"] == 64 and s["tb"][-1][0] == s["ub"][-1][0], code
        key = {"HERO": "MCDOHL"}.get(name.upper().replace(" ", "_"), name.upper().replace(" ", "_"))  # the game calls McDohl "Hero"
        out[key] = {"name": "McDohl" if key == "MCDOHL" else name, "id": rid, "itemDone": s["done"],
                     "itemUserFreeAlly": a["ub"][-1][0]}
    dest = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "outputs",
                        "CharacterItemTimings.json")
    json.dump(out, open(dest, "w"), indent=1)
    json.dump(constants(), open(os.path.join(os.path.dirname(dest), "ItemEffectConstants.json"), "w"),
              indent=1)
    print("wrote", len(out), "characters and ItemEffectConstants.json")


if __name__ == "__main__":
    main()
