#!/usr/bin/env python3
"""Reference implementation of the Suikoden war battle engine (the six "regular" scenarios).

Executable documentation: every rule here was read from the war overlays (`data/16_war/war_*.bin`)
and checked against live EmuHawk runs frame by frame, see docs/game_mechanics/War_Battles.md for the
rules and notes/War_Battles.md for the history.

The simulation is exact for the RNG: it consumes `rand()` in the same order as the game, including the
soldier animation (3000-30000 calls per round). One loop iteration in `play()` is one iteration of the
game's per-frame loop. Waits that depend only on UI (text boxes, fades) are modelled with the 13 frame
constant measured from the game (UI_WAIT); the other text waits are not modelled, they never touch the
RNG. Charge, Bow, Magic and all five Others commands are implemented. Not modelled: the scripted
scenarios (sca1, teo1, teo2), an arrow aimed past the end of a sprite array, and reading the recruited
characters from a save (pass the war ids to `start_battle`).

Usage:
    b = start_battle('kuwa', recruited=[...war ids...])      # at the first command menu, seed 0x43
    b.units(0)           # groups offered under Charge
    b.play(0, 0)         # Charge with group 0 -> dict(lossP, lossE, frames, outcome, ...)
    b.use_merchant(35)   # Others
    b.rng                # the game's RNG state after each step
"""
import struct
from WarDataDump import scenario, load as load_overlay, BASE

A = 0x41c64e6d
C = 0x3039
M32 = 0xffffffff

MATRIX = [2, 0, 1, 1, 2, 0, 0, 1, 2]
UI_WAIT = 13          # frames the round state machine waits (state 0x13) after the resolver and after the animation


def s16(v):
    v &= 0xffff
    return v - 0x10000 if v & 0x8000 else v


def cdiv(a, b):
    """C integer division (truncates toward zero)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


# --- sine table: main.exe 0x801765bc is exactly round(4096 * sin(i * pi / 2 / 1024)), i = 0..1024 ------------
def _build_sin():
    import math
    return [round(4096 * math.sin(i * math.pi / 2 / 0x400)) for i in range(0x401)]


_T = _build_sin()


def load_sin_table(path):
    """Optional: load the quarter-wave table from a 0x802 byte dump instead (it is identical)."""
    global _T
    _T = list(struct.unpack('<%dh' % 0x401, open(path, 'rb').read()[:0x802]))


def _sin_1(x):
    x &= 0xfff
    if x <= 0x400:
        return _T[x]
    if x <= 0x800:
        return _T[0x800 - x]
    if x <= 0xc00:
        return -_T[x - 0x800]
    return -_T[0x1000 - x]


def rsin(a):
    return _sin_1(a) if a >= 0 else -_sin_1(-a)


def rcos(a):
    if a < 0:
        a = -a
    u = a & 0xfff
    if u < 0x801:
        return _T[0x400 - u] if u < 0x401 else -_T[u - 0x400]
    if u > 0xc00:
        return _T[u - 0xc00]
    return -_T[0xc00 - u]


def rsin_psn(a):
    """The PSN build's rsin (0x80154c20 in the dump): the same quarter table (1024 entries, index 0..0x3ff) but the
    second and fourth quadrants mirror around 0x7ff / 0xfff instead of 0x800 / 0x1000, so they are one entry off."""
    def sub(x):
        if x < 0x400:
            return _T[x]
        if x < 0x800:
            return _T[0x7ff - x]
        if x < 0xc00:
            return -_T[x - 0x800]
        return -_T[0xfff - x]
    return sub(a & 0xfff) if a >= 0 else -sub((-a) & 0xfff)


def rcos_psn(a):
    """The PSN build's rcos (0x80154d28): cos(a) is read as Q[0x3ff - a] in the first quadrant (the disc build
    reads sin(0x400 - a), one entry higher), and so on for the others."""
    a = abs(a) & 0xfff
    if a < 0x400:
        return _T[0x3ff - a]
    if a < 0x800:
        return -_T[a - 0x400]
    if a < 0xc00:
        return -_T[0xbff - a]
    return _T[a - 0xc00]


def bios_qsort(items, cmp):
    """The PlayStation BIOS qsort (A(0x31), a K&R quicksort with the pivot moved to the right end). The command
    menu sorts its unit list with it, so the order of equal keys is whatever this does. Returns a sorted copy."""
    v = list(items)

    def sw(a, b):
        v[a], v[b] = v[b], v[a]

    def q(lo, hi):
        while lo < hi:
            sw((lo + hi) >> 1, hi)
            i, j = lo - 1, hi
            while True:
                while True:
                    i += 1
                    if cmp(v[i], v[hi]) >= 0 or not i < j:
                        break
                while True:
                    j -= 1
                    if not i < j or not cmp(v[j], v[hi]) > 0:
                        break
                if not i < j:
                    break
                sw(i, j)
            sw(hi, i)
            q(lo, i - 1)
            lo = i + 1

    q(0, len(v) - 1)
    return v


class Sprite:
    """One soldier sprite (28 bytes in the game). Positions are fixed point (pixels * 16)."""
    __slots__ = ("x", "y", "vx", "vy", "tx", "ty", "state", "timer")

    @classmethod
    def from_bytes(cls, raw):
        s = cls()
        w = struct.unpack("<7I", raw)
        s.x = s16(w[0]); s.y = s16(w[1]); s.vx = s16(w[2]); s.vy = s16(w[3])
        s.tx = s16(w[4]); s.ty = s16(w[4] >> 16)
        s.state = w[6] & 0xff; s.timer = s16(w[6] >> 16)
        return s

    def key(self):
        return (self.x, self.y, self.vx, self.vy, self.tx, self.ty, self.state, self.timer)


class Arrow:
    __slots__ = ("state", "timer", "tside", "tidx")

    def __init__(self):
        self.state = 0; self.timer = 0; self.tside = 0xff; self.tidx = 0


# scripted scenarios built on the same engine (static analysis + Teo 2 live): data and resolver switches
SPECIAL = {
    # static analysis only (no savestate): teo1 = player always loses 130 * P; ends when the menu opens on turn 3,
    # sca1 = player loses 8/10 of the soldiers, ends when the menu opens on turn 1. Neither sets the game over flag.
    'teo1': dict(enemy=14000, per_sprite=450, turns=[(0, 0), (1, 1), (2, 2)], turn_limit=3, no_game_over=True,
                 actions=[(0, 0, 30, 'Armored cavalry', 0), (1, 0, 30, 'Armored cavalry', 0), (2, 0, 40, "Teo's Charge", 0)]),
    'sca1': dict(enemy=12000, per_sprite=400, turns=[(0, 0), (0, 3), (0, 3), (0, 3), (4, 4)], turn_limit=1,
                 no_game_over=True,
                 actions=[(0, 2, 10, 'Poisonous Pollen', 0), (1, 0, 10, 'Charge Attack', 0), (2, 1, 10, 'Bow attack', 0),
                          (3, 2, 10, 'Magic Attack', 0), (4, 0, 20, 'Bow attack', 0)]),
    'teo2': dict(enemy=14000, per_sprite=450, turns=[(0, 0), (1, 1), (2, 2)],
                 actions=[(0, 0, 20, 'Armored cavalry', 0), (1, 0, 20, 'Armored cavalry', 0), (2, 0, 30, "Teo's Charge", 0)]),
}


class Tables:
    """Static tables (read from the overlay). The character, unit and banter tables have the same content in every
    overlay, only their address moves, so they are found by content."""
    def __init__(self, name='kuwa'):
        self.name = name
        d = load_overlay(name)
        ref = load_overlay('kuwa')

        def find(a, n):
            i = d.find(ref[a - BASE:a - BASE + n])
            assert i >= 0, (name, hex(a))
            return d[i:i + n]
        t = find(0x80026f18, 648)
        self.ctype = [t[i * 6] for i in range(108)]
        self.cbase = [t[i * 6 + 1] for i in range(108)]
        self.cextra = [t[i * 6 + 2] for i in range(108)]
        self.csoldiers = [int.from_bytes(t[i * 6 + 4:i * 6 + 6], 'little') for i in range(108)]
        g = find(0x800271a0, 108)
        self.groups = [list(g[i * 3:i * 3 + 3]) for i in range(36)]
        sp = find(0x8002bb48, 27)
        self.speaking = [((sp[i >> 2] >> ((3 - (i & 3)) * 2)) & 3) == 1 for i in range(108)]
        if name in SPECIAL:
            sc = SPECIAL[name]
            self.per_sprite, self.enemy_start = sc['per_sprite'], sc['enemy']
            self.actions, self.turns = sc['actions'], sc['turns']
            self.turn_limit = sc.get('turn_limit')
            self.no_game_over = sc.get('no_game_over', False)
        else:
            self.turn_limit = None
            self.no_game_over = False
            self.scen = scenario(name)
            self.per_sprite = self.scen['per_sprite']
            self.enemy_start = self.scen['enemy']
            self.actions = self.scen['actions']         # (index, type, power, name, extra)
            self.turns = self.scen['turns']              # (min, max) pairs
        self.cycle = len(self.turns)


class Battle:
    def __init__(self, tables, recruited, seed=0x43):
        self.t = tables
        self.rng = seed
        self.calls = 0
        self.avail = [0xff if i in set(recruited) else 0xfd for i in range(108)]
        self.p = sum(tables.csoldiers[i] for i in recruited)
        self.e = tables.enemy_start
        self.cap_p = self.p
        self.unit_used = [False] * 36
        self.strat = 0
        self.ninja_thief_used = False
        self.turn = 0
        self.enemy_used = [0] * 8
        self.script_pos = 0
        self.enemy_action = 0
        self.outcome = None
        self.frames = 0
        # animation state
        self.cap = [self.p // tables.per_sprite + 1, self.e // tables.per_sprite + 1]
        self.sprites = [[None] * self.cap[0], [None] * self.cap[1]]
        self.alive = list(self.cap)
        self.kill = [0, 0]
        self.drift = 0
        self.arrows = []
        self.gap = None
        self.libgte = 'psn'              # 'psn' (the PSN build the PSTV runs) or 'disc' (USA v1.1 as in BizHawk)
        self.arrivals = None             # list to fill with the frame counts at which a sprite arrives (for gap searches)
        self.arrow_pool = False        # True while the game has the arrow pool allocated (Bow rounds, countered knights)
        self.fx = [dict(state=0, timer=0, x=0, y=0, vx=0, vy=0, ground=0) for _ in range(30)]
        self.a7498 = 0

    # ------------------------------------------------------------------ RNG
    def rand(self):
        self.rng = (self.rng * A + C) & M32
        self.calls += 1
        return (self.rng >> 16) & 0x7fff

    # ------------------------------------------------------------------ units
    def rsin(self, a):
        return rsin_psn(a) if self.libgte == 'psn' else rsin(a)

    def rcos(self, a):
        return rcos_psn(a) if self.libgte == 'psn' else rcos(a)

    def unit_members(self, g):
        return [m for m in self.t.groups[g] if self.avail[m] == 0xff]

    def unit_power(self, g, raw_only=False):
        mem = self.unit_members(g)
        if not mem:
            return 0
        first = mem[0]
        pw = self.t.cbase[first] + sum(self.t.cextra[m] for m in mem[1:])
        if self.t.ctype[first] == 0 and self.strat > 0:
            pw = pw + pw // 2
        return pw & 0xff

    def unit_type(self, g):
        mem = self.unit_members(g)
        return self.t.ctype[mem[0]] if mem else None

    def units(self, category):
        """Groups offered under a command category (0 Charge, 1 Bow, 2 Magic, 3 Others)."""
        out = []
        for g in range(36):
            if self.unit_used[g]:
                continue
            if g in (0x21, 0x18) and self.ninja_thief_used:
                continue
            if self.unit_type(g) == category:
                out.append(g)
        return out

    def menu(self, category):
        """The unit list as the command menu shows it: `units()` sorted by power, highest first, with equal powers in
        the order the BIOS qsort leaves them (FUN_80014f24 builds the list, the menu sorts it)."""
        key = {g: self.unit_power(g) for g in self.units(category)}
        return bios_qsort(list(key), lambda a, b: -1 if key[a] > key[b] else (1 if key[a] < key[b] else 0))

    def speaking_members(self, g):
        return [m for m in self.unit_members(g) if self.t.speaking[m]]

    # ------------------------------------------------------------------ enemy action pick (phase 1)
    def pick_enemy_action(self):
        lo, hi = self.t.turns[self.script_pos]
        n = hi - lo + 1
        while True:
            r = self.rand()
            k = 0x7fff // n
            idx = r // k + lo
            if self.enemy_used[idx] == 0:
                break
        self.enemy_action = idx
        self.enemy_used[idx] = 1
        self.script_pos += 1
        if self.script_pos > self.t.cycle - 1:
            self.enemy_used = [0] * 8
            self.script_pos = 0

    def enemy(self):
        i, typ, pw, name, extra = self.t.actions[self.enemy_action]
        return typ, pw

    # ------------------------------------------------------------------ sprites (FUN_80018098 and friends)
    def retarget_params(self, side):
        return (self.drift, 0x96) if side == 0 else (-150, self.drift)

    def set_course(self, side, idx, speed):                   # FUN_80018098
        s = self.sprites[side][idx]
        dx = s.tx - (s.x >> 4)
        dy = s.ty - (s.y >> 4)
        if abs(dy) < abs(dx):
            s.vx = s16(speed) if dx > 0 else s16(-speed)
            s.timer = s16(cdiv(s.tx * 16 - s.x, s.vx))
            if s.timer == 0:
                s.state = 0
            else:
                s.vy = s16(cdiv(s.ty * 16 - s.y, s.timer))
        else:
            s.vy = s16(speed) if dy > 0 else s16(-speed)
            s.timer = s16(cdiv(s.ty * 16 - s.y, s.vy))
            if s.timer == 0:
                s.state = 2
            else:
                s.vx = s16(cdiv(s.tx * 16 - s.x, s.timer))

    def start_run(self, side, idx, p3, p4):                    # FUN_800156b0
        s = self.sprites[side][idx]
        if s.state in (7, 8):
            return
        if self.rand() // 324 < 20:
            ra = self.rand()
            s.tx = s16(self.drift + ra // 799 - 20)
            rb = self.rand()
            s.ty = s16(rb // 537 + 50)
            s.state = 5
            rc = self.rand()
            self.set_course(side, idx, rc // 0x1fff + 0xf)
        else:
            rx = self.rand()
            s.tx = s16(p3 + rx // (0x7fff // (p4 - p3 + 1)))
            ry = self.rand()
            s.ty = s16(ry // 537 + 50)
            s.state = 3
            rc = self.rand()
            self.set_course(side, idx, rc // 0x1fff + 0xd)

    def retarget(self, side, idx):
        p3, p4 = self.retarget_params(side)
        self.start_run(side, idx, p3, p4)

    def all_charge(self):                                      # FUN_80015a34
        for side in (0, 1):
            for i in range(self.cap[side]):
                p3, p4 = self.retarget_params(side)
                self.start_run(side, i, p3, p4)

    def die(self, side, idx):                                  # FUN_80017148 (the visual part is skipped)
        s = self.sprites[side][idx]
        s.state = 8
        s.timer = 0
        s.ty = -128

    def form_up_one(self, side, idx, p3, p4):                  # FUN_800174a0
        s = self.sprites[side][idx]
        if s.state in (7, 8):
            return
        r = self.rand()
        s.tx = s16(p3 + r // (0x7fff // (p4 - p3 + 1)))
        r = self.rand()
        s.ty = s16(r // 537 + 50)
        r = self.rand()
        self.set_course(side, idx, r // 0x1249 + 0xc)
        s.state = 2

    def form_up(self):                                         # FUN_800176a8
        for side, (p3, p4) in enumerate(((50, 135), (-155, -70))):
            for idx in range(self.cap[side]):
                self.form_up_one(side, idx, p3, p4)

    def set_kills(self, newp, newe):                           # FUN_8001839c
        def k(side, new):
            if new & 0xffff == 0:
                return self.alive[side]
            return self.alive[side] - ((new & 0xffff) // self.t.per_sprite + 1)
        self.kill = [k(0, newp), k(1, newe)]

    # fx pool (sparks and flying bits): only matters because a full pool changes how many rand() calls are made ----
    def spawn_spark(self):                                     # FUN_8001f20c
        for f in self.fx:
            if f['state'] == 0:
                f['state'] = 1; f['timer'] = 0xf
                return True
        return False

    def spawn_arc(self, x, y):                                 # FUN_8001f320 (consumes one rand() when a slot is free)
        for f in self.fx:
            if f['state'] == 0:
                f['state'] = 2
                f['vx'] = -30; f['vy'] = 0
                # only bits 4..15 are written: the old fraction nibble of the slot survives
                f['x'] = s16(((x & 0xfff) << 4) | (f['x'] & 0xf)); f['y'] = s16(((y & 0xfff) << 4) | (f['y'] & 0xf))
                f['ground'] = self.rand() // 0x421 + 0x4b
                return True
        return False

    def update_fx(self):                                       # FUN_8001f48c
        for f in self.fx:
            if f['state'] == 1:
                old = f['timer']; f['timer'] = s16(old - 1)
                if old < 0:
                    f['state'] = 0
            elif f['state'] == 2:
                f['x'] = s16(f['x'] + f['vx'])
                f['y'] = s16(f['y'] + f['vy'])
                f['vy'] += 1
                if f['ground'] < (f['y'] >> 4):
                    f['state'] = 0

    # sprite state handlers ------------------------------------------------
    def _move(self, s):
        s.x = s16(s.x + s.vx)
        s.y = s16(s.y + s.vy)

    def h0(self, side, idx):
        s = self.sprites[side][idx]; s.vx = 0; s.vy = 0

    def h2(self, side, idx):
        s = self.sprites[side][idx]
        self._move(s)
        old = s.timer; s.timer = s16(old - 1)
        if old <= 0:
            s.state = 0; s.vx = 0; s.vy = 0

    def h3(self, side, idx):
        s = self.sprites[side][idx]
        self._move(s)
        if (self.rand() >> 4) == 1:
            s.state = 6; s.timer = 0x3d
        else:
            old = s.timer; s.timer = s16(old - 1)
            if old <= 0:
                self.retarget(side, idx)

    def h4(self, side, idx):
        s = self.sprites[side][idx]
        n = min(2, self.alive[side] // 5)
        old = s.timer; s.timer = s16(old - 1)
        if old <= 0:
            if self.kill[side] > 0:
                r = self.rand()
                if r // (0x7fff // (n + 1)) == 0 and (self.alive[0] == 1 or side != 0 or idx != 0):
                    self.die(side, idx)
                    self.spawn_spark()
                    self.rand()                                # sound pick
                    self.kill[side] -= 1
                    self.alive[side] -= 1
                    return
            self.retarget(side, idx)

    def h5(self, side, idx):
        s = self.sprites[side][idx]
        self._move(s)
        old = s.timer; s.timer = s16(old - 1)
        if old <= 0:
            if side == 0 and self.t.name == 'teo2':
                self.rand(); self.rand()                       # Teo 2 only: two sound rolls for the player's sprites
            s.state = 4
            s.timer = s16(self.rand() // 0x421 + 0x3c)
            s.vx = 0; s.vy = 0

    def h6(self, side, idx):
        s = self.sprites[side][idx]
        old = s.timer; s.timer = s16(old - 1)
        if old <= 0:
            self.retarget(side, idx)

    def h8(self, side, idx):
        s = self.sprites[side][idx]
        old = s.timer; s.timer = s16(old + 1)
        if old > 300:
            s.state = 7

    def h9(self, side, idx):                                   # archer
        s = self.sprites[side][idx]
        if s.timer == 0:
            if self.rand() // 324 != 1:
                return
            s.timer = 0x57
            return
        s.timer = s16(s.timer - 1)
        if s.timer == 0x1c:
            if self.rand() // 0x3fff == 1:
                tside = 1 - side
                if self.alive[tside] == 0:
                    self.ground_shot()
                else:
                    cap = self.cap[tside]
                    while True:
                        t = self.rand() // (0x7fff // cap)
                        st = self.sprites[tside][t].state if t < cap else 0
                        if st not in (7, 8):
                            break
                    self.fire(tside, t)
            else:
                self.ground_shot()

    def ground_shot(self):
        self.rand(); self.rand()
        self.fire(0xff, 0)

    def fire(self, tside, tidx):
        for a in self.arrows:
            if a.state == 0:
                a.state = 1; a.timer = 100; a.tside = tside; a.tidx = tidx
                return

    def arrow_hit(self, side, idx):                            # FUN_80016af4
        if idx >= self.cap[side]:
            return                                             # the game reads past the array here (not modelled)
        s = self.sprites[side][idx]
        if s.state not in (7, 8) and self.kill[side] > 0 and (self.alive[0] == 1 or side != 0 or idx != 0):
            self.die(side, idx)
            self.kill[side] -= 1
            self.alive[side] -= 1

    def update_arrows(self):                                   # FUN_8001dcf4
        for a in self.arrows:
            if a.state == 1:
                old = a.timer; a.timer = s16(old - 1)
                if old <= 0:
                    if a.tside != 0xff:
                        self.arrow_hit(a.tside, a.tidx)
                    self.spawn_spark()
                    a.state = 0

    HANDLERS = {0: h0, 2: h2, 3: h3, 4: h4, 5: h5, 6: h6, 8: h8, 9: h9}

    def update_sprites(self):                                  # FUN_80018530 (sprite part)
        for side in (0, 1):
            for idx in range(self.cap[side]):
                h = self.HANDLERS.get(self.sprites[side][idx].state)
                if h:
                    h(self, side, idx)
        self.a7400 = 0 if (self.kill[0] == 0 and self.kill[1] == 0) else 1
        self.update_fx()

    def spawn_runner(self, side):                              # FUN_8001613c, once per side per frame in state 5
        n = min(self.alive[side] * 3, 0x3c)
        if self.rand() // (0x7fff // (n + 1)) == 0:
            idx = self.cap[side] - 1
            while idx >= 0:
                s = self.sprites[side][idx]
                if s.state not in (7, 8, 4, 5):
                    ra = self.rand()
                    s.tx = s16(self.drift + ra // 799 - 20)
                    rb = self.rand()
                    s.ty = s16(rb // 537 + 50)
                    s.state = 5
                    rc = self.rand()
                    self.set_course(side, idx, rc // 0x1fff + 0xf)
                    return
                idx -= 1

    # magic ---------------------------------------------------------------
    def cast(self, side):                                      # FUN_80016bec
        sv = 0x5a if side == 0 else -0x5a
        idx = 0
        while idx < self.cap[side]:
            if self.sprites[side][idx].state not in (7, 8):
                break
            idx += 1
        s = self.sprites[side][idx]
        s.tx = sv; s.ty = 0x46
        self.set_course(side, idx, self.rand() // 0x1249 + 0xc)
        s.state = 2
        k = 0
        for i in range(idx + 1, self.cap[side]):
            sp = self.sprites[side][i]
            if sp.state not in (7, 8):
                ang = (0x1000 // (self.alive[side] - 1)) * k
                c, sn = self.rcos(ang), self.rsin(ang)
                sp.tx = s16(sv + s16(((c >> 4) * 0x28 & M32) >> 8))
                sp.ty = s16(s16(((sn >> 4) * 0x14 & M32) >> 8) + 0x46)
                self.set_course(side, i, self.rand() // 0x1249 + 0xc)
                k += 1
                sp.state = 2

    def kill_all_marked(self):                                 # FUN_80016fe4
        for side in (0, 1):
            idx = self.cap[side] - 1
            while idx >= 0 and self.kill[side] != 0:
                if self.sprites[side][idx].state not in (7, 8):
                    self.spawn_spark()
                    self.die(side, idx)
                    self.kill[side] -= 1
                    self.alive[side] -= 1
                idx -= 1

    # ------------------------------------------------------------------ battle start
    def init_sprites(self):
        """FUN_800188e0 + FUN_800176a8: 2 rand() per sprite for the entrance position, 3 for the formation."""
        for side in (0, 1):
            for i in range(self.cap[side]):
                s = Sprite.from_bytes(b'\0' * 28)
                s.state = 0
                r = self.rand()
                x = r // 537 + 0xb4 if side == 0 else -(r // 537) - 0xb4
                s.x = s16(x * 16)
                r = self.rand()
                s.y = s16((r // 0x333 + 0x46) * 16)
                s.timer = -1
                self.sprites[side][i] = s
        self.form_up()
        while any(s.state == 2 for side in (0, 1) for s in self.sprites[side]):
            self.update_sprites()

    # ------------------------------------------------------------------ one command round
    def resolve(self, cat, group):
        """The round resolver (FUN_8001b610). Returns (loss_player, loss_enemy, visual plan)."""
        t = self.t
        raw = self.unit_power(group)
        pPow = raw + self.p // 3000
        etype, eraw = self.enemy()
        ePow = eraw + self.e // 3000
        m = MATRIX[cat * 3 + etype]
        roll = lambda r: r // 537 - 30
        if self.t.name == 'teo1':                              # scripted resolver: the player always loses
            P = raw + self.p // 3000
            lossP = min(130 * P + roll(self.rand()), self.p)
            self.a7498 = 0
            return lossP, 0, ('charge', 100)
        if self.t.name == 'sca1':                              # scripted resolver: 80% of the army, no roll
            self.a7498 = 0
            return min((self.p << 3) // 10, self.p), 0, ('magic', None)
        if self.t.name == 'teo2':                              # scripted resolver 0x8001b70c
            P = raw + self.p // 3000
            if cat == 0:
                r1 = self.rand(); r2 = self.rand()
                lossE = 130 * P + roll(r1); lossP = 40 * P + roll(r2); plan = ('charge', -100)
            else:
                lossE = 0; lossP = 130 * P + roll(self.rand()); plan = ('charge', 100)
            self.a7498 = 0
            lossP = min(lossP, self.p); lossE = min(lossE, self.e)
            if lossE == self.e and lossP == self.p:
                r = self.rand()
                lossP = self.p - r // (0x7fff // (self.p + 1)) - 1
            return lossP, lossE, plan
        lossP = lossE = 0
        plan = None
        self.a7498 = 0
        if m == 1:
            self.a7498 = 1
            if etype == 1:
                lossP = 120 * ePow + roll(self.rand()); plan = ('bow', (1,))
            elif etype == 0:
                r1 = self.rand(); r2 = self.rand()
                lossE = 80 * pPow + roll(r1); lossP = 130 * pPow + roll(r2); plan = ('charge', 100)
            else:
                lossP = 200 * eraw; plan = ('magic', 1)
        elif m == 0:
            if cat == 1:
                lossE = 120 * pPow + roll(self.rand()); plan = ('bow', (0,))
            elif cat == 0:
                r1 = self.rand(); r2 = self.rand()
                lossE = 130 * pPow + roll(r1); lossP = 80 * pPow + roll(r2); plan = ('charge', -100)
            else:
                lossE = 200 * raw; plan = ('magic', 0)
        else:
            if cat == 1:
                r1 = self.rand(); r2 = self.rand()
                lossE = 90 * pPow + roll(r1); lossP = 90 * ePow + roll(r2); plan = ('bow', (0, 1))
            elif cat == 0:
                r1 = self.rand(); r2 = self.rand()
                lossE = 100 * pPow + roll(r1); lossP = 100 * ePow + roll(r2); plan = ('charge', 0)
            else:
                r = self.rand()
                if r // (0x7fff // (raw + eraw + 1)) < raw:
                    lossE = 200 * raw; plan = ('magic', 0)
                else:
                    lossP = 200 * eraw; plan = ('magic', 1)
        # clamp (FUN_8001b4e8)
        lossP = min(lossP, self.p)
        lossE = min(lossE, self.e)
        if lossE == self.e and lossP == self.p:
            r = self.rand()
            lossP = self.p - r // (0x7fff // (self.p + 1)) - 1
        return lossP, lossE, plan

    def play(self, cat, group, on_frame=None):
        """Play one Charge/Bow/Magic round. Returns a dict with the results; advances the RNG exactly."""
        assert cat in (0, 1, 2) and not self.unit_used[group]
        lossP, lossE, plan = self.resolve(cat, group)
        kind, arg = plan
        a74d0 = 0
        timer = 0
        if kind == 'charge':
            self.drift = arg
            self.all_charge(); timer = 0x3c; nxt = 5
        elif kind == 'bow':
            for side in arg:
                for idx in range(self.cap[side]):
                    s = self.sprites[side][idx]
                    if s.state not in (7, 8):
                        s.timer = 0; s.state = 9
            self.arrows = [Arrow() for _ in range(30)]
            self.arrow_pool = True
            nxt = 6; timer = 0xf0; a74d0 = 1
        else:
            if arg is not None:
                self.cast(arg)
            nxt = 7
        self.set_kills(self.p - lossP, self.e - lossE)
        if kind == 'magic' and arg is not None:
            self.rand()                                        # discarded roll
        self.a7400 = 1
        stats = dict(lossP=lossP, lossE=lossE, kind=kind, frames=0)
        # --- frames ---
        stall = False
        mphase = 0; mv = 0
        wait = 0
        state = 'wait'
        self.update_sprites()
        frames = 1
        if on_frame:
            on_frame(self, frames)
        finished_round = False
        while True:
            frames += 1
            if state == 'wait':
                wait += 1
                if wait >= UI_WAIT:
                    state = nxt
            elif state == 5:
                self.spawn_runner(0); self.spawn_runner(1)
                fin = 0 if (self.alive[0] == 0 or self.alive[1] == 0) else self.a7400
                if fin == 0:
                    old = timer; timer = s16(old - 1)
                    if old <= 0:
                        self.form_up(); state = 'wait2'; wait = 0
            elif state == 6:
                fin = 0 if (self.alive[0] == 0 or self.alive[1] == 0) else self.a7400
                finished = False
                if fin == 0:
                    old = timer; timer = s16(old - 1)
                    if old <= 0:
                        if a74d0:
                            for side in (0, 1):
                                for s in self.sprites[side]:
                                    if s.state not in (7, 8):
                                        s.timer = 0; s.state = 0
                            a74d0 = 0
                        timer = 0
                        if all(a.state != 1 for a in self.arrows):
                            self.form_up(); state = 'wait2'; wait = 0; finished = True
                if not finished:
                    self.update_arrows()
            elif state == 7:
                if stall:
                    stall = False
                elif not any(s.state == 2 for s in self.sprites[0]) and not any(s.state == 2 for s in self.sprites[1]):
                    done = False
                    if mphase == 0:
                        mv += 4
                        if mv > 100:
                            mv = 0; mphase = 1
                    elif mphase == 1:
                        mv += 2; stall = True
                        if mv > 0x96:
                            mv = 100; mphase = 2
                    else:
                        mv -= 8
                        if mv < 0:
                            done = True
                    if done:
                        self.kill_all_marked(); state = 'wait2'; wait = 0
            elif state == 'wait2':
                wait += 1
                if wait >= UI_WAIT:
                    finished_round = True
            self.update_sprites()
            if on_frame:
                on_frame(self, frames)
            if finished_round:
                break
        # the sprites keep walking to their formation spots while the results panel is up (no rand() there)
        self.arrow_pool = False
        self.settle()
        self.frames += frames
        stats['frames'] = frames
        # --- results panel (state 8): apply the losses, mark the unit ---
        self.p -= lossP
        self.e -= lossE
        self.unit_used[group] = True
        stats['banter'] = self.banter(group)
        self.end_of_round(stats)
        return stats

    # ------------------------------------------------------------------ after the animation
    def banter(self, group, dragon=False):
        """State 8's banter roll and the two rolls inside the banter (states 9 and 0xd)."""
        if self.a7498 != 1:
            return None
        if self.rand() // 324 < 90 and self.speaking_members(group):
            n = len(self.speaking_members(group))
            r = self.rand()
            k = r // (0x7fff // n) + 1
            self.rand()
            return k
        return 0

    def end_of_round(self, stats):
        if self.e <= 0:
            self.outcome = 0
            # victory screen (FUN_80017770): every player sprite picks a spot in -60..60, then sprite 0 once more
            for idx in range(self.cap[0]):
                self.form_up_one(0, idx, -60, 60)
            self.form_up_one(0, 0, -10, 0)
        elif self.p <= 0:
            self.outcome = 5
        else:
            if self.strat > 0:
                self.strat -= 1
            self.ninja_thief_used = False
            self.pick_enemy_action()
            if not any(self.units(c) for c in (0, 1, 2)):
                self.outcome = 8
            if self.t.turn_limit is not None and self.turn + 1 == self.t.turn_limit:
                self.outcome = 8                               # the command menu ends the battle (sca1: 1, teo1: 3)
        self.turn += 1
        stats['outcome'] = self.outcome

    # ------------------------------------------------------------------ Others
    def use_strategist(self, group=32):
        self.strat = self.unit_power(group)
        self.unit_used[group] = True

    def use_ninja(self, group=33):
        self.ninja_thief_used = True
        mem = self.unit_members(group)
        self.avail[mem[0]] = 0xfc

    def use_thief(self, group=24):
        r = self.rand()
        q = r // 0x1fff
        self.ninja_thief_used = True
        mem = self.unit_members(group)
        self.avail[mem[0]] = 0xfc
        return 'reveal' if q < 2 else ('fail' if q == 2 else 'steal')

    def use_merchant(self, group=35):
        """Merchants: 1 rand() for the bucket, then (if soldiers change hands) the revival rands."""
        q = self.rand() // 0x1fff
        deficit = self.cap_p - self.p
        gain = 0
        if q != 0 and deficit != 0:
            gain = min(deficit, self.e >> (3 if q == 1 else 2))
        if gain:
            newp, newe = self.p + gain, self.e - gain
            self.set_kills(newp, newe)
            # FUN_80017c88: enemy sprites (from the last one) fly to the player's side
            n = self.kill[1]
            flying = []
            idx = self.cap[1] - 1
            while idx >= 0 and n >= 1:
                if self.sprites[1][idx].state not in (7, 8):
                    flying.append(idx)
                    n -= 1
                idx -= 1
            # FUN_80017e0c: they leave the army, dead player sprites come back (3 rand() each)
            for idx in flying:
                self.sprites[1][idx].state = 7
                self.kill[1] -= 1
                self.alive[1] -= 1
            idx = self.cap[0] - 1
            while idx >= 0:
                if self.kill[0] > -1:
                    break
                s = self.sprites[0][idx]
                if s.state in (7, 8):
                    s.state = 0
                    # the game only rewrites bits 4..15 of x and y: the old fraction nibble survives
                    s.x = s16((0 << 4) | (s.x & 0xf))
                    s.y = s16((0x3c << 4) | (s.y & 0xf))
                    self.form_up_one(0, idx, 50, 135)
                    self.kill[0] += 1
                    self.alive[0] += 1
                idx -= 1
            self.p, self.e = newp, newe
            self.settle()
        self.unit_used[group] = True
        return gain

    def settle(self):
        """The frames of the results panel and the menu: sprites walk to their spots, sparks fade (no rand()).
        `self.gap` = frames until the next command's resolver (None: long enough for everyone to arrive). The game
        starts the next round whenever the player confirms, sprites still walking are re-aimed from where they are."""
        n = 0
        last = None
        while any(s.state == 2 for side in (0, 1) for s in self.sprites[side]) and (self.gap is None or n < self.gap):
            if self.arrivals is not None:
                cnt = sum(s.state == 2 for side in (0, 1) for s in self.sprites[side])
                if cnt != last:
                    self.arrivals.append(n); last = cnt
            self.update_sprites(); n += 1
        if self.arrivals is not None:
            self.arrivals.append(n)
        while any(f['state'] for f in self.fx):
            self.update_fx()

    # ---- Dragon Knights -------------------------------------------------------------------------
    def use_dragon(self, group=34, on_frame=None):
        """The Dragon Knights command: uses up the turn. Returns the enemy loss (0 if countered)."""
        etype, eraw = self.enemy()
        # FUN_800191cc: 25 knights, 5 rand() each
        kn = []
        for i in range(25):
            r1 = self.rand(); r2 = self.rand(); r3 = self.rand(); r4 = self.rand(); r5 = self.rand()
            kn.append(dict(state=0x1e, x0=r1 // 0x194 + 0xa0, y0=r2 // 799 - 0x8c, tx=r3 // 0x194 - 0xf0, ty=r4 // 799 - 0x50,
                           timer=r5 // 0x10e + 0x14, t=0))
        countered = etype == 1
        dmg = 0 if countered else (self.e >> 2)
        if countered:
            for idx in range(self.cap[1]):
                s = self.sprites[1][idx]
                if s.state not in (7, 8):
                    s.timer = 0; s.state = 9
            self.arrows = [Arrow() for _ in range(30)]
            self.arrow_pool = True
            self.set_kills(self.p, self.e)
        else:
            self.set_kills(self.p, self.e - dmg)
        # iteration 0 (the init above): only the soldier sprites update
        self.update_sprites()
        frames = 1
        self.knights = kn
        if on_frame:
            on_frame(self, frames)
        while True:
            frames += 1
            for k in kn:                                       # FUN_800195d0
                if k['state'] == 0x1e:
                    old = k['timer']; k['timer'] = old - 1
                    if old <= 0:
                        k['timer'] = 0; k['state'] = 0x1f
                elif k['state'] == 0x1f:
                    t = k['timer']
                    x = k['x0'] + cdiv((k['tx'] - k['x0']) * t, 0xb4)
                    y = k['y0'] + cdiv((k['ty'] - k['y0']) * t, 0xb4) + (((self.rsin(cdiv(t << 11, 0xb4)) >> 4) * 100) >> 8)
                    if x < 0x50:
                        r = self.rand()
                        if r // 0x421 == 0 and dmg != 0:
                            self.rand()                        # sound pick
                            self.spawn_arc(x, y)               # one rand() if a fx slot is free
                    if x < 0x50:
                        r = self.rand()
                        if r // 0x421 == 0 and dmg == 0:
                            k['state'] = 0x21
                            k['y16'] = s16((y & 0xfff) << 4); k['vy'] = 0
                            self.spawn_spark()
                    old = k['timer']; k['timer'] = old + 1
                    if old > 0xb4:
                        k['state'] = 7
                elif k['state'] == 0x21:                           # shot down: falls with gravity
                    k['y16'] = s16(k['y16'] + k['vy']); k['vy'] += 1
                    if (k['y16'] >> 4) > 100:
                        k['state'] = 7
            if countered:
                self.update_arrows()                           # FUN_8001dcf4
            done = not any(k['state'] in (0x1e, 0x1f, 0x21) for k in kn)
            if done and countered:
                for sp in self.sprites[1]:                     # FUN_8001792c(1)
                    if sp.state not in (7, 8):
                        sp.timer = 0; sp.state = 0
            self.update_sprites()
            if on_frame:
                on_frame(self, frames)
            if done:
                break
        if not countered:
            self.kill_all_marked()
            self.e -= dmg
            self.settle()
        else:
            # case 3: wait for the arrows in flight, then the usual formation (3 rand() per living sprite)
            while any(a.state == 1 for a in self.arrows):
                self.update_arrows(); self.update_sprites()
            self.form_up()
            self.arrow_pool = False
            self.settle()
        self.unit_used[group] = True
        # end of round
        stats = dict(lossP=0, lossE=dmg)
        self.a7498 = 1 if countered else 0
        if countered:
            self.banter(group, dragon=True)
        self.end_of_round(stats)
        return stats


def start_battle(name='kuwa', recruited=(), seed=0x43, libgte='psn'):
    """Builds a battle at the first command menu (after the intro) for a scenario. `libgte` picks the library's
    rsin/rcos: 'psn' (default, the PSN build the PSTV runs) or 'disc' (the USA v1.1 disc as BizHawk runs it, unless
    scripts/WarPsnPatch.lua is applied there). See notes/War_Battles.md."""
    b = Battle(Tables(name), list(recruited), seed)
    b.libgte = libgte
    b.init_sprites()
    b.pick_enemy_action()
    return b
