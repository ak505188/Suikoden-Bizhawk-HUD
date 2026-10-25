#!/usr/bin/env python3
"""Dump per-room random-encounter blocks (rate, grace, groups) from the disc.

Static: reads main.exe's field-file descriptor table and the cooked ISO.
Chain (see docs/game_mechanics/Battles_and_Encounters.md):
  main.exe 0x8016f67c[region] -> [area] -> {size, lba} descriptor
  file[0] = header H; H+4 = room-ptr table; H+8 = 0x10-byte entry table
  entry byte5 = room idx; room+0x38 = encounter block
  block: u8 rate @0, u8 grace @2, ptr table @4; table+8 -> {count, ptrs}
Pointers are absolute, file loaded at 0x80010000.

Usage: dump_encounter_blocks.py [--root DIR]  (default: /mnt/Shared/ISOs/Suikoden)
"""
import struct
import sys
from collections import defaultdict

ROOT = sys.argv[sys.argv.index("--root") + 1] if "--root" in sys.argv else "/mnt/Shared/ISOs/Suikoden"
EXE = open(f"{ROOT}/Suikoden Files/main.exe", "rb").read()
ISO = open(f"{ROOT}/Suikoden.iso01.iso", "rb")
BASE = 0x80010000


def exe_u32(a):
    o = a - 0x800C0800 + 0x800
    return struct.unpack("<I", EXE[o:o + 4])[0]


def descriptors():
    regs = [exe_u32(0x8016F67C + 4 * i) for i in range(12)]
    out = {}
    for ri, r in enumerate(regs):
        n = (regs[ri + 1] - r) // 4 if ri < 11 else 8
        for ai in range(n):
            p = exe_u32(r + 4 * ai)
            if p:
                out[(ri, ai)] = (exe_u32(p), exe_u32(p + 4))  # size, lba
    return out


def main():
    for (ri, ai), (size, lba) in sorted(descriptors().items()):
        ISO.seek(lba * 2048)
        b = ISO.read(size)
        u32 = lambda a: struct.unpack_from("<I", b, a - BASE)[0]
        ok = lambda a: BASE <= a < BASE + len(b) - 3
        H = u32(BASE)
        if not ok(H):
            continue
        cnt, rt, et = u32(H), u32(H + 4), u32(H + 8)
        rooms = defaultdict(list)
        for i in range(cnt):
            eo = et - BASE + 16 * i
            if eo + 16 > len(b):
                break
            room = u32(rt + 4 * b[eo + 5]) if ok(rt + 4 * b[eo + 5]) else 0
            if not ok(room):
                continue
            e = u32(room + 0x38)
            if not ok(e):
                continue
            t = u32(e + 4)
            if not ok(t) or not ok(u32(t + 8)):
                continue
            groups = u32(u32(t + 8))
            if groups == 0 or groups > 32:  # reject non-encounter garbage
                continue
            rooms[(b[e - BASE], b[e - BASE + 2], groups, t)].append(b[eo + 5])
        for (rate, grace, groups, t), rs in rooms.items():
            print(f"region {ri:2} area {ai:2}  rate {rate}  grace {grace:2}  "
                  f"groups {groups:2}  table {t:#x}  rooms {sorted(set(rs))}")


if __name__ == "__main__":
    main()
