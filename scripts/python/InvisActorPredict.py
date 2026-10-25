#!/usr/bin/env python3
"""Predict what the "invisible actor" glitch writes into a hidden room slot, for any character.

Background (docs/game_mechanics/Invisible_Actor_Glitch.md): every field screen load decompresses the
party's sprite sheets into one 16 KB heap buffer, in formation order. When it is freed, the room's actor
table is carved out of the same memory without clearing it, so a *hidden* slot (+0x14 == 0xFF; X/Y/+2..+7/
+0x15..+0x17 never written) keeps whatever bytes of the LAST formation member's sprite sheet lay there.

This script decompresses every character's sprite sheet straight from the disc (data/04_play/*.bin, byte 0 =
character id) with disc_extract/lzss.py, so it needs no emulator.

  InvisActorPredict.py offset 0x3908 [--slot N]
      For every character as the last party member, show the 24 bytes a slot whose address is `offset` bytes
      into the buffer would hold (X, Y, +0x15..+0x17). --slot N shifts by (N-1)*0x18 from a table offset.
  InvisActorPredict.py where X Y [--offset 0x3908] [--tolerance]
      Which characters, as last member, put (X, Y) in the slot at that offset.
  InvisActorPredict.py room --table-off 0x3908 --slots 3 [--hidden 1,2]
      Every slot of a room at once: for each character as last member, the stale bytes of EVERY slot. A hidden
      slot keeps X, Y, +2..+7 and +0x15..+0x17; a present slot only keeps +0x17 (the builder writes the rest).
      --table-off is the room table's offset in the sprite buffer (outputs/ScreenSweep.csv `table_off`, or
      `state`); --hidden lists slots that are (or may be) hidden.
  InvisActorPredict.py table --wm W --area A --screen S [--csv FILE] [--table-off HEX --slots N]
      The per-room deliverable: rows = every combat character as last member, columns = every slot of the room,
      cell = the (X,Y) that slot would hold *if it were the only hidden slot*. (Which slot is hidden does not move
      the table, so the columns are independent.) Columns marked * are slots whose NPC can be hidden per the static
      scan. Table offset and slot count come from outputs/ScreenSweep.csv (or --table-off/--slots).
  InvisActorPredict.py table-all --csv outputs/StaleSlotXY.csv
      The same for every swept screen, long format: one row per (screen, slot, character).
  InvisActorPredict.py state FILE.State
      Read a savestate's room table; for every hidden slot print its offset in the sprite buffer (found by
      matching the last party member's decompressed sheet against RAM), the predicted vs actual bytes, and
      the hero tiles from which that stale (X, Y) can be talked to.
"""
import argparse
import glob
import json
import os
import struct
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "disc_extract"))
from lzss import lz_decompress  # noqa: E402

PLAY_DIR = "/mnt/Shared/ISOs/Suikoden/Suikoden Files/data/04_play"
RAM_OFFSET_IN_CORE = 0x1CB18  # MainRAM start inside a BizHawk Nymashock Core.bin (after zstd)
SLOT = 0x18


def u32(d, a):
    return struct.unpack_from("<I", d, a)[0]


def load_characters():
    """{char_id: (file_name, [decompressed textures])}"""
    chars = {}
    for p in sorted(glob.glob(os.path.join(PLAY_DIR, "*.bin"))):
        d = open(p, "rb").read()
        hdr = u32(d, 0x28)  # sprite header; +4 = texture count, +8 = pointer array (file-relative)
        arr = u32(d, hdr + 8)
        texs = []
        for i in range(d[hdr + 4]):
            t = u32(d, arr + 4 * i)
            texs.append(lz_decompress(d[t + 4 : t + 4 + u32(d, t)]))
        chars[d[0]] = (os.path.basename(p), texs)
    return chars


def names_by_id():
    """Character names from lib/Characters/Addresses.lua (Names.X = id)."""
    import re

    lua = open(os.path.join(HERE, "..", "..", "lib", "Characters", "Addresses.lua")).read()
    out = {}
    for name, body in re.findall(r"\[Names\.(\w+)\] = \{(.*?)\n  ?\},?", lua, re.S):
        m = re.search(r"Id = (\d+)", body)
        if m:
            out[int(m.group(1))] = name.title()
    return out


def slot_bytes(sheet, off):
    return sheet[off : off + SLOT] if 0 <= off <= len(sheet) - SLOT else None


def cmd_offset(args, chars, names):
    off = int(args.offset, 0) + (args.slot - 1) * SLOT
    print(f"buffer offset {off:#x} (row {off // 0x80}, col {off % 0x80})")
    print(f"{'char':<12} {'id':>3} {'file':<8}  bytes 0-7                X   Y   +15 +16 +17")
    for cid in sorted(chars):
        sheet = chars[cid][1][-1]  # only a member's LAST texture stays in the buffer
        b = slot_bytes(sheet, off)
        if b is None:
            print(f"{names.get(cid, '?'):<12} {cid:>3}  (offset outside the 0x4000 buffer)")
            continue
        print(f"{names.get(cid, '?'):<12} {cid:>3} {chars[cid][0]:<8}  {b[:8].hex(' ')}  {b[0]:>3} {b[1]:>3}   {b[0x15]:02x}  {b[0x16]:02x}  {b[0x17]:02x}")


def cmd_where(args, chars, names):
    off = int(args.offset, 0)
    for cid in sorted(chars):
        b = slot_bytes(chars[cid][1][-1], off)
        if b is None:
            continue
        if (b[0], b[1]) == (args.x, args.y) or (args.tolerance and abs(b[0] - args.x) <= 1 and abs(b[1] - args.y) <= 1):
            print(f"{names.get(cid, '?'):<12} id {cid:>3}: bytes {b[:8].hex(' ')}")


def cmd_room(args, chars, names):
    tbl = int(args.table_off, 0)
    hidden = {int(h) for h in args.hidden.split(",") if h}
    groups = {}
    for cid in sorted(chars):
        sheet = chars[cid][1][-1]
        cells = []
        for k in range(1, args.slots + 1):
            b = slot_bytes(sheet, tbl + (k - 1) * SLOT)
            if b is None:
                cells.append("outside")
            elif k in hidden:
                cells.append(f"({b[0]},{b[1]}) +2..7={b[2:8].hex()} +15..17={b[0x15:0x18].hex()}")
            else:
                cells.append(f"+17={b[0x17]:02x}")
        groups.setdefault(tuple(cells), []).append(names.get(cid, str(cid)))
    print(f"table at buffer offset {tbl:#x}, {args.slots} slots, hidden {sorted(hidden) or 'none'}; "
          f"{len(groups)} distinct outcomes over {len(chars)} characters")
    for cells, who in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        print("  " + " | ".join(f"slot{k}: {c}" for k, c in enumerate(cells, 1)))
        print("      last member: " + ", ".join(who))


def _load_sweep_and_scan():
    import csv
    out = os.path.join(HERE, "..", "..", "outputs")
    sweep = {}
    for r in csv.DictReader(open(os.path.join(out, "ScreenSweep.csv"))):
        if r.get("status") == "ok":
            sweep[(int(r["wm"]), int(r["area"]), int(r["screen"]))] = r
    scan = {}
    for s in json.load(open(os.path.join(out, "RoomDescriptors.json"))):
        scan[(s["wm"], s["area"], s["screen"])] = s
    return sweep, scan


def _room_cells(chars, tbl, nslots):
    """{cid: [(x, y) or None per slot]}"""
    res = {}
    for cid in sorted(chars):
        sheet = chars[cid][1][-1]
        row = []
        for k in range(nslots):
            b = slot_bytes(sheet, tbl + k * SLOT)
            row.append((b[0], b[1]) if b else None)
        res[cid] = row
    return res


def cmd_table(args, chars, names):
    sweep, scan = _load_sweep_and_scan()
    key = (args.wm, args.area, args.screen)
    if args.table_off is not None:
        tbl, nslots = int(args.table_off, 0), args.slots
    elif key in sweep:
        tbl, nslots = int(sweep[key]["table_off"]), int(sweep[key]["ns"])
    else:
        sys.exit(f"{key} is not in outputs/ScreenSweep.csv; pass --table-off and --slots")
    can = {d["slot"] for d in scan.get(key, {}).get("descriptors", []) if d["can_hide"] and d["slot"]}
    cells = _room_cells(chars, tbl, nslots)
    head = ["Character"] + [f"Slot {k}{'*' if k in can else ''}" for k in range(1, nslots + 1)]
    rows = [[names.get(cid, str(cid))] + [f"{c[0]},{c[1]}" if c else "-" for c in row] for cid, row in cells.items()]
    if args.csv:
        import csv
        with open(args.csv, "w", newline="") as f:
            w = csv.writer(f); w.writerow(head); w.writerows(rows)
        print(f"wrote {args.csv}")
    print(f"wm{args.wm}/area{args.area}/screen{args.screen}: table at buffer offset {tbl:#x}, {nslots} slots (* = can be hidden)")
    widths = [max(len(str(x)) for x in col) for col in zip(head, *rows)]
    for r in [head] + rows:
        print("  ".join(str(x).ljust(w) for x, w in zip(r, widths)).rstrip())


def cmd_table_all(args, chars, names):
    import csv
    sweep, scan = _load_sweep_and_scan()
    n = 0
    with open(args.csv, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["wm", "area", "screen", "file", "table_off", "slot", "can_hide", "character", "char_id", "x", "y"])
        for key, r in sorted(sweep.items()):
            tbl, nslots = int(r["table_off"]), int(r["ns"])
            can = {d["slot"] for d in scan.get(key, {}).get("descriptors", []) if d["can_hide"] and d["slot"]}
            cells = _room_cells(chars, tbl, nslots)
            for cid, row in cells.items():
                for k, c in enumerate(row, 1):
                    w.writerow([*key, r["file"], hex(tbl), k, int(k in can), names.get(cid, cid), cid, c[0] if c else "", c[1] if c else ""])
                    n += 1
    print(f"wrote {n} rows for {len(sweep)} screens to {args.csv}")


def interact_positions(x, y):
    """Hero tiles/facings that talk to an actor slot at (x, y): from FUN_8013d3cc + its offset tables."""
    pos = [(x, y - 2, "DOWN"), (x - 1, y - 2, "DOWN"), (x + 1, y - 2, "DOWN")]  # slotY = heroY+2, |dx|<=1
    pos += [(x, y + 1, "UP"), (x - 1, y + 1, "UP"), (x + 1, y + 1, "UP")]  # slotY = heroY-1
    for hy in (y - 1, y):  # slotY in [heroY, heroY+1]
        pos.append((x + 2, hy, "LEFT"))  # slotX = heroX-2
        pos.append((x - 2, hy, "RIGHT"))  # slotX = heroX+2
    return pos


def state_ram(path):
    core = zipfile.ZipFile(path).read("Core.bin")
    raw = subprocess.run(["zstd", "-dc"], input=core, capture_output=True, check=True).stdout
    return raw[RAM_OFFSET_IN_CORE : RAM_OFFSET_IN_CORE + 0x200000]


def cmd_state(args, chars, names):
    r = state_ram(args.file)
    rd = lambda a: u32(r, a & 0x1FFFFF)
    ptr, count = rd(0x17DAA0), r[0x17DBFC]
    form = [r[0x1B800E + i] for i in range(r[0x1B8003])]
    ids = [r[0x1B8008 + i] for i in range(6)]
    last_id = ids[form[-1]]
    print(f"area/screen/wm {tuple(r[0x1B8000:0x1B8003])}  table {ptr:#x}  slots {count}  formation {[ids[s] for s in form]}  last = {names.get(last_id, '?')} ({last_id})")
    sheet = chars[last_id][1][-1]
    # The sheet can sit in the heap more than once (older copies of the same decompress); prefer the one
    # whose 0x4000 bytes contain the room table, since that is the memory the table was carved from.
    matches = [b for b in range(0x180000, 0x19A000 - 0x4000, 8) if r[b : b + 0x400] == sheet[:0x400]]
    tbl = ptr & 0x1FFFFF
    base = next((b for b in matches if b <= tbl < b + 0x4000), matches[0] if matches else None)
    print(f"sprite buffer in this state: {('%#x' % (0x80000000 + base)) if base else 'not found (already overwritten / not a freshly loaded screen)'}")
    for i in range(count):
        a = (ptr & 0x1FFFFF) + i * SLOT
        s = r[a : a + SLOT]
        hidden = s[0x14] == 0xFF
        line = f"slot {i + 1}: ({s[0]},{s[1]}) id {s[0x14]:02x}{' HIDDEN' if hidden else ''}"
        if base is not None:
            off = a - base
            pred = slot_bytes(sheet, off)
            line += f"  buffer offset {off:#x}" + (f" predicted {pred[:8].hex(' ')} actual {s[:8].hex(' ')}" if pred and hidden else "")
        print(line)
        if hidden:
            print("   talk-able from (heroX, heroY, facing):", ", ".join(f"({px},{py},{d})" for px, py, d in interact_positions(s[0], s[1])))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("offset"); p.add_argument("offset"); p.add_argument("--slot", type=int, default=1); p.set_defaults(fn=cmd_offset)
    p = sub.add_parser("where"); p.add_argument("x", type=int); p.add_argument("y", type=int); p.add_argument("--offset", default="0x3908"); p.add_argument("--tolerance", action="store_true"); p.set_defaults(fn=cmd_where)
    p = sub.add_parser("room"); p.add_argument("--table-off", required=True); p.add_argument("--slots", type=int, required=True); p.add_argument("--hidden", default=""); p.set_defaults(fn=cmd_room)
    p = sub.add_parser("table"); p.add_argument("--wm", type=int, required=True); p.add_argument("--area", type=int, required=True); p.add_argument("--screen", type=int, required=True); p.add_argument("--csv"); p.add_argument("--table-off"); p.add_argument("--slots", type=int); p.set_defaults(fn=cmd_table)
    p = sub.add_parser("table-all"); p.add_argument("--csv", required=True); p.set_defaults(fn=cmd_table_all)
    p = sub.add_parser("state"); p.add_argument("file"); p.set_defaults(fn=cmd_state)
    args = ap.parse_args()
    args.fn(args, load_characters(), names_by_id())


if __name__ == "__main__":
    main()
