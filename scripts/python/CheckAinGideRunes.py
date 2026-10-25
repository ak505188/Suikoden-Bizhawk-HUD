# Offline check of scripts/TestAinGideRunes.lua: predicts each member's Special damage from
# calc_rune_element_attack_damage (element = 1) and compares with the observed HP drops.
#   base = 410 - target MGC; variance (one roll per living member, in slot order, after the 48
#   particle rolls); halve if rune category == 1 (Fire/Rage), == 7 (Soul Eater), or - the compiled
#   $s1 bug - the Rune.Id is unlisted and the party slot == 1.
import re, sys, collections
OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestAinGideRunes.txt"
M = 1 << 32
CAT = {1: 7, 2: 1, 0x1b: 1, 3: 2, 0x1c: 2, 6: 3, 0x1e: 3, 5: 4, 0x1f: 4, 4: 5, 0x1d: 5, 7: 6}
ELEMENT = 1


def nxt(s): return (s * 0x41c64e6d + 0x3039) % M
def rng2(s): return (s >> 16) & 0x7fff
def cdiv(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def predict(seed, mgcs, runes, att=410):
    # move selection: 3 front-row candidates
    calls = 0
    while True:
        tgt = None
        for _ in range(3):
            seed = nxt(seed)
            if rng2(seed) % 100 > 50:
                tgt = 1; break
        if tgt: break
    seed = nxt(seed)
    assert (rng2(seed) * 100) // 32767 >= 0x33, "not a Special"
    for _ in range(48): seed = nxt(seed)
    res = []
    for i, (mg, ru) in enumerate(zip(mgcs, runes), 1):
        seed = nxt(seed); r = rng2(seed)
        base = att - mg
        dmg = base + 1 - r % 4 if base < 10 else base + cdiv(base // 2 - r % base, 5)
        cat = CAT.get(ru)
        bug = cat is None and i == ELEMENT
        if cat == ELEMENT or cat == 7 or bug:
            dmg = cdiv(dmg, 2)
        res.append((max(dmg, 1), "bug" if bug else ("real" if cat in (ELEMENT, 7) else "")))
    return res


ok = bad = 0
tally = collections.Counter()
runs = re.split(r"(?m)^RUN ", open(OUT).read())[1:]
for blk in runs:
    lines = blk.strip().split("\n")
    h = re.match(r"(s\d+) (\S+) T0seed=([0-9a-f]+) special=(\w+)", lines[0])
    if not h or h.group(4) != "true" or "NO DAMAGE" in lines[0]:
        print("skip", lines[0]); continue
    mg, ru, drop = [], [], []
    for l in lines[1:]:
        m = re.match(r"\s+m (\d+) pos (\d+) rune (\d+) mgc (\d+) drop (\d+)", l)
        ru.append(int(m.group(3))); mg.append(int(m.group(4))); drop.append(int(m.group(5)))
    pred = predict(int(h.group(3), 16), mg, ru)
    good = [p[0] for p in pred] == drop
    ok += good; bad += not good
    for p, d in zip(pred, drop):
        if p[1]: tally[(p[1], p[0] == d)] += 1
    if not good:
        print("MISMATCH", lines[0], "\n  pred", pred, "\n  obs ", drop)
print("runs exact: %d / %d" % (ok, ok + bad))
print("halvings by cause (cause, matched):", dict(tally))
