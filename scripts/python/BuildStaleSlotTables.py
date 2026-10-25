#!/usr/bin/env python3
"""Build outputs/StaleSlotTables/: one CSV per screen of what each possible last party member would leave in
every actor slot of that screen's room table (the invisible-actor glitch; docs/game_mechanics/Invisible_Actor_Glitch.md).

  outputs/StaleSlotTables/
    index.csv                       every screen record: status, slots, table offset, path
    README.md
    wm_NN/area_NN[_Name]/screen_NN.csv

Each screen CSV: Character, Slot 1, Slot 2, ... ; cell = "X,Y" = the (X, Y) that slot would hold if it were the only
hidden slot. A `*` after the slot name means the static scan says that slot's NPC can be hidden by game state.
"-" = the slot lies outside the sprite buffer. Rows are every combat character (the last party member).

Inputs: the live sweep (SweepScreens.lua output), its targets JSON, outputs/RoomDescriptors.json (static scan).

  BuildStaleSlotTables.py SWEEP.txt TARGETS.json [--out outputs/StaleSlotTables]
"""
import argparse
import csv
import importlib.util
import json
import os
import re
import struct

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


iap = load("InvisActorPredict")
srd = load("ScanRoomDescriptors")
ana = load("AnalyzeScreenSweep")


README = """# Stale slot tables (invisible actor glitch)

One CSV per screen: what each possible LAST party member would leave in every actor slot of that screen's room.
Background and method: docs/game_mechanics/Invisible_Actor_Glitch.md. Regenerate with
scripts/python/BuildStaleSlotTables.py (needs the sweep data from scripts/SweepScreens.lua).

Layout: wm_NN/area_NN[_Name]/screen_NN.csv. Area names come from the zone spreadsheet (WM 0-3 only).
index.csv lists EVERY screen record with its status, slot count, hideable slots and table offset.

Per-screen CSV: first column = the last party member (every combat character); then one column per slot.
A cell "X,Y" is the (X, Y) that slot would hold if it were the ONLY hidden slot (which slot is hidden does not move
the table). A `*` after the slot name = the static scan says that slot's NPC can be hidden by game state (slots
without it are always present, so their X/Y is overwritten and never matters). "-" = outside the sprite buffer.
Characters that share a sprite sheet give identical rows. Hidden-slot X,Y is only meaningful if the NPC is hidden.

Status values in index.csv: ok; ok (loaded; screen runs an event on entry ...) = loaded but never reached the idle state
(table read at the end of the run); no slots = no actor table, nothing to analyse; could not enter = the teleport did
not load the screen, no CSV.

Caveats: offsets were measured by loading each screen through the game's own screen-change path and reading the heap;
a sample of 25 screens loaded from a second, unrelated start state gave identical offsets. Whether a stale (X, Y)
is a tile the hero can actually stand next to is NOT checked. Screens that no actor-linked descriptor uses have no table.
"""


def safe(name):
    return re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sweep")
    ap.add_argument("targets")
    ap.add_argument("--out", default=os.path.join(HERE, "..", "..", "outputs", "StaleSlotTables"))
    ap.add_argument("--extra", nargs=2, action="append", default=[], metavar=("SWEEP", "TARGETS"),
                    help="further sweep runs (e.g. a retry of failures); a run that succeeded for a screen wins")
    args = ap.parse_args()

    runs = [(args.sweep, args.targets)] + [tuple(e) for e in args.extra]
    scan = json.load(open(os.path.join(HERE, "..", "..", "outputs", "RoomDescriptors.json")))
    srd.load_char_names()
    chars = iap.load_characters()
    names = iap.names_by_id()
    iso = srd.Iso(srd.ISO)
    file_hdr = {}
    for lba, (path, size) in iso.files.items():
        b = os.path.basename(path).upper()
        if b.startswith("V") and b.endswith(".BIN"):
            file_hdr[b] = struct.unpack("<I", iso.sector(lba, 1)[:4])[0]

    # live result per (lba, screen); an "ok" from any run wins
    live = {}
    items = []
    for sweep_path, targets_path in runs:
        res_i = ana.parse_results(sweep_path)
        for i, t in enumerate(json.load(open(targets_path)), 1):
            items.append((t, res_i.get(i)))
    for t, r in items:
        st = "not swept"
        tbl = None
        if r is not None and "err" not in r:
            ok_overlay = int(r["hdr"], 16) == file_hdr.get(t["file"].upper(), -1)
            ok_ns = int(r["ns"]) == t["ns"]
            buf = int(r["bufLast"], 16)
            if not ok_overlay or (r["done"] != "true" and not (int(r["ns"]) == t["ns"] and int(r["table"], 16) >= 0x80100000)):
                st = "could not enter (teleport did not load the screen)"
            elif not ok_ns:
                st = "slot count mismatch"
            elif buf == 0:
                st = "no sprite buffer seen"
            else:
                st, tbl = "ok", (int(r["table"], 16) & 0x1FFFFF) - (buf & 0x1FFFFF)
                if r["done"] != "true":
                    st = "ok (loaded; screen runs an event on entry so the idle state was never reached)"
        elif r is not None:
            st = "error"
        k = (t["lba"], t["screen"])
        if k not in live or (st.startswith("ok") and not live[k][0].startswith("ok")):
            live[k] = (st, tbl, t["ns"])

    os.makedirs(args.out, exist_ok=True)
    index = []
    written = 0
    for s in sorted(scan, key=lambda s: (s["wm"], s["area"], s["screen"])):
        key = (s["lba"], s["screen"])
        ns = max([d["slot"] or 0 for d in s["descriptors"]] + [0])
        hideable = sorted({d["slot"] for d in s["descriptors"] if d["slot"] and d["can_hide"]})
        area_name = srd.AREA_NAMES.get((s["wm"], s["area"]), "")
        rel = os.path.join(f"wm_{s['wm']:02d}", f"area_{s['area']:02d}" + (f"_{safe(area_name)}" if area_name else ""), f"screen_{s['screen']:02d}.csv")
        row = {"wm": s["wm"], "area": s["area"], "area_name": area_name, "screen": s["screen"], "file": os.path.basename(s["file"]),
               "slots": ns, "hideable_slots": " ".join(map(str, hideable)), "table_offset": "", "status": "", "csv": ""}
        if ns == 0:
            row["status"] = "no slots (no actor table to analyse)"
        else:
            st, tbl, _ = live.get(key, ("not swept", None, ns))
            row["status"] = st
            if st.startswith("ok"):
                row["table_offset"] = hex(tbl)
                path = os.path.join(args.out, rel)
                os.makedirs(os.path.dirname(path), exist_ok=True)
                cells = iap._room_cells(chars, tbl, ns)
                with open(path, "w", newline="") as f:
                    w = csv.writer(f)
                    w.writerow(["Character"] + [f"Slot {k}{'*' if k in hideable else ''}" for k in range(1, ns + 1)])
                    for cid, cr in cells.items():
                        w.writerow([names.get(cid, str(cid))] + [f"{c[0]},{c[1]}" if c else "-" for c in cr])
                row["csv"] = rel.replace(os.sep, "/")
                written += 1
        index.append(row)

    with open(os.path.join(args.out, "index.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, list(index[0]))
        w.writeheader()
        w.writerows(index)
    with open(os.path.join(args.out, "README.md"), "w") as f:
        f.write(README)
    stat = {}
    for r in index:
        stat[r["status"]] = stat.get(r["status"], 0) + 1
    print(f"{written} CSVs written under {args.out}; {len(index)} screen records")
    for k, v in sorted(stat.items(), key=lambda kv: -kv[1]):
        print(f"  {v:>4}  {k}")


if __name__ == "__main__":
    main()
