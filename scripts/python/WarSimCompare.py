#!/usr/bin/env python3
"""Replays an emulator chain dump (scripts/WarChainDump.lua) through scripts/python/WarSim.py and reports, round by
round, whether the simulated RNG, soldier counts and enemy action match the game.

Usage: WarSimCompare.py <WarChain_*.bin> [sin_table.bin]
"""
import struct
import sys
PSN = '--psn' in sys.argv           # recording made with scripts/WarPsnPatch.lua applied
sys.argv = [a for a in sys.argv if a != '--psn']
import WarSim
from WarSim import Battle, Tables, Sprite

from WarDump import load


EXTRA = {'chainS': [54, 29, 62, 21], 'chainM': [31, 101, 102], 'chainD': [10, 35, 34], 'chainD2': [10, 35, 34]}


def main():
    path = sys.argv[1]
    if len(sys.argv) > 2:
        WarSim.load_sin_table(sys.argv[2])
    tag = path.split('WarChain_')[-1].split('.')[0]
    seed, cap, frames = load(path)
    f0 = frames[0]
    g0 = f0.g
    recruited = [0, 1, 2, 3, 4, 5, 7, 8, 9, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 39, 48, 74, 83, 90]
    b = Battle(Tables('kuwa'), recruited, f0.rng)
    b.libgte = 'psn' if PSN else 'disc'
    for i in (EXTRA.get(tag, []) or ([54, 29, 62, 21, 31, 101, 102, 10, 35, 34] if tag.startswith('rnd') else [])):
        b.avail[i] = 0xff
    for side, raw in ((0, f0.s[0]), (1, f0.s[1])):
        for i in range(cap[side]):
            b.sprites[side][i] = Sprite.from_bytes(raw[i * 28:(i + 1) * 28])
    b.enemy_action = g0['enemyIdx']
    b.enemy_used[4] = 1
    b.script_pos = 1
    # events: rounds (phase 3 starts) and Others commands (phase 4 starts); menus: returns to the command menu
    events = []
    menus = []
    prev_menu = False
    prev_phase = None
    last_turn = None
    for fr in frames:
        f, rng, g = fr.f, fr.rng, fr.g
        m = g['phase'] == 2 and g['a76a8'] == 2
        if m and not prev_menu:
            menus.append((f, rng, g))
        prev_menu = m
        if g['phase'] == 3 and g['state'] == 0 and last_turn != g['turns'] and prev_phase != 3:
            events.append(('round', g['cat'], g['unit']))
            last_turn = g['turns']
        if g['phase'] == 4 and prev_phase != 4:
            events.append(('others', g['cat'], g['unit']))
        prev_phase = g['phase']
    ok_all = True
    for n, ev in enumerate(events):
        kind, cat, unit = ev
        if kind == 'round':
            res = b.play(cat, unit)
            what = f"round cat {cat} unit {unit} loss P/E {res['lossP']}/{res['lossE']}"
        else:
            r0 = b.calls
            if unit == 24:
                what = 'thief ' + b.use_thief(unit)
            elif unit == 32:
                b.use_strategist(unit); what = 'strategist'
            elif unit == 33:
                b.use_ninja(unit); what = 'ninja'
            elif unit == 35:
                what = f'merchant gain {b.use_merchant(unit)}'
            elif unit == 34:
                res = b.use_dragon(unit); what = f"dragon loss E {res['lossE']}"
            else:
                what = f'others unit {unit}?'
        nxt = menus[n] if n < len(menus) else None
        msg = f"{n + 1}: {what} -> counts {b.p}/{b.e} enemy {b.enemy_action} rng {b.rng:08x}"
        if nxt:
            good = (b.rng == nxt[1] and b.p == nxt[2]['pcnt'] and b.e == nxt[2]['ecnt'] and b.enemy_action == nxt[2]['enemyIdx'])
            msg += f" | ref rng {nxt[1]:08x} counts {nxt[2]['pcnt']}/{nxt[2]['ecnt']} enemy {nxt[2]['enemyIdx']} -> {'OK' if good else 'MISMATCH'}"
            ok_all &= good
        print(msg)
    print('ALL OK' if ok_all else 'MISMATCHES')


if __name__ == '__main__':
    main()
