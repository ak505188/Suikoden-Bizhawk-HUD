"""Reader for the frame streams written by scripts/WarChainDump.lua (magic "WAD1")."""
import struct

GLOBALS = ["phase", "state", "next", "timer", "a74d0", "alive0", "alive1", "cap0", "cap1", "kill0", "kill1", "k8", "k9",
           "a7400", "drift", "pcnt", "ecnt", "lossP", "lossE", "fxcnt", "arrcnt", "a76b8", "a74e8", "a74f0", "a7498",
           "a7690", "a7408", "a7694", "a75b0", "a7700", "unit", "cat", "enemyIdx", "turns", "a76a8"]


class Frame:
    __slots__ = ("f", "rng", "g", "s", "fx", "ar", "dr")


def load(path):
    """Returns (seed, (cap0, cap1), [Frame]). `s` = (side 0 bytes, side 1 bytes) of 28 byte sprites, `fx` = fx pool
    (28 bytes each), `ar` = arrow pool (30 x 32 bytes), `dr` = Dragon Knight pool (25 x 28 bytes)."""
    d = open(path, 'rb').read()
    assert d[:4] == b'WAD1'
    seed, cap0, cap1, fxcnt, ng = struct.unpack('<5I', d[4:24])
    sizes = (cap0 * 28, cap1 * 28, fxcnt * 28, 30 * 32, 25 * 28)
    fsz = 8 + 4 * ng + sum(sizes)
    off = 24
    frames = []
    while off + fsz <= len(d):
        fr = Frame()
        fr.f, fr.rng = struct.unpack('<2I', d[off:off + 8])
        o = off + 8
        fr.g = dict(zip(GLOBALS, struct.unpack('<%dI' % ng, d[o:o + 4 * ng])))
        o += 4 * ng
        parts = []
        for n in sizes:
            parts.append(d[o:o + n]); o += n
        fr.s = (parts[0], parts[1]); fr.fx, fr.ar, fr.dr = parts[2], parts[3], parts[4]
        frames.append(fr)
        off += fsz
    return seed, (cap0, cap1), frames
