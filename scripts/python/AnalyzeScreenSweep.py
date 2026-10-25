#!/usr/bin/env python3
"""Analyse SweepScreens.lua output against the static scan.

  AnalyzeScreenSweep.py SWEEP.txt TARGETS.json [--csv out.csv]

Per target: did the right overlay load (header word == file's), did the slot count match the scan, where the
16 KB sprite buffer and the room table landed, whether the (forced-hidden) slot lies inside the buffer and, if so,
whether its actual bytes equal the last party member's decompressed sheet at that offset (the model's prediction).
Then, for every character as last member, the (X, Y) the hidden slot would get.
"""
import argparse
import importlib.util
import json
import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("iap", os.path.join(HERE, "InvisActorPredict.py"))
iap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(iap)
spec2 = importlib.util.spec_from_file_location("srd", os.path.join(HERE, "ScanRoomDescriptors.py"))
srd = importlib.util.module_from_spec(spec2)
spec2.loader.exec_module(srd)

START_LAST_MEMBER_ID = 8  # InvisVikiOutsideRoom.State formation ends with the hero


def parse_results(path):
    out = {}
    for line in open(path):
        if not line.startswith("T\t"):
            continue
        parts = line.rstrip("\n").split("\t")
        if parts[2] == "ERR":
            out[int(parts[1])] = {"err": parts[3]}
            continue
        d = {"idx": int(parts[1]), "wm": int(parts[2]), "area": int(parts[3]), "screen": int(parts[4])}
        for kv in parts[5:]:
            k, _, v = kv.partition("=")
            d[k] = v
        raw = d.get("slots", "")
        d["slots"] = []
        for sl in raw.split():
            m = re.match(r"(\d+):([0-9a-f]{2}):(\d+),(\d+):([0-9a-f]+)", sl)
            if m:
                d["slots"].append({"n": int(m.group(1)), "id": int(m.group(2), 16), "x": int(m.group(3)), "y": int(m.group(4)), "bytes": bytes.fromhex(m.group(5))})
        out[d["idx"]] = d
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sweep")
    ap.add_argument("targets")
    ap.add_argument("--csv")
    args = ap.parse_args()

    targets = json.load(open(args.targets))
    res = parse_results(args.sweep)
    chars = iap.load_characters()
    names = iap.names_by_id()
    iso = srd.Iso(srd.ISO)
    file_hdr = {}
    for lba, (path, size) in iso.files.items():
        base = os.path.basename(path)
        if base.upper().startswith("V") and base.upper().endswith(".BIN"):
            file_hdr[base.upper()] = struct.unpack("<I", iso.sector(lba, 1)[:4])[0]

    rows = []
    for i, t in enumerate(targets, 1):
        r = res.get(i)
        row = {"i": i, "wm": t["wm"], "area": t["area"], "screen": t["screen"], "file": t["file"]}
        if r is None or "err" in r:
            row["status"] = "NO RESULT" if r is None else "ERR " + r["err"]
            rows.append(row)
            continue
        loaded = int(r["hdr"], 16) == file_hdr.get(t["file"].upper(), -1)
        ns_ok = int(r["ns"]) == t["ns"]
        table, buf = int(r["table"], 16), int(r["bufLast"], 16)
        row.update(done=r["done"] == "true", overlay_ok=loaded, ns=int(r["ns"]), exp=t["ns"], ns_ok=ns_ok, table=table, buf=buf)
        if not (loaded and ns_ok and r["done"] == "true"):
            row["status"] = "LOAD MISMATCH"
            rows.append(row)
            continue
        if buf == 0:
            row["status"] = "no buffer seen"
            rows.append(row)
            continue
        hs = t["hide_slot"]
        slot = next((s for s in r["slots"] if s["n"] == hs), None)
        off = (table & 0x1FFFFF) + 0x18 * (hs - 1) - (buf & 0x1FFFFF)
        row.update(hide_slot=hs, off=off, hidden=bool(slot and slot["id"] == 0xFF), table_off=(table & 0x1FFFFF) - (buf & 0x1FFFFF))
        row["in_buffer"] = 0 <= off <= 0x4000 - 0x18
        if slot:
            row["x"], row["y"], row["bytes"] = slot["x"], slot["y"], slot["bytes"].hex()
        if row["hidden"] and row["in_buffer"]:
            pred = iap.slot_bytes(chars[START_LAST_MEMBER_ID][1][-1], off)[:8]
            row["pred_hero"] = pred.hex()
            row["model_ok"] = pred == slot["bytes"]
            hit = []
            for cid in sorted(chars):
                b = iap.slot_bytes(chars[cid][1][-1], off)
                if b and (b[0] or b[1]):
                    hit.append((names.get(cid, str(cid)), b[0], b[1]))
            row["nonzero_chars"] = len(hit)
            row["examples"] = hit[:6]
        row["status"] = "ok"
        rows.append(row)

    ok = [r for r in rows if r["status"] == "ok"]
    print(f"{len(rows)} targets: {len(ok)} analysed, {sum(1 for r in rows if r['status'] == 'LOAD MISMATCH')} load mismatches, "
          f"{sum(1 for r in rows if r['status'].startswith('ERR') or r['status'] == 'NO RESULT')} errors/no result, "
          f"{sum(1 for r in rows if r['status'] == 'no buffer seen')} no buffer")
    hid = [r for r in ok if r["hidden"]]
    print(f"forced hidden worked on {len(hid)}/{len(ok)}; table inside the 16 KB buffer for {sum(1 for r in ok if 0 <= r['table_off'] < 0x4000)}/{len(ok)};"
          f" hidden slot inside buffer {sum(1 for r in hid if r['in_buffer'])}/{len(hid)}")
    chk = [r for r in hid if r["in_buffer"]]
    print(f"model check (actual stale bytes == last member's sheet at that offset): {sum(1 for r in chk if r['model_ok'])}/{len(chk)}")
    for r in chk:
        if not r["model_ok"]:
            print("  MODEL MISMATCH", r["wm"], r["area"], r["screen"], "actual", r["bytes"], "pred", r["pred_hero"], "off", hex(r["off"]))
    print("\nwm area scr file      slotN hidden  off     inbuf  X   Y   nonzero chars (example last members -> (X,Y))")
    for r in rows:
        if r["status"] != "ok":
            print(f"{r['wm']:>2} {r['area']:>3} {r['screen']:>3} {r['file']:<10} {r['status']}")
            continue
        ex = "; ".join(f"{n}({x},{y})" for n, x, y in r.get("examples", [])[:3])
        print(f"{r['wm']:>2} {r['area']:>3} {r['screen']:>3} {r['file']:<10} {r['hide_slot']:>3} {str(r['hidden']):<6} {r['off']:>6x} {str(r['in_buffer']):<6} {r.get('x', '-'):>3} {r.get('y', '-'):>3}  {r.get('nonzero_chars', '-')}  {ex}")
    if args.csv:
        import csv
        keys = sorted({k for r in rows for k in r})
        with open(args.csv, "w", newline="") as f:
            w = csv.DictWriter(f, keys)
            w.writeheader()
            for r in rows:
                w.writerow({k: (v if not isinstance(v, list) else json.dumps(v)) for k, v in r.items()})


if __name__ == "__main__":
    main()
