# Dumps the static item definition table (LAB_80167658) straight out of main.exe - no emulator
# needed, it's never relocated. Layout: docs/game_mechanics/Items.md.
# Usage: python3 scripts/python/DumpItemTable.py   (writes outputs/Items.json)
import json, os, re, struct

MAIN_EXE = "/mnt/Shared/ISOs/Suikoden/Suikoden Files/main.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
ITEM_TABLE = 0x80167658   # u32 pointer per item id; id 0 is unused (holds 8, not a pointer)
ITEM_COUNT = 179          # ids 1..179; the next word starts the field-use handler table
FIELD_USE_TABLE = 0x80167928

EQUIP_TYPES = {0x80: "Head", 0xa0: "Body", 0xc0: "Shield", 0xe0: "Accessory"}
ANTIQUE_TYPES = {0x1000: "Pot", 0x2000: "Ornament", 0x4000: "Painting"}
WEAR_BITS = [(0x01, "E"), (0x02, "C"), (0x04, "H"), (0x08, "L"),
             (0x10, "V"), (0x20, "R"), (0x40, "S"), (0x80, "A")]
WHO_BITS = [(0x01, "M"), (0x02, "F"), (0x04, "K"), (0x08, "N")]
BONUS_STATS = ["PWR", "SKL", "DEF_BASE", "SPD", "MGC", "LUK", "ATK", "DEF"]
TARGETS = {0: "all allies", 1: "all enemies", 2: "one ally", 3: "one ally"}

exe = open(MAIN_EXE, "rb").read()
t_addr = struct.unpack_from("<I", exe, 0x18)[0]


def rd(addr, n):
    off = addr - t_addr + 0x800
    return exe[off:off + n]


def u32(addr):
    return struct.unpack("<I", rd(addr, 4))[0]


charmap = {}
for line in open(os.path.join(ROOT, "lib", "Charmap.lua"), encoding="utf-8"):
    m = re.match(r"\s*\[0x([0-9a-f]+)\]='(.*)',", line)
    if m:
        charmap[int(m.group(1), 16)] = m.group(2).replace("\\'", "'")


def decode(raw):
    out = ""
    for b in raw:
        if b == 0:
            break
        out += charmap.get(b, "<%02x>" % b)
    return out


def bits(value, table):
    return "".join(ch for bit, ch in table if value & bit)


items = []
for item_id in range(1, ITEM_COUNT + 1):
    ptr = u32(ITEM_TABLE + item_id * 4)
    rec = rd(ptr, 0x28)
    flags = struct.unpack_from("<H", rec, 0x1c)[0]
    item = {
        "id": item_id,
        "address": "0x%08x" % ptr,
        "name": decode(rec[:0x18]),
        "price": struct.unpack_from("<I", rec, 0x18)[0],
        "flags": "0x%04x" % flags,
    }
    if flags & 0x80:
        # Equipment: 0x28-byte record, +0x20 is a signed per-stat bonus array.
        item["equipType"] = EQUIP_TYPES[flags & 0xe0]
        item["wear"] = bits(rec[0x1e], WEAR_BITS)
        item["restrict"] = bits(rec[0x1d], WHO_BITS) or "MFKN"
        bonus = struct.unpack_from("<8b", rec, 0x20)
        item["bonuses"] = {BONUS_STATS[i]: v for i, v in enumerate(bonus) if v}
    else:
        # Everything else: 0x24-byte record, +0x20 is the battle effect handler (0 = none).
        handler = struct.unpack_from("<I", rec, 0x20)[0]
        item["battleUse"] = bool(flags & 0x04)
        item["fieldUse"] = bool(flags & 0x08)
        item["fullQuantity"] = rec[0x1e]  # 0 = never consumed; sells for 0 unless slot qty == this
        if flags & 0x0c:
            item["target"] = TARGETS[flags & 3]
            item["fieldUseIndex"] = rec[0x1f]
        if handler:
            item["battleHandler"] = "0x%08x" % handler
        if flags & 0x7000:
            item["antiqueType"] = ANTIQUE_TYPES[flags & 0x7000]
    items.append(item)

field_use = ["0x%08x" % u32(FIELD_USE_TABLE + i * 4) for i in range(14)]
path = os.path.join(ROOT, "outputs", "Items.json")
with open(path, "w") as f:
    json.dump({"items": items, "fieldUseHandlers": field_use}, f, indent=1)
print("wrote %d items to %s" % (len(items), os.path.normpath(path)))
