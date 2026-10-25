#!/usr/bin/env python3
"""Static scan of every field screen's actor descriptors, straight from the disc (no emulator).

How the game finds a screen (all verified against live RAM, see notes/Invisible_Actor_Glitch.md):
  * main.exe table PTR_PTR_8016F67C[WM_ZONE][AREA_ZONE] -> record {u32 size, u32 LBA} of the area overlay.
  * The overlay loads at 0x80010000. u32 @0 -> header H. H+8 -> screen-record array, one 0x10-byte record per
    SCREEN_ZONE: +0 descriptor array ptr, +4 u8 descriptor count, +5 u8 resource index, +7 u8 flags.
  * Descriptor (0x18 bytes): +0 X, +2 Y, +4 u16 flags, +6 u16 sprite/char id, +8 slot byte (runtime),
    +0xC ptr to appearance-condition bytecode, +0x10/+0x14 other ptrs.
  * room_build_actor_table (0x8012ed84) gives a descriptor with (flags & 0x101) a slot iff its condition
    evaluates to 0 (present) or 2 (HIDDEN). Hidden slots keep stale heap bytes: the invisible-actor glitch.

Condition bytecode (FUN_8013d8e0; lengths from FUN_801345dc), list ends with 06 <sortParam> <initialDir>:
  07/08/09/0A id mask : event-flag byte (07,08 = array gs+0x190; 09,0A = gs+0x280) & mask  set/clear/set/clear
  0E id / 0F id       : character id in / NOT in the party
  10 id               : recruit-state[id] bit0 set and bit1 clear
  11 id               : recruit-state[id] bit0 clear and bit1 clear
  19 id               : recruit-state[id] bit0 or bit1 set
  13 id lvl           : character id level >= lvl
  14 x lvl            : castle level >= lvl
  15 n                : random, present ~1/(n+1) of the time
  16 n                : FUN_801395ac() >= n (count of something; unidentified)
  01-05,0B,0C,0D,12,17,18 : result 1 (alias: no slot of its own)
  anything else       : result 2 (hidden)

Usage: ScanRoomDescriptors.py [--json outputs/RoomDescriptors.json] [--csv] [--wm N --area N --screen N]
"""
import argparse
import json
import os
import struct
import sys

ROOT = "/mnt/Shared/ISOs/Suikoden"
ISO = ROOT + "/Suikoden.iso01.iso"
MAIN = ROOT + "/Suikoden Files/main.exe"
MAIN_LOAD = 0x800C0800
ZONE_TABLE = 0x8016F67C
OVL_BASE = 0x80010000
RECORD_LO, RECORD_HI = 0x80163D00, 0x80164900  # where the {size, LBA} records live in main.exe

# (WM, area) -> name, from the user's zone spreadsheet. The sheet only covers WM 0-3; other WMs have no names.
AREA_NAMES = {
    (0, 0): "Gregminster", (0, 1): "Rockland", (0, 2): "Lenankamp", (0, 3): "Magician's Island", (0, 4): "Sarady",
    (0, 5): "Kwaba", (0, 6): "Mt. Seifu", (0, 7): "Mt. Tigerwolf (bottom)", (0, 8): "Mt. Tigerwolf (top)",
    (0, 9): "Gregminster Palace", (1, 0): "Seika", (1, 1): "Kaku", (1, 2): "Kouan", (1, 3): "Garan",
    (1, 4): "Great Forest", (1, 7): "Kwaba", (1, 41): "Where You Fight Teo", (2, 0): "Dwarf Trail", (2, 7): "Dwarf Trail",
    (2, 2): "Dwarves' Vault", (2, 3): "Village of the Dwarves/Elves", (2, 4): "Burnt Village of the Elves",
    (2, 5): "Pannu Yakuta", (2, 6): "Great Forest", (3, 0): "Antei", (3, 1): "Teien", (3, 2): "Rikon",
    (3, 3): "Sonierre", (3, 4): "Scarletia", (3, 5): "Northern Checkpoint", (3, 6): "Garan", (3, 7): "Lorimar",
    (3, 8): "Dragon's Den",
}
CHAR_NAMES = {}


def load_char_names():
    import re

    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib", "Characters", "Addresses.lua")
    for name, body in re.findall(r"\[Names\.(\w+)\] = \{(.*?)\n  ?\},?", open(path).read(), re.S):
        m = re.search(r"Id = (\d+)", body)
        if m:
            CHAR_NAMES[int(m.group(1))] = name.title().replace("_", " ")


def cname(i):
    return f"{CHAR_NAMES[i]}({i})" if i in CHAR_NAMES else f"char{i}"


LEN3 = {0x01, 0x02, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x13, 0x14}
LEN2 = {0x04, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x15, 0x16, 0x19}
ALIAS = {0x01, 0x02, 0x03, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x12, 0x17, 0x18}


def u32(d, a):
    return struct.unpack_from("<I", d, a)[0]


def u16(d, a):
    return struct.unpack_from("<H", d, a)[0]


class Iso:
    def __init__(self, path):
        self.f = open(path, "rb")
        pvd = self.sector(16)
        assert pvd[1:6] == b"CD001"
        self.files = {}
        self._walk(u32(pvd, 158), u32(pvd, 166), "/")

    def sector(self, n, cnt=1):
        self.f.seek(n * 2048)
        return self.f.read(2048 * cnt)

    def _walk(self, lba, size, path):
        data = self.sector(lba, (size + 2047) // 2048)
        i = 0
        while i < len(data):
            ln = data[i]
            if ln == 0:
                i = (i // 2048 + 1) * 2048
                continue
            rec = data[i : i + ln]
            i += ln
            elba, esize, flags, nl = u32(rec, 2), u32(rec, 10), rec[25], rec[32]
            name = rec[33 : 33 + nl].decode("latin1").split(";")[0]
            if name in ("\x00", "\x01"):
                continue
            if flags & 2:
                self._walk(elba, esize, path + name + "/")
            else:
                self.files[elba] = (path + name, esize)


def zone_table(main):
    """[(wm, area, size, lba)] for every non-empty entry."""
    off = lambda a: a - MAIN_LOAD + 0x800
    wm_ptrs = [u32(main, off(ZONE_TABLE + 4 * i)) for i in range(12)]
    starts = sorted(set(wm_ptrs))
    out = []
    for wm, p in enumerate(wm_ptrs):
        nxt = min([s for s in starts if s > p] + [p + 0x100])
        for area in range((nxt - p) // 4):
            rec = u32(main, off(p + 4 * area))
            if RECORD_LO <= rec < RECORD_HI:
                out.append((wm, area, u32(main, off(rec)), u32(main, off(rec + 4))))
    return out


def decode_condition(ovl, ptr):
    """Returns (text, can_hide, alias, sortParam, initialDir)."""
    if ptr == 0:
        return "(no condition)", False, True, None, None  # FUN_8013d8e0(NULL) = 1 = alias
    p = ptr - OVL_BASE
    parts, can_hide, alias = [], False, False
    while 0 <= p < len(ovl):
        op = ovl[p]
        if op == 0x06:
            return " & ".join(parts) or "always", can_hide, alias, ovl[p + 1], ovl[p + 2]
        n = 3 if op in LEN3 else 2 if op in LEN2 else 1
        a, b = (ovl[p + 1] if n > 1 else None), (ovl[p + 2] if n > 2 else None)
        if op in ALIAS:
            parts.append(f"ALIAS(op{op:02x})"); alias = True
            return " & ".join(parts), can_hide, alias, None, None  # the game returns 1 here, ignoring the rest
        elif op in (0x07, 0x09):
            parts.append(f"evflag{'A' if op == 7 else 'B'}[{a}]&{b:#04x} set"); can_hide = True
        elif op in (0x08, 0x0A):
            parts.append(f"evflag{'A' if op == 8 else 'B'}[{a}]&{b:#04x} clear"); can_hide = True
        elif op == 0x0E:
            parts.append(f"{cname(a)} in party"); can_hide = True
        elif op == 0x0F:
            parts.append(f"{cname(a)} NOT in party"); can_hide = True
        elif op == 0x10:
            parts.append(f"{cname(a)} recruited,not gone"); can_hide = True
        elif op == 0x11:
            parts.append(f"{cname(a)} not recruited"); can_hide = True
        elif op == 0x19:
            parts.append(f"{cname(a)} state b0|b1 set"); can_hide = True
        elif op == 0x13:
            parts.append(f"{cname(a)} lvl>={b}"); can_hide = True
        elif op == 0x14:
            parts.append(f"castle lvl>={b}"); can_hide = True
        elif op == 0x15:
            parts.append(f"random 1/{a + 1}"); can_hide = True
        elif op == 0x16:
            parts.append(f"count>={a}"); can_hide = True
        else:
            parts.append(f"ALWAYS HIDDEN (op{op:02x})"); can_hide = True
            return " & ".join(parts), can_hide, alias, None, None  # the game returns 2 here
        p += n
    return "(unterminated)", can_hide, alias, None, None


def parse_overlay(ovl):
    """Yield (screen_index, resource_index, [descriptor dict])."""
    hdr = u32(ovl, 0) - OVL_BASE
    if not (0 <= hdr < len(ovl) - 0x10):
        return
    tab = u32(ovl, hdr + 8) - OVL_BASE
    if not (0 <= tab < len(ovl) - 0x10):
        return
    screens = []
    for i in range(0, 64):
        rec = tab + 0x10 * i
        if rec < 0 or rec + 0x10 > len(ovl):
            break
        dptr, count, res = u32(ovl, rec), ovl[rec + 4], ovl[rec + 5]
        dp = dptr - OVL_BASE
        # A real record has +7 < 0x10, +10/+11 == 0 and +0xC null or an aligned in-overlay pointer, and either a
        # valid descriptor array or (dptr == 0 and count == 0) for a screen with no actor list. Reading past the
        # end of the array lands on unrelated data that fails these (checked against the zone sheet).
        p0c = u32(ovl, rec + 0xC)
        tail_ok = p0c == 0 or (OVL_BASE <= p0c < OVL_BASE + len(ovl) and p0c & 3 == 0)
        empty = dptr == 0 and count == 0
        arr_ok = 0 <= dp < len(ovl) and dp & 3 == 0 and dp + 0x18 * count <= len(ovl)
        if not any(ovl[rec : rec + 16]):  # an all-zero record terminates the array
            break
        if not (empty or arr_ok) or ovl[rec + 7] >= 0x10 or ovl[rec + 10] != 0 or ovl[rec + 11] != 0 or not tail_ok:
            break
        descs = []
        slot = 0
        for j in range(count if not empty else 0):
            a = dp + 0x18 * j
            flags = u16(ovl, a + 4)
            cptr = u32(ovl, a + 0xC)
            text, can_hide, alias, sortp, ddir = decode_condition(ovl, cptr) if flags & 0x181 else ("-", False, False, None, None)
            linked = bool(flags & 0x101)
            makes_slot = linked and not alias
            d = {
                "i": j, "x": ovl[a], "y": ovl[a + 2], "flags": flags, "sprite": u16(ovl, a + 6),
                "actor_linked": linked, "condition": text, "can_hide": linked and can_hide,
                "alias": alias, "slot": (slot + 1) if makes_slot else None,
                "ptr10": u32(ovl, a + 0x10), "ptr14": u32(ovl, a + 0x14),
            }
            if makes_slot:
                slot += 1
            descs.append(d)
        screens.append({"screen": i, "resource": res, "count": count, "descriptors": descs})
    return screens


def write_report(path, result):
    cand = lambda s: [d for d in s["descriptors"] if d["can_hide"] and d["slot"]]
    lines = ["# Screens with a conditional actor-linked NPC (can become a hidden slot)", "",
             "Generated by `scripts/python/ScanRoomDescriptors.py --report`. Static scan of the disc; whether an NPC is",
             "hidden at runtime depends on the save (recruitment / event flags). `slot` = its slot index when the",
             "room is built (hidden or not, it keeps this slot). Only the lowest-index hidden slot is ever read by",
             "the interaction check. Area names come from the zone spreadsheet (WM 0-3 only).", ""]
    seen, n = set(), 0
    for s in result:
        c = cand(s)
        key = (s["lba"], s["screen"])
        if not c or key in seen:
            continue
        seen.add(key)
        n += 1
        same = sorted({(x["wm"], x["area"]) for x in result if x["lba"] == s["lba"] and x["screen"] == s["screen"]})
        names = ", ".join(f"wm{w}/area{a} {AREA_NAMES.get((w, a), '')}".strip() for w, a in same)
        lines.append(f"## {names} - screen {s['screen']} ({os.path.basename(s['file'])}, {s['count']} descriptors)")
        for d in c:
            lines.append(f"- slot {d['slot']} d{d['i']} at ({d['x']},{d['y']}) sprite {d['sprite']} flags {d['flags']:#06x}: shown if {d['condition']}")
        lines.append("")
    lines.insert(1, f"{n} screens.")
    open(path, "w").write("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json")
    ap.add_argument("--wm", type=int)
    ap.add_argument("--area", type=int)
    ap.add_argument("--screen", type=int)
    ap.add_argument("--report", help="write a markdown candidate list")
    ap.add_argument("--all", action="store_true", help="also list screens with nothing that can hide")
    args = ap.parse_args()

    load_char_names()
    iso = Iso(ISO)
    main_exe = open(MAIN, "rb").read()
    result = []
    cache = {}
    for wm, area, size, lba in zone_table(main_exe):
        if args.wm is not None and wm != args.wm or args.area is not None and area != args.area:
            continue
        name = iso.files.get(lba, ("?", 0))[0]
        if lba not in cache:
            try:
                cache[lba] = parse_overlay(iso.sector(lba, (size + 2047) // 2048)[:size]) or []
            except (struct.error, IndexError):
                cache[lba] = []
        for s in cache[lba]:
            if args.screen is not None and s["screen"] != args.screen:
                continue
            result.append({"wm": wm, "area": area, "file": name, "lba": lba, **s})

    cand = lambda s: [d for d in s["descriptors"] if d["can_hide"]]
    print(f"{len(cache)} overlays, {len(result)} (wm,area,screen) entries")
    n = 0
    for s in result:
        c = cand(s)
        if not c and not args.all:
            continue
        n += 1
        print(f"wm {s['wm']:>2} area {s['area']:>2} screen {s['screen']:>2} {AREA_NAMES.get((s['wm'], s['area']), ''):<24}{os.path.basename(s['file'])}  {s['count']} descriptors, {len(c)} can hide")
        for d in c if not args.all else s["descriptors"]:
            print(f"    d{d['i']} slot {d['slot']} at ({d['x']},{d['y']}) flags {d['flags']:#06x} sprite {d['sprite']}  if {d['condition']}")
    print(f"{n} screens have a conditional actor-linked descriptor")
    if args.json:
        json.dump(result, open(args.json, "w"), indent=1)
    if args.report:
        write_report(args.report, result)


if __name__ == "__main__":
    main()
