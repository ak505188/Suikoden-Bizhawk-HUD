# Static bestiary scanner: walks every file under the unpacked disc's data/ tree looking
# for byte-valid MonsterRecord structs (charmap name + sane stat ranges + an AI function
# pointer landing inside that same file's mapped 0x80010000+ range). No emulator needed.
# Usage: python3 ScanMonsterRecords.py ["/path/to/Suikoden Files/data/"]
import os, struct

CHARMAP_FWD = {}
CHARMAP_FWD[0x10] = ' '
for i,c in enumerate('abcdefghijklmnopqrstuvwxyz'):
    CHARMAP_FWD[0x11+i] = c
for i,c in enumerate('ABCDEFGHIJKLMNOPQRSTUVWXYZ'):
    CHARMAP_FWD[0x2b+i] = c
for i,c in enumerate('0123456789'):
    CHARMAP_FWD[0x45+i] = c

def decode_name(b16):
    out = []
    for byte in b16:
        if byte == 0:
            break
        c = CHARMAP_FWD.get(byte)
        if c is None:
            return None
        out.append(c)
    if not out:
        return None
    return ''.join(out)

def scan_file(path, base=0x80010000):
    with open(path, 'rb') as f:
        data = f.read()
    size = len(data)
    results = []
    seen_names_offsets = set()
    for off in range(0, size - 54):
        name = decode_name(data[off:off+16])
        if name is None or len(name) < 3 or len(name) > 15:
            continue
        if not name[0].isupper():
            continue
        # require rest of the 16-byte field to be null-padded after the terminator
        term_idx = off + len(name)
        if data[term_idx] != 0:
            continue
        # parse the rest of the record
        try:
            level, footprint = data[off+16], data[off+17]
            hp, pwr, skl, defe, spd, mgc, luk = struct.unpack_from('<7H', data, off+18)
            p1, p2, pai = struct.unpack_from('<3I', data, off+40)
        except struct.error:
            continue
        if not (1 <= level <= 99):
            continue
        if not (1 <= hp <= 30000):
            continue
        if not (0 <= pwr <= 2000 and 0 <= skl <= 2000 and 0 <= defe <= 2000 and 0 <= spd <= 2000 and 0 <= mgc <= 2000 and 0 <= luk <= 2000):
            continue
        # AI pointer must land within this file's mapped range
        if not (base <= pai < base + size):
            continue
        # attack script table pointers should also look like plausible KSEG0 addrs (or 0)
        if p1 != 0 and not (0x80000000 <= p1 <= 0x80200000):
            continue
        results.append((off, name, level, hp, pwr, skl, defe, spd, mgc, luk, pai))
    return results

if __name__ == "__main__":
    import sys
    root = sys.argv[1] if len(sys.argv) > 1 else "/mnt/Shared/ISOs/Suikoden/Suikoden Files/data/"
    out_lines = []
    for d in sorted(os.listdir(root)):
        full = os.path.join(root, d)
        if not os.path.isdir(full):
            continue
        for fn in sorted(os.listdir(full)):
            p = os.path.join(full, fn)
            if not os.path.isfile(p):
                continue
            # only scan likely overlay/data files (skip huge non-candidate types if needed)
            try:
                recs = scan_file(p)
            except Exception as e:
                out_lines.append(f"ERROR {p}: {e}")
                continue
            if recs:
                out_lines.append(f"=== {d}/{fn} ({os.path.getsize(p)} bytes) ===")
                for off, name, level, hp, pwr, skl, defe, spd, mgc, luk, pai in recs:
                    out_lines.append(f"  off={hex(off)} name={name!r} lvl={level} HP={hp} PWR={pwr} SKL={skl} DEF={defe} SPD={spd} MGC={mgc} LUK={luk} AI={hex(pai)}")
    print('\n'.join(out_lines))
