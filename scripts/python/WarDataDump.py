#!/usr/bin/env python3
"""Dump the per-scenario data of the war battle overlays (data/16_war/war_*.bin).

The six "regular" overlays (kuwa, gara, sca2, kita, shas, last) share identical engine code at the
same addresses; only the data tables and a few immediates differ. This script locates the tables
from the lui/addiu address pairs inside the shared functions, so it works on all six.

Usage: scripts/python/WarDataDump.py [--iso-dir DIR]
"""
import re
import struct
import sys

ISO = "/mnt/Shared/ISOs/Suikoden/Suikoden Files/data/16_war/"
REGULAR = ["kuwa", "gara", "sca2", "kita", "shas", "last"]
BASE = 0x80010000


def load(n):
    return open(f"{ISO}war_{n}.bin", "rb").read()


def word(d, a):
    return struct.unpack("<I", d[a - BASE:a - BASE + 4])[0]


def s16(x):
    return x - 65536 if x & 0x8000 else x


def charmap():
    m = {}
    for l in open("/home/alex/Projects/Suikoden-Bizhawk-HUD/lib/Charmap.lua"):
        r = re.match(r"\s*\[0x([0-9a-fA-F]+)\]='(.*)',?\s*$", l)
        if r:
            m[int(r.group(1), 16)] = r.group(2)
    return m


CM = charmap()


def dec(b):
    return "".join(CM.get(x, "<%02x>" % x) for x in b).replace("\\'", "'")


def cstr(d, a):
    o = a - BASE
    return dec(d[o:d.index(b"\0", o)])


def addr_pairs(d, start, count):
    out = []
    for i in range(count):
        pc = start + 4 * i
        w = word(d, pc)
        if w >> 26 == 0x0f:
            rt = (w >> 16) & 31
            hi = w & 0xffff
            for j in range(1, 8):
                w2 = word(d, pc + 4 * j)
                op = w2 >> 26
                if ((w2 >> 21) & 31) == rt and op in (0x09, 0x0d, 0x23, 0x21, 0x20, 0x24, 0x25, 0x2b, 0x29, 0x28):
                    lo = w2 & 0xffff
                    out.append(((hi << 16) + (s16(lo) if op != 0x0d else lo)) & 0xffffffff)
                    break
    return out


def scenario(n):
    d = load(n)
    # enemy action pick (FUN_8001afdc) references the per-turn (min,max) pair table at +0/+1
    turn = [a for a in addr_pairs(d, 0x8001afdc, 30) if 0x80026000 < a < 0x80030000]
    turn_base = min(turn)
    # resolver (FUN_8001b610) references the action table at +0/+1 and the matchup matrix
    res = sorted({a for a in addr_pairs(d, 0x8001b610, 140) if 0x80026000 < a < 0x80030000})
    act_base = res[0]
    matrix = res[-1]
    cycle = 6 if n == "last" else 5
    nact = (turn_base - act_base) // 16
    acts = []
    for i in range(nact):
        o = act_base - BASE + i * 16
        typ, pw = d[o], d[o + 1]
        ptr = struct.unpack("<I", d[o + 4:o + 8])[0]
        acts.append((i, typ, pw, cstr(d, ptr), d[o + 12]))
    turns = [(d[turn_base - BASE + 2 * i], d[turn_base - BASE + 2 * i + 1]) for i in range(cycle)]
    mat = list(d[matrix - BASE:matrix - BASE + 9])
    # starting enemy count: ori rt,$zero,N at 0x800105e8
    enemy = word(d, 0x800105e8) & 0xffff
    per_sprite = word(d, 0x800183a4) & 0xffff
    return dict(name=n, act_base=act_base, turn_base=turn_base, matrix=matrix, actions=acts, turns=turns,
                mat=mat, enemy=enemy, per_sprite=per_sprite)


if __name__ == "__main__":
    for n in REGULAR:
        s = scenario(n)
        print(f"== {n}: enemy start {s['enemy']}, soldiers per sprite {s['per_sprite']}, "
              f"actions @{s['act_base']:#x}, turn script @{s['turn_base']:#x}, matrix @{s['matrix']:#x} {s['mat']}")
        for i, t, p, nm, x in s["actions"]:
            print(f"   action {i}: type {'CBM'[t] if t < 3 else t} power {p} '{nm}' (+0xc={x:#x})")
        print("   turn script:", " ".join(f"T{i+1}:{a}-{b}" for i, (a, b) in enumerate(s["turns"])))
