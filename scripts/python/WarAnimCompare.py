#!/usr/bin/env python3
"""Frame by frame check of scripts/python/WarSim.py against a recording made by scripts/WarChainDump.lua.

For every round (Charge/Bow/Magic) and every Dragon Knights command in the recording it replays the command
in the simulator and, after every simulated frame, compares with the recorded frame: the RNG, the alive and
kill counters, all soldier sprites (dying sprites only by state and timer), the arrow pool, the fx pool and
(Dragon Knights) the knight pool. It stops at the first difference of a command and prints it.

Usage: WarAnimCompare.py <WarChain_*.bin>
"""
import struct
import sys
PSN = '--psn' in sys.argv           # recording made with scripts/WarPsnPatch.lua applied
sys.argv = [a for a in sys.argv if a != '--psn']
from WarDump import load
from WarSim import Battle, Tables, Sprite, s16
import WarSimCompare

RECRUITED = [0, 1, 2, 3, 4, 5, 7, 8, 9, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 39, 48, 74, 83, 90]


def frame_diff(b, fr, caps):
    if b.rng != fr.rng:
        return f"rng sim {b.rng:08x} ref {fr.rng:08x}"
    g = fr.g
    if b.alive != [g['alive0'], g['alive1']] or b.kill != [s16(g['kill0']) if g['kill0'] < 128 else g['kill0'] - 256,
                                                         s16(g['kill1']) if g['kill1'] < 128 else g['kill1'] - 256]:
        return f"alive/kill sim {b.alive}/{b.kill} ref {g['alive0']},{g['alive1']}/{g['kill0']},{g['kill1']}"
    for side in (0, 1):
        for i in range(caps[side]):
            ref = Sprite.from_bytes(fr.s[side][i * 28:(i + 1) * 28])
            sim = b.sprites[side][i]
            a, c = ref.key(), sim.key()
            if ref.state in (7, 8) or sim.state in (7, 8):
                # dead sprites: only "dead or not" matters (the arc/timer of a dying sprite only drives its looks)
                a, c = (ref.state in (7, 8),), (sim.state in (7, 8),)
            if a != c:
                return f"sprite side {side} idx {i} sim {sim.key()} ref {ref.key()}"
    for k, arr in enumerate(b.arrows if b.arrow_pool else []):
        raw = fr.ar[k * 32:(k + 1) * 32]
        rstate = raw[0x1a]
        if (arr.state == 1) != (rstate == 1):
            return f"arrow {k} state sim {arr.state} ref {rstate}"
        if arr.state == 1:
            rt = struct.unpack('<h', raw[0x18:0x1a])[0]
            if (arr.timer, arr.tside) != (rt, raw[0x1b]) or (arr.tside != 0xff and arr.tidx != raw[0x1c]):
                return f"arrow {k} sim {(arr.timer, arr.tside, arr.tidx)} ref {(rt, raw[0x1b], raw[0x1c])}"
    for k, f in enumerate(b.fx):
        raw = fr.fx[k * 28:(k + 1) * 28]
        if f['state'] != raw[4]:
            return f"fx {k} state sim {f['state']} ref {raw[4]}"
        if f['state'] == 1 and f['timer'] != struct.unpack('<h', raw[6:8])[0]:
            return f"fx {k} timer sim {f['timer']} ref {struct.unpack('<h', raw[6:8])[0]}"
    knights = getattr(b, 'knights', None)
    if knights and fr.g['a7408'] == len(knights):
        for k, kn in enumerate(knights):
            raw = fr.dr[k * 28:(k + 1) * 28]
            rs, rt = raw[0x18], struct.unpack('<h', raw[0x1a:0x1c])[0]
            if kn['state'] != rs or (kn['state'] in (0x1e, 0x1f) and kn['timer'] != rt):
                return f"knight {k} sim {(kn['state'], kn['timer'])} ref {(rs, rt)}"
    return None


def main():
    path = sys.argv[1]
    seed, caps, frames = load(path)
    tag = path.split('WarChain_')[-1].split('.')[0]
    f0 = frames[0]
    b = Battle(Tables('kuwa'), RECRUITED, f0.rng)
    b.libgte = 'psn' if PSN else 'disc'
    for i in (WarSimCompare.EXTRA.get(tag, []) or ([54, 29, 62, 21, 31, 101, 102, 10, 35, 34] if tag.startswith('rnd') else [])):
        b.avail[i] = 0xff
    for side in (0, 1):
        for i in range(caps[side]):
            b.sprites[side][i] = Sprite.from_bytes(f0.s[side][i * 28:(i + 1) * 28])
    b.enemy_action = f0.g['enemyIdx']
    b.enemy_used[4] = 1
    b.script_pos = 1
    # events with the index of the first recorded frame of the command
    events = []
    prev_phase = None
    last_turn = None
    for i, fr in enumerate(frames):
        g = fr.g
        if g['phase'] == 3 and g['state'] == 0 and last_turn != g['turns'] and prev_phase != 3:
            j = i
            while j < len(frames) and not (frames[j].g['state'] == 19 and frames[j - 1].g['state'] == 4):
                j += 1
            events.append(('round', g['cat'], g['unit'], j))
            last_turn = g['turns']
        if g['phase'] == 4 and prev_phase != 4:
            j = i
            while j < len(frames) and frames[j].g['phase'] == 4 and frames[j].g['a7408'] != 25:
                j += 1
            events.append(('others', g['cat'], g['unit'], j if g['unit'] == 34 else None))
        prev_phase = g['phase']
    bad_total = 0
    for n, (kind, cat, unit, j) in enumerate(events):
        state = {'bad': None, 'count': 0}

        def hook(sim, it, j=j):
            if state['bad'] is None and j + it - 1 < len(frames):
                state['count'] += 1
                d = frame_diff(sim, frames[j + it - 1], caps)
                if d:
                    state['bad'] = (it, frames[j + it - 1].f, d)
        if kind == 'round':
            res = b.play(cat, unit, on_frame=hook)
            what = f"round cat {cat} unit {unit}"
        elif unit == 34:
            b.use_dragon(unit, on_frame=hook)
            what = "dragon knights"
        else:
            what = {24: 'thief', 32: 'strategist', 33: 'ninja', 35: 'merchant'}.get(unit, f'others {unit}')
            {24: b.use_thief, 32: b.use_strategist, 33: b.use_ninja, 35: b.use_merchant}[unit](unit) if unit in (24, 32, 33, 35) else None
            print(f"{n + 1}: {what}: not compared frame by frame")
            continue
        if state['bad']:
            bad_total += 1
            print(f"{n + 1}: {what}: MISMATCH at iteration {state['bad'][0]} (recorded frame {state['bad'][1]}): {state['bad'][2]}")
        else:
            print(f"{n + 1}: {what}: {state['count']} frames identical")
    print('ALL FRAMES OK' if not bad_total else f'{bad_total} commands differ')


if __name__ == '__main__':
    main()
