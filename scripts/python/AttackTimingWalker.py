# Static, frame-accurate walker for battle animation scripts: answers "how many frames after an
# attack starts does its damage land?" with no emulator, by simulating the animation-script
# interpreter (main.exe play_attack_animation 0x800e3820 / runner FUN_800e358c) and the sprite
# animation player (FUN_800e2044 start / FUN_800e2a9c per-frame update) over the raw disc files.
#
# Timing model (all read from main.exe decompiles, 2026-09-24):
#   - Script start (play_attack_animation, called from the turn coroutine) runs opcodes in mode 0
#     until one returns 0 ("pending"), then saves it.
#   - Every frame, FUN_800e09bc walks party, enemies, then sub-actors; for each it calls the
#     sprite-anim updater FIRST, then the script runner. The runner calls the pending opcode in
#     mode 1; if that returns -1 it keeps running following opcodes in mode 0 until one pends.
#     After the script, the runner steps an active move timer (+0x10) down by one.
#   - The turn coroutine runs before that pass, so a script started at frame 0 gets its first
#     anim update / mode-1 tick in frame 0 itself.
#   - Damage functions (apply_uncovered_attack_damage etc.) poll the ATTACKER's
#     enemy_data+0x40 & 0x2 from the turn coroutine, so damage (and its calc_damage rand()) is
#     applied the frame AFTER the script sets that bit (opcode 26, mask 0x2, on the attacker).
#   Validated against the documented live Whip Master trace (busy set frame 48, bit 0x2 frame 68,
#   dependent code frame 69): this walker gives 0 / 20 / 21 for the same script.
#
# Usage:
#   python3 scripts/python/AttackTimingWalker.py                      # every Bestiary monster, slot 1
#   python3 scripts/python/AttackTimingWalker.py "Whip Master" 8 -v   # one monster, one slot, trace
#   python3 scripts/python/AttackTimingWalker.py --party [gre [slot]] # party files, data/04_play/*.bin
#   python3 scripts/python/AttackTimingWalker.py --json               # write outputs/AttackTimings.json
import json, os, struct, sys

ROOT = "/mnt/Shared/ISOs/Suikoden/Suikoden Files/"
MAIN_EXE_LOAD = 0x800c0800
BESTIARY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "outputs", "Bestiary.json")
MAX_FRAMES = 1500
SHARED_BATTLE_LOAD = 0x800aa000                         # data/00_init/battle.bin
SHARED_SCRIPT_TABLE = 0x8016c208                        # main.exe PTR_DAT_8016c208


class Mem:
    """Overlay file at its load base, plus main.exe's static image."""

    def __init__(self, overlay_path, overlay_base):
        self.name = os.path.relpath(overlay_path, ROOT + "data/")
        self.regions = []
        with open(overlay_path, "rb") as f:
            self.regions.append((overlay_base, f.read()))
        with open(ROOT + "main.exe", "rb") as f:
            self.regions.append((MAIN_EXE_LOAD, f.read()[0x800:]))
        with open(ROOT + "data/00_init/battle.bin", "rb") as f:
            # battle-common data at 0x800aa000; word 0 = shared effect sprite sheet
            self.regions.append((SHARED_BATTLE_LOAD, f.read()))

    @staticmethod
    def combine(a, b):
        """One address space holding two combatants' files (an enemy overlay at 0x80010000 or
        0x80080000 and a party file at 0 never overlap) plus main.exe."""
        m = Mem.__new__(Mem)
        m.name = b.name                                # handlers belong to the target's file
        m.regions = a.regions + [r for r in b.regions if r not in a.regions]
        return m

    def _loc(self, addr, n):
        for base, data in self.regions:
            if base <= addr and addr + n <= base + len(data):
                return data, addr - base
        return None, None

    def ok(self, addr, n=2):
        return self._loc(addr, n)[0] is not None

    def u8(self, a):
        d, o = self._loc(a, 1)
        return None if d is None else d[o]

    def s16(self, a):
        d, o = self._loc(a, 2)
        return None if d is None else struct.unpack_from("<h", d, o)[0]

    def u32(self, a):
        d, o = self._loc(a, 4)
        return None if d is None else struct.unpack_from("<I", d, o)[0]


class Unresolvable(Exception):
    pass


class Anim:
    """Sprite animation state (EnemyData.pAnimResource +0..+3, +8 bits 0/1)."""

    def __init__(self, mem, sprite_res):
        self.mem, self.res = mem, sprite_res
        self.frames, self.pos, self.dur, self.playing, self.loop = [], 0, 0, False, False

    def start(self, seq):
        if self.res is None:
            raise Unresolvable("sprite resource unknown (anim op 4)")
        tab = self.mem.u32(self.res + 0x14)
        p = self.mem.u32(tab + seq * 4) if tab is not None else None
        if p is None or not self.mem.ok(p, 4):
            raise Unresolvable("sprite sequence %d unreadable" % seq)
        n, hdr = self.mem.u8(p), self.mem.u8(p + 1)
        self.frames = [self.mem.u8(p + 5 + 2 * k) for k in range(max(n, 1))]
        self.pos, self.dur = 0, self.frames[0]
        self.playing, self.loop = bool(hdr & 1), bool(hdr & 2)

    def update(self):                                  # FUN_800e2a9c
        if not self.playing:
            return
        self.dur = (self.dur - 1) & 0xFF
        if self.dur != 0:
            return
        if self.pos + 1 < len(self.frames):
            self.pos += 1
        elif not self.loop:
            self.playing = False
        else:
            self.pos = 0
        self.dur = self.frames[self.pos]


class Actor:
    def __init__(self, name, mem, table, sprite_res):
        self.name, self.mem, self.table = name, mem, table
        self.anim = Anim(mem, sprite_res)
        self.cursor, self.saved = None, 0
        self.delay = self.move = self.phase = 0
        self.fx = self.busy = 0
        self.target = None
        self.vfx = None
        self.counter = 0
        self.dying = False                              # HP < 1, death not started yet
        self.death_script = None
        self.revives = 0                                # Sacrificial Buddhas held (party)
        self.bright = 0


def handler_projectile(sim, a):
    """main.exe 0x800f0b24 (shared table DAT_8016bb70[1]): projectile phase machine."""
    t = a.target
    if a.phase == 0:
        a.phase = 1
    elif a.phase == 1:
        if t is not None and t.fx & 0x2:
            a.phase = 2
    elif a.phase == 2:
        if t is not None and t.fx & 0x10:
            a.phase = 99
        else:
            a.move, a.phase = 30, 3
    elif a.phase == 3:
        if a.move == 0:
            a.phase = 99
    elif a.phase == 99:
        a.vfx = None


def handler_curve(sim, a):
    """Crow (a_data 0x80080438 + step FUN_80080178): 30-step flight curve. Phase 0 sets it up;
    phases 1-2 step it (counter +1 per frame); phase 1 -> 2 once the counter passes 15;
    phase 99 when the curve finishes (30 steps)."""
    if a.phase == 0:
        a.counter = 0
        a.phase = 1
        return
    if a.phase == 99:
        a.vfx = None
        return
    if a.phase == 1 and a.counter > 15:
        a.phase = 2
    if a.phase in (1, 2):
        a.counter += 1
        if a.counter >= 30:
            a.phase = 99


def handler_hop(sim, a):
    """Holly Boy (va4 0x800103f4, vb6 0x800108cc): phases 1/3/5 each start a 30-frame move
    toward the target and advance the phase; phase 6 uninstalls."""
    if a.phase in (1, 3, 5):
        a.move = 30
        a.phase += 1
    elif a.phase == 6:
        a.vfx = None


def handler_trail(sim, a):
    """Giant Snail (va8 0x800112d0): phase 0 -> 1 (setup), phase 1 draws a trail with no
    transition of its own, phase 2 -> 3 (cleanup)."""
    if a.phase in (0, 2):
        a.phase += 1


def handler_vine_setup(sim, a):
    """Ivy / Mad Ivy (0x800805c0): phase 0 sets up and swaps in the vine handler
    (0x80080ea4) with a 10-frame extension counter."""
    if a.phase == 0:
        a.counter = 10
        a.vfx = ("vine",)
        a.phase = 1


def handler_vine(sim, a):
    """Ivy vine (0x80080ea4): phase 1 extends for 10 frames then -> 2; phase 2 retracts with
    no transition of its own; 99 -> 100 -> uninstall."""
    if a.phase == 1:
        if a.counter < 1:
            a.phase = 2
        else:
            a.counter -= 1
    elif a.phase == 99:
        a.phase = 100
    elif a.phase == 100:
        a.vfx = None


def handler_slot_reels(sim, a):
    """Slot man (vb3 0x80011790): an RNG consumer. Phase 0: one rand() picks the outcome
    ((r*100/0x7fff) % 6), -> 1. Phase 1: a 60-frame spin; each frame one reel is rerolled with
    rand() until the value differs from what it shows (>= 1 call per frame), -> 2 at the end.
    Phase 2 -> 3, then a per-outcome effect function (PTR_LAB_80074ee4[outcome]) runs; its
    timing isn't modelled, so the walker stops there."""
    if a.phase == 0:
        a.counter = 60
        sim.log(a, "rand() slot outcome")
        a.phase = 1
    elif a.phase == 1:
        a.counter -= 1
        sim.log(a, "rand() reel reroll (1+ calls, rejection loop)")
        if a.counter <= 0:
            a.phase = 2
    elif a.phase == 2:
        a.phase = 3


def handler_damage(sim, a, what):
    """A handler that applies damage itself (callback +0xc calc_damage or +0x158
    calc_rune_element_attack_damage, then +0x10 apply_hp_damage_display): the damage rand()
    happens on this frame, not the frame after an IMPACT bit."""
    sim.log(a, "HANDLER DAMAGE (%s rand)" % what)


def counted(total, then):
    """Phase-1 handler that runs `total` calls, then moves to phase `then`."""
    def h(sim, a):
        if a.phase == 0:
            a.counter, a.phase = 0, 1
        elif a.phase == 1:
            a.counter += 1
            if a.counter >= total:
                a.phase = then
        elif a.phase == 99:
            if then == 99 and h.cleanup_step:
                a.phase = 100
            else:
                a.vfx = None
        elif a.phase == 100:
            a.vfx = None
    h.cleanup_step = True
    return h


def handler_viperman(sim, a):
    """Viperman "onpu" notes (vd5 0x80013870): phase 0 -> 1; phase 1 runs 192 calls -> 99;
    99 frees and uninstalls."""
    if a.phase == 0:
        a.counter, a.phase = 0, 1
    elif a.phase == 1:
        a.counter += 1
        if a.counter >= 192:
            a.phase = 99
    elif a.phase == 99:
        a.vfx = None


def handler_neclord(sim, a):
    """Neclord (ve1 0x80013224 / ve3 0x80015c68, identical): phase 1 runs a sub-machine:
    setup 1 call, state 0 16 calls, state 1 64 calls (damage on call 64 via +0x158 against
    every living party member), states 2/3 1 call each; then 1 -> 2 -> 99 -> 100 -> gone."""
    if a.phase == 0:
        a.counter, a.phase = 0, 1
    elif a.phase == 1:
        a.counter += 1
        if a.counter == 1 + 16 + 64:
            handler_damage(sim, a, "calc_rune_element_attack_damage x living party")
        if a.counter > 1 + 16 + 64 + 2:
            a.phase = 2
    elif a.phase == 2:
        a.phase = 99
    elif a.phase == 99:
        a.phase = 100
    elif a.phase == 100:
        a.vfx = None


def handler_banshee(sim, a):
    """Banshee (ve2 0x800151a0): 20-call wait, then a sub-machine (setup 1, state 0 128, state 1
    70 with damage on its call 70 via +0x158 per living party member, state 2 1)."""
    if a.phase == 0:
        a.counter, a.phase = 0, 1
    elif a.phase == 1:
        a.counter += 1
        if a.counter >= 20:
            a.phase = 2
    elif a.phase == 2:
        a.counter, a.phase = 0, 3
    elif a.phase == 3:
        a.counter += 1
        if a.counter == 1 + 128 + 70:
            handler_damage(sim, a, "calc_rune_element_attack_damage x living party")
        if a.counter > 1 + 128 + 70 + 1:
            a.phase = 99
    elif a.phase == 99:
        a.phase = 100
    elif a.phase == 100:
        a.vfx = None


def handler_mirage(sim, a):
    """Mirage / Phantom (f_data 0x800825b0, vad 0x80010a8c): 30 calls, teleport -> 2; 30 calls
    -> 99 -> 100 -> gone."""
    if a.phase == 0:
        a.counter, a.phase = 0, 1
    elif a.phase == 1:
        a.counter += 1
        if a.counter >= 30:
            a.counter, a.phase = 30, 2
    elif a.phase == 2:
        a.counter -= 1
        if a.counter < 1:
            a.phase = 99
    elif a.phase == 99:
        a.phase = 100
    elif a.phase == 100:
        a.vfx = None


def handler_crystal_core(sim, a):
    """Crystal Core (vf2 0x80017d88): mailbox to an overlay controller. ASSUMES the
    controller's spin speed starts at its steady 48: spin-up 8 frames, orbs fly 30 frames
    (releases phase 1), damage via +0xc calc_damage on phase 2, then 30 + 30 + 1 + 8 frames
    until the controller reaches step 100. Not live-checked; ±1 frame on controller order."""
    if a.phase == 0:
        a.counter, a.phase = 0, 1
    elif a.phase == 1:
        a.counter += 1
        if a.counter >= 8 + 1 + 30:
            a.phase = 2
    elif a.phase == 2:
        handler_damage(sim, a, "calc_damage")
        a.counter, a.phase = 0, 3
    elif a.phase == 3:
        a.counter += 1
        if a.counter >= 30 + 30 + 1 + 8:
            a.phase = 99
    elif a.phase == 99:
        a.vfx = None


def handler_colossus_projectile(sim, a):
    """Colossus projectile (vad 0x8001297c): the common projectile, except phase 3 also
    decrements the move timer itself (2 per frame, so 15 frames instead of 30)."""
    t = a.target
    if a.phase == 0:
        a.phase = 1
    elif a.phase == 1:
        if t is not None and t.fx & 0x2:
            a.phase = 2
    elif a.phase == 2:
        if t is not None and t.fx & 0x10:
            a.phase = 99
        else:
            a.move, a.phase = 30, 3
    elif a.phase == 3:
        was = a.move
        a.move = max(a.move - 1, 0)
        if was <= 1:
            a.phase = 99
    elif a.phase == 99:
        a.vfx = None


def handler_nightmare(sim, a):
    """Nightmare (vd5 0x80013e5c): picks one of 3 sub-attacks with rand() (rerolled 4 times
    during a 126-frame spin), and each sub-attack waits on an async load (callback +0x9c) of
    unknown length. Not timed; the walker reports it blocked after logging the rolls."""
    if a.phase == 0:
        sim.log(a, "rand() nightmare pick")
        a.counter, a.phase = 0, 1
    elif a.phase == 1:
        a.counter += 1
        if a.counter in (27, 59, 91, 123):
            sim.log(a, "rand() nightmare reroll (1+ calls, rejection loop)")
        if a.counter >= 126:
            a.phase = 2


def handler_death_fade(sim, a):
    """main.exe 0x800f1018 (shared table DAT_8016bb70[3]), installed by death scripts: phase 0
    and 1 set up and advance (+1 each call), phase 2 fades the sprite with no transition of its
    own. Phase 99 (set by the script's closing op 30) clears the actor's active flag (+3) AND
    its busy byte (+5) and uninstalls itself - in the same runner call, so busy drops one frame
    before the script's own op 16 would clear it (live-confirmed on Soldier Ant deaths)."""
    if a.phase in (0, 1):
        a.phase += 1
    elif a.phase == 99:
        if a.busy:
            sim.log(a, "clear busy on %s mask 255" % a.name)
        a.busy = 0
        a.vfx = None
        a.cursor = None                                 # +3 = 0: no longer updated


def handler_revive_setup(sim, a):
    """main.exe 0x800f3170 (shared table [6]), Sacrificial Buddha revive script: phase 0
    allocates the effect (4 sprite clones) with a 60-frame counter (+0x144) and moves to phase
    1; phase 1 swaps in the countdown handler 0x800f1da4."""
    if a.phase == 0:
        a.counter, a.phase = 60, 1
    elif a.phase == 1:
        a.vfx = 0x800f1da4


def handler_revive_countdown(sim, a):
    """main.exe 0x800f1da4: phase 0 falls into phase 1; phase 1 counts the 60 down and at 0
    sets the brightness (+0x160) to 255, swaps in the fade handler 0x800f1fcc, phase 2."""
    if a.phase == 0:
        a.phase = 1
    if a.phase == 1:
        a.counter -= 1
        if a.counter <= 0:
            a.bright, a.vfx, a.phase = 255, 0x800f1fcc, 2


def handler_revive_fade(sim, a):
    """main.exe 0x800f1fcc: phases 0 and 1 fall through to 2; phase 2 lowers the brightness by
    4 per call and sets phase 99 once it drops below 129 (32 calls from 255); phase 99 frees the
    clones and uninstalls."""
    if a.phase == 0:
        a.phase = 1
    if a.phase == 1:
        a.phase = 2
    if a.phase == 2:
        a.bright -= 4
        if a.bright < 0x81:
            a.phase = 99
    elif a.phase == 99:
        a.vfx = None


def handler_revive_heal(sim, a):
    """main.exe 0x800f32d4 (shared table [7]): phase 0 heals HPMax/2 (truncated) through
    apply_hp_damage_display, so it is pending until the next round-driver tick commits it, and
    sets phase 99 in the same call; phase 99 uninstalls."""
    if a.phase == 0:
        sim.log(a, "revive heal HPMax/2 (pending, committed next tick)")
        a.phase = 99
    elif a.phase == 99:
        a.vfx = None


# Native per-frame handlers (EnemyData.pVfxEffectHandler), keyed by address. The runner calls
# the installed handler every frame after the script and move step. Unmodelled handlers do
# nothing here, and the walker reports a script that then waits on them as BLOCKED.
HANDLERS = {
    0x800f0b24: handler_projectile,
    0x800f0dac: handler_projectile,                           # spinning variant (party archers)
    0x800f1018: handler_death_fade,                           # death scripts (enemy slot 7)
    0x800f3170: handler_revive_setup,                         # Sacrificial Buddha revive
    0x800f1da4: handler_revive_countdown,
    0x800f1fcc: handler_revive_fade,
    0x800f32d4: handler_revive_heal,
}
# Overlay-compiled copies of the same projectile phase machine (decompiled 2026-09-24; they
# differ only by an extra sound cue). Keyed by (file, address): overlays reuse addresses.
OVERLAY_HANDLERS = {
    ("01_area.a/va4.bin", 0x80010ca4): handler_projectile,    # Golem
    ("08_area.e/ve2.bin", 0x80014098): handler_projectile,    # Clay Doll
    ("09_area.f/vf2.bin", 0x80014760): handler_projectile,    # Rock Buster
    ("11_area.h/h_data.bin", 0x80082a18): handler_projectile, # Earth Golem
    ("08_area.e/ve2.bin", 0x80015acc): handler_projectile,    # Red Elemental
    ("09_area.f/vf1.bin", 0x800147a8): handler_projectile,    # Black Elemental
    ("14_area.s/vs1.bin", 0x80017538): handler_projectile,    # Shell Venus
    ("01_area.a/a_data.bin", 0x80080438): handler_curve,      # Crow
    ("01_area.a/va4.bin", 0x800103f4): handler_hop,           # Holly Boy
    ("02_area.b/vb6.bin", 0x800108cc): handler_hop,           # Holly Boy
    ("01_area.a/va8.bin", 0x800112d0): handler_trail,         # Giant Snail
    ("07_area.d/d_data.bin", 0x800805c0): handler_vine_setup, # Mad Ivy
    ("07_area.d/k_data.bin", 0x800805c0): handler_vine_setup, # Ivy
    ("02_area.b/vb3.bin", 0x80011790): handler_slot_reels,    # Slot man
    # decoded by a sub-agent pass, 2026-09-24
    ("02_area.b/vb5.bin", 0x80011490): handler_trail,         # Giant Slug
    ("07_area.d/vd5.bin", 0x80013870): handler_viperman,      # Viperman
    ("07_area.d/vd5.bin", 0x80013e5c): handler_nightmare,     # Nightmare (untimed)
    ("08_area.e/ve1.bin", 0x80013224): handler_neclord,       # Neclord
    ("08_area.e/ve3.bin", 0x80015c68): handler_neclord,       # Neclord
    ("08_area.e/ve2.bin", 0x800151a0): handler_banshee,       # Banshee
    ("08_area.e/ve3.bin", 0x80014fb8): counted(60, 99),       # Larvae (60-frame arc, own timer)
    ("09_area.f/f_data.bin", 0x80081f28): counted(80, 99),    # Shadow Man
    ("10_area.g/vg2.bin", 0x800136d0): counted(80, 99),       # Shadow
    ("09_area.f/f_data.bin", 0x800825b0): handler_mirage,     # Mirage
    ("15_area.z/vad.bin", 0x80010a8c): handler_mirage,        # Phantom
    ("09_area.f/vf2.bin", 0x80017d88): handler_crystal_core,  # Crystal Core (assumed speed)
    ("15_area.z/vad.bin", 0x8001297c): handler_colossus_projectile,  # Colossus
}


class Sim:
    def __init__(self, verbose=False):
        self.frame, self.actors, self.events, self.sync = 0, [], [], {}
        self.verbose = verbose
        self.attacker = None

    def log(self, actor, what):
        self.events.append((self.frame, actor.name, what))
        if self.verbose:
            print("  f%-4d %-10s %s" % (self.frame, actor.name, what))

    def who(self, a, flag):
        return a.target if flag == 1 else a

    # --- one opcode; returns True (-1, continue) or False (0, pending) -----------------------
    def op(self, a, mode):
        m, c = a.mem, a.cursor
        o = m.s16(c)
        if o is None:
            raise Unresolvable("script cursor 0x%08x unreadable" % c)
        arg = lambda k: m.s16(c + 2 * k)
        if o in (0, 2):
            self.log(a, "end (op %d)" % o)
            a.saved = 0
            return False
        if o == 1:
            self.log(a, "halt (op 1)")
            return False
        if o == 3:                                     # delay N frames
            if mode == 0:
                a.delay = arg(1)
                return False
            a.delay -= 1
            if a.delay < 1:
                a.cursor += 4
                return True
            return False
        if o == 4:
            a.anim.start(arg(1)); a.cursor += 4
            self.log(a, "anim seq %d (%d frames%s)" % (arg(1), sum(a.anim.frames),
                                                       ", loops" if a.anim.loop else ""))
            return True
        if o == 5:                                     # wait until anim done
            if not a.anim.playing:
                a.cursor += 2
                return True
            return False
        if o == 9 or o == 10:
            if a is self.attacker:
                self.sync[arg(1)] = 1 if o == 9 else 0
            self.log(a, "%s sync signal %d" % ("set" if o == 9 else "clear", arg(1)))
            a.cursor += 4
            return True
        if o == 11 or o == 12:
            want = o == 11
            if bool(self.sync.get(arg(1), 0)) == want:
                a.cursor += 4
                return True
            return False
        if o in (15, 16):
            t = self.who(a, arg(1))
            if t is None:
                a.cursor += 6
                return True
            mask = arg(2) & 0xFF
            t.busy = (t.busy | mask) if o == 15 else (t.busy & ~mask)
            self.log(a, "%s busy on %s mask %d" % ("set" if o == 15 else "clear", t.name, mask))
            a.cursor += 6
            return True
        if o == 44:
            t = self.who(a, arg(1))
            if t is None or (arg(2) & t.busy) == 0:
                a.cursor += 6
                return True
            return False
        if o in (26, 27):
            t = self.who(a, arg(1))
            mask = arg(2) & 0xFFFF
            if t is not None:
                t.fx = (t.fx | mask) if o == 26 else (t.fx & ~mask)
            self.log(a, "%s fx on %s mask 0x%x" % ("set" if o == 26 else "clear",
                                                   t.name if t else "?", mask))
            if o == 26 and t is self.attacker and mask & 2:
                self.log(a, "IMPACT")
            a.cursor += 6
            return True
        if o in (28, 29):
            t = self.who(a, arg(1))
            hit = t is not None and (arg(2) & t.fx) != 0
            if hit == (o == 28):
                a.cursor += 6
                return True
            return False
        if o == 21:                                    # wait until move timer done
            if a.move < 1:
                a.cursor += 2
                return True
            return False
        if o == 22:
            a.move = arg(1); a.cursor += 4; return True
        if o == 23:
            a.move = arg(2); a.cursor += 18; return True
        if o == 33:
            a.move = max(arg(2), 1); a.cursor += 12; return True
        if o == 37:
            a.move = arg(1); a.cursor += 4; return True
        if o == 30:                                    # set phase, costs one frame
            if mode == 0:
                a.phase = arg(1)
                return False
            a.cursor += 4
            return True
        if o == 31:
            if a.phase == arg(1):
                a.cursor += 4
                return True
            return False
        if o == 32:                                    # spawn sub-actor from own table
            sub = Actor(a.name + "/sub", m, a.table, a.anim.res)
            sub.anim.start(arg(1))
            sub.target = a
            p = m.u32(a.table + arg(2) * 4)
            a.cursor += 8
            self.log(a, "spawn sub-actor slot %d" % arg(2))
            self.actors.append(sub)
            self.play(sub, p)
            return True
        if o == 24:                                    # spawn sub-actor (own or shared table)
            flags = arg(1) & 0xFFFF
            if flags & 1:
                sub = Actor(a.name + "/sub", m, a.table, a.anim.res)
            else:                                      # shared effect sheet + script table
                sub = Actor(a.name + "/fx", m, SHARED_SCRIPT_TABLE, m.u32(SHARED_BATTLE_LOAD))
            sub.anim.start(arg(2))
            sub.target = a.target if flags & 4 else a
            p = m.u32(sub.table + arg(3) * 4)
            a.cursor += 14
            self.log(a, "spawn sub-actor slot %d" % arg(3))
            self.actors.append(sub)
            self.play(sub, p)
            return True
        if o == 36:                                    # goto own table[arg]
            a.cursor = m.u32(a.table + arg(1) * 4)
            self.log(a, "goto slot %d" % arg(1))
            return True
        if o == 40:
            self.log(a, "rand() status roll (status %d, chance %d)" % (arg(1), arg(2)))
            a.cursor += 6
            return True
        if o == 42:
            a.cursor += 4 + 2 * arg(1)
            return True
        if o == 35:                                    # install native per-frame handler
            src, idx = arg(1), arg(2)
            if src == 1:
                tab = a.table
            elif src == 2:
                tab = a.target.table if a.target else None
            else:
                tab = 0x8016bb70                       # main.exe shared handler table
            addr = m.u32(tab + idx * 4) if tab else None
            a.vfx = addr
            self.log(a, "native handler 0x%08x" % (addr or 0))
            a.counter = 0
            a.cursor += 6
            return True
        width = {6: 4, 7: 4, 8: 4, 13: 4, 14: 4, 17: 10, 18: 10, 19: 10, 20: 12, 25: 8,
                 34: 4, 38: 2, 39: 2, 41: 8, 43: 8}.get(o)
        if width is None:
            raise Unresolvable("unknown opcode %d at 0x%08x" % (o, c))
        a.cursor += width
        return True

    def play(self, a, script):                         # play_attack_animation
        if script is None or not a.mem.ok(script):
            raise Unresolvable("script pointer unreadable")
        a.cursor = script
        while self.op(a, 0):
            pass
        self.settle(a)

    def settle(self, a):                               # the handler that pended is saved (+0x6)
        o = a.mem.s16(a.cursor)
        a.saved = 0 if o in (0, 2) else o

    def tick(self):                                    # FUN_800e09bc, one actor pass
        # by index, like the game: a sub-actor spawned this frame sits in a later slot and
        # gets its first anim update / script tick in this same pass (live-confirmed on Cleo's projectile, 04_play/cre.bin)
        i = 0
        while i < len(self.actors):
            a = self.actors[i]
            i += 1
            if a.cursor is None:
                continue
            a.anim.update()
            if a.saved not in (0, 1):                  # 0 = ended, 1 = halted forever
                if self.op(a, 1):
                    while self.op(a, 0):
                        pass
                self.settle(a)
            if a.move > 0:
                a.move -= 1
            if a.vfx == ("vine",):
                h = handler_vine
            else:
                h = HANDLERS.get(a.vfx) or OVERLAY_HANDLERS.get((a.mem.name, a.vfx))
            if h:
                h(self, a)
            # FUN_800e09bc, right after this combatant's own update: HP < 1 and not busy ->
            # death routine (party FUN_800e2c90: main.exe 0x8016c068; enemy FUN_800e2dac: its
            # own slot 7). Sub-actors never have death_script set.
            if a.dying and a.busy == 0 and a.death_script is not None:
                a.dying = False
                if a.revives > 0:
                    # FUN_800e2c90, only while battle_state+0x3428 == 4 (the round driver is
                    # running - always true for deaths caused by a round's actions): the first
                    # Sacrificial Buddha (item 83) in the inventory is removed and the revive
                    # script runs instead. +0x45 / ActionTag / statuses are left untouched.
                    a.revives -= 1
                    self.log(a, "Sacrificial Buddha revive (item 83 consumed)")
                    self.play(a, SACRIFICIAL_BUDDHA_SCRIPT)
                else:
                    self.log(a, "death (HP < 1, not busy)")
                    self.play(a, a.death_script)

    def run(self, attacker, script, target):
        self.attacker = attacker
        attacker.target = target
        self.actors = [attacker, target]
        self.frame = 0
        self.play(attacker, script)
        self.blocked = None
        impacts_done = 0
        while self.frame < MAX_FRAMES:
            # turn coroutine, before the actor pass: the damage function sees the IMPACT bit set
            # last frame, rolls calc_damage and marks the attacker's +0x40 |= 0x10
            n = sum(1 for f, _, w in self.events if w == "IMPACT" and f < self.frame)
            if n > impacts_done:
                impacts_done = n
                attacker.fx |= 0x10
                self.log(attacker, "damage applied (calc_damage rand)")
            self.tick()
            live = [x for x in self.actors if x.cursor is not None and x.saved not in (0, 1)]
            if not live:
                break
            quiet = self.frame - (self.events[-1][0] if self.events else 0)
            if quiet > 400:                            # nothing moving: waiting on native code
                x = live[0]
                self.blocked = "%s waits at op %d (native handler %s)" % (
                    x.name, x.saved, "0x%08x" % x.vfx if x.vfx else "none")
                break
            self.frame += 1
        return self.events


# Records whose Bestiary _recordBase is wrong: Dragon's record lives in vc61.bin, which the
# game loads at 0x80080000 alongside vc6.bin (code, 0x80010000). Its "attack" script hands off
# to the move handler documented in Battle_Damage_Formula.md (Lightning / Fire Breath roll).
FILE_OVERRIDES = {
    "06_area.c/vc61.bin": [("06_area.c/vc61.bin", 0x80080000), ("06_area.c/vc6.bin", 0x80010000)],
}


def load_monster(rec):
    override = FILE_OVERRIDES.get(rec["_sourceFile"])
    if override:
        mems = [Mem(ROOT + "data/" + f, b) for f, b in override]
        mem = mems[0]
        for extra in mems[1:]:
            mem = Mem.combine(extra, mem)
        return mem, int(rec["actionScriptTableAddress"], 16), int(rec["spriteResourceTableAddress"], 16)
    path = ROOT + "data/" + rec["_sourceFile"]
    mem = Mem(path, int(rec["_recordBase"], 16))
    table = int(rec["actionScriptTableAddress"], 16)
    sprite = int(rec["spriteResourceTableAddress"], 16)
    return mem, table, sprite


def load_party(code):
    """data/04_play/<code>.bin: per-character battle file, pointers are file-relative (the game
    relocates them at load), so map the file at address 0. Header +0x20 = script table offset,
    +0x24 = sprite resource offset."""
    mem = Mem(ROOT + "data/04_play/%s.bin" % code, 0)
    return mem, mem.u32(0x20), mem.u32(0x24)


CHARMAP = {0x10: " "}
CHARMAP.update({0x11 + i: c for i, c in enumerate("abcdefghijklmnopqrstuvwxyz")})
CHARMAP.update({0x2b + i: c for i, c in enumerate("ABCDEFGHIJKLMNOPQRSTUVWXYZ")})
CHARMAP.update({0x45 + i: c for i, c in enumerate("0123456789")})


def party_identity(code):
    """04_play/<code>.bin header: byte 0 = roster id, bytes 1.. = charmap-encoded name
    (0-terminated). Matches the six roster ids read live in the Zombie Dragon fight."""
    with open(ROOT + "data/04_play/%s.bin" % code, "rb") as f:
        head = f.read(17)
    name = ""
    for b in head[1:]:
        if b == 0:
            break
        name += CHARMAP.get(b, "?")
    return head[0], name


def summarize(events):
    first = lambda pred: next((f for f, _, w in events if pred(w)), None)
    impacts = [f for f, _, w in events if w == "IMPACT"]
    handler_hits = [f for f, _, w in events if w.startswith("HANDLER DAMAGE")]

    def busy(kind, who):
        def pred(w):
            parts = w.split()
            return (len(parts) == 6 and parts[0] == kind and parts[1] == "busy"
                    and parts[3] == who)
        return first(pred)
    return {
        "impact": impacts,
        "damage_roll": sorted([f + 1 for f in impacts] + handler_hits),
        "attacker_busy_clear": busy("clear", "attacker"),
        "attacker_fx4_set": fx_set_frame(events, "attacker", 4),
        "target_busy_set": busy("set", "target"),
        "target_busy_clear": busy("clear", "target"),
        "script_rand": [f for f, _, w in events if w.startswith("rand()")],
        "end": next((f for f, who, w in events
                     if who == "attacker" and (w.startswith("end") or w.startswith("halt"))), None),
    }


def busy_clear_frame(events, who, bit):
    for f, _, w in events:
        parts = w.split()
        if (len(parts) == 6 and parts[0] == "clear" and parts[1] == "busy" and parts[3] == who
                and int(parts[5]) & bit):
            return f
    return None


def fx_set_frame(events, who, bit):
    for f, _, w in events:
        parts = w.split()
        if (len(parts) == 6 and parts[0] == "set" and parts[1] == "fx" and parts[3] == who
                and int(parts[5], 16) & bit):
            return f
    return None


def walk_self(loaded, slot, verbose=False, script_ptr=None):
    """Run one of a combatant's non-attack scripts the way the engine starts it from the turn
    coroutine: play_attack_animation(self, other, table[slot]). Used for the hit reaction
    (slot 2, crit slot 8: started by the damage function on the damage frame) and the
    return-to-position script (slot 4: started by battle_enemy_attack_multitarget_continue the
    frame after the attacker's own script sets +0x40 & 0x4). Frames are relative to that start;
    'target' is the combatant itself, 'attacker' the other side."""
    mem, table, sprite = loaded
    me = Actor("target", mem, table, sprite)
    other = Actor("attacker", mem, None, None)
    sim = Sim(verbose)
    sim.attacker = other                               # nothing here counts as IMPACT
    me.target = other
    sim.actors = [me, other]
    sim.play(me, script_ptr if script_ptr is not None else mem.u32(table + slot * 4))
    sim.blocked = None
    while sim.frame < MAX_FRAMES:
        sim.tick()
        if me.saved in (0, 1) and all(x.saved in (0, 1) for x in sim.actors[2:]):
            break
        quiet = sim.frame - (sim.events[-1][0] if sim.events else 0)
        if quiet > 400:
            sim.blocked = "waits at op %d (native handler %s)" % (
                me.saved, "0x%08x" % me.vfx if me.vfx else "none")
            break
        sim.frame += 1
    ev = sim.events
    return {
        "self_busy1_clear": busy_clear_frame(ev, "target", 1),
        "self_busy8_clear": busy_clear_frame(ev, "target", 8),
        "self_fx4_set": fx_set_frame(ev, "target", 4),
        "script_rand": [f for f, _, w in ev if w.startswith("rand()")],
        "end": next((f for f, who, w in ev if who == "target"
                     and (w.startswith("end") or w.startswith("halt"))), None),
        "blocked": sim.blocked,
    }


def walk_reaction(att, tgt, slot=2, script=None, verbose=False):
    """Hit reaction: the damage function runs the ATTACKER's table[slot] (2 = hit,
    8 = crit; party attackers with Rune_Piece_Type 1/4 use main.exe 0x8016c56c/0x8016c648
    instead, pass those as `script`) on the TARGET, with the target's own sprite sheet and own
    script table (op 32/35/36 lookups). Returns frames, relative to the damage frame, until
    the target clears its own busy bit 8 (i.e. becomes eligible for turn rolls / enemy
    attacks again)."""
    amem, atable, _ = att
    tmem, ttable, tsprite = tgt
    mem = Mem.combine(amem, tmem)
    ptr = script if script is not None else mem.u32(atable + slot * 4)
    return walk_self((mem, ttable, tsprite), None, verbose, script_ptr=ptr)


def walk(rec, slot, verbose=False, loaded=None):
    mem, table, sprite = loaded or load_monster(rec)
    script = mem.u32(table + slot * 4)
    attacker = Actor("attacker", mem, table, sprite)
    target = Actor("target", mem, None, None)          # passive stand-in, no script of its own
    sim = Sim(verbose)
    out = summarize(sim.run(attacker, script, target))
    out["blocked"] = sim.blocked
    return out


# --- full basic-Attack resolution, both sides' real scripts -----------------------------------
# The combatant_rec+0x50 continuation chains (main.exe, decompiled 2026-09-25). Each runs in the
# round driver's step 2 (after the turn logic, before the actor pass), in combatant-index order,
# so it sees flag bits the scripts set during the previous frame's actor pass.
#   hit     apply_uncovered_attack_damage 0x800f5960: attacker fx&2 -> calc_damage, fx|=0x10,
#           target runs the attacker's slot 2 -> recover
#   crit    critical_hit_apply_damage 0x800f5abc: same, damage x3, attacker's slot 8
#   miss    ordinary_miss_continue 0x800f5c1c: attacker fx&1 -> target runs ITS OWN slot 3
#           (dodge) at the attacker -> recover
#   counter counter_attack_reprisal 0x800f5db4: attacker fx&1 -> retaliator runs its own slot 3
#           at the attacker; attacker's +0x50 cleared
#           counter_attack_reprisal_continue 0x800f5f98: retaliator fx&2 -> clear its fx, it runs
#           its own slot 5 (counter strike) at the attacker
#           counter_attack_apply_damage 0x800f6030: retaliator fx&2 -> calc_damage(retaliator,
#           attacker), clear its fx, attacker runs the retaliator's slot 2 -> attacker recovers
#   cover   battle_check_counter_attack 0x800f4d5c at dispatch: ally runs 0x8016c270 at the
#           target, target runs 0x8016c29c at the ally; apply_covered_attack_damage 0x800f5e90:
#           attacker fx&2 -> calc_damage(attacker, ally), fx|=0x10, ally runs the attacker's
#           slot 2, target runs 0x8016c2b4 at the ally -> recover
#   recover battle_enemy_attack_multitarget_continue 0x800f5cd0: attacker fx&4 -> attacker runs
#           its own slot 4 (Double-Beat repeats not modelled)
COVER_ALLY_SCRIPT, COVER_TARGET_SCRIPT, COVER_AFTER_SCRIPT = 0x8016c270, 0x8016c29c, 0x8016c2b4
PARTY_DEATH_SCRIPT = 0x8016c068                         # FUN_800e2c90
SACRIFICIAL_BUDDHA_SCRIPT = 0x8016c400                  # FUN_800e2c90's revive branch
PATHS = ("hit", "crit", "miss", "counter", "cover")
CONT_ADDR = {"hit": 0x800f5960, "crit": 0x800f5abc, "miss": 0x800f5c1c, "reprisal": 0x800f5db4,
             "covered": 0x800f5e90, "recover": 0x800f5cd0, "reprisal_continue": 0x800f5f98,
             "apply_counter": 0x800f6030}


def walk_path(att, tgt, path, ally=None, attacker_first=True, reaction_script=None,
              verbose=False, index_order=None, init_fx=None, lethal=(), party_roles=None,
              buddhas=None):
    """Simulate one basic Attack from dispatch (frame 0) until every actor is idle.
    att / tgt / ally are loaded (mem, table, sprite) tuples; attacker_first = the attacker has
    the lower combatant index (party attacker), which orders the continuation callbacks.
    reaction_script overrides the hit/crit reaction (party Rune Piece 1/4 scripts).
    index_order: the roles sorted by combatant index (default: attacker first for a party
    attacker, else target, ally, attacker). It orders both the +0x50 callbacks and the actor
    pass (FUN_800e09bc walks combatants by index, then sub-actors), which matters when one
    actor's script waits on another's flag bits (a party dodge waits on the enemy attacker's
    0x4: live-confirmed one frame later than attacker-first order).
    init_fx: effect flags each role already holds at dispatch. They persist between actions;
    only the executor (the attacker's own, cleared to 0) and the counter steps clear them, so a
    target that dodged earlier still has its 0x2 (live-confirmed: its next counter's first
    step fires immediately).
    buddhas: {role: count} of Sacrificial Buddhas a party role carries (auto-revive).
    lethal: roles whose HP this attack's damage drops below 1; party_roles: which roles are
    party members (default: the attacker for a party attacker, else target and ally). A dead
    combatant starts its death script the first actor pass it is not busy (after its hit
    reaction), and is busy again until that ends (party 0x8016c068, enemy own slot 7).
    Returns frames relative to dispatch."""
    loaded = {"attacker": att, "target": tgt}
    if path == "cover":
        loaded["ally"] = ally
    mems = {k: v[0] for k, v in loaded.items()}
    actors = {}
    for k, (mem, table, sprite) in loaded.items():
        # one address space per actor, its OWN file first: two party files both map at 0
        # (file-relative pointers), so the actor's own sprite/table lookups must win. No
        # script here runs one party member's file-relative script on another party member.
        m = mem
        for other_k, other in mems.items():
            if other_k != k:
                m = Mem.combine(m, other)
        m.name = mem.name                               # own file's overlay handlers
        actors[k] = Actor(k, m, table, sprite)
    A, T = actors["attacker"], actors["target"]
    L = actors.get("ally")
    for k, fx in (init_fx or {}).items():
        if k in actors and k != "attacker":             # the executor clears the attacker's
            actors[k].fx = fx
    if index_order is None:
        index_order = (["attacker", "target", "ally"] if attacker_first
                       else ["target", "ally", "attacker"])
    index_order = [k for k in index_order if k in actors]
    if party_roles is None:
        party_roles = {"attacker"} if attacker_first else {"target", "ally"}
    for k, x in actors.items():
        x.death_script = (PARTY_DEATH_SCRIPT if k in party_roles
                          else x.mem.u32(x.table + 7 * 4))
        if k in party_roles:
            x.revives = (buddhas or {}).get(k, 0)
    sim = Sim(verbose)
    sim.attacker = A
    sim.actors = [actors[k] for k in index_order]
    slot = lambda actor, n: actor.mem.u32(actor.table + n * 4)
    rolls, notes = [], []

    def play(actor, script, target):
        actor.target = target
        sim.play(actor, script)

    def damage(who, on, mult=1):
        rolls.append({"frame": sim.frame, "by": who.name, "on": on.name, "x": mult})
        if on.name in lethal:                           # committed in step 3, before the pass
            on.dying = True
        sim.log(who, "calc_damage rand() -> %s%s" % (on.name, " x3" if mult == 3 else ""))

    # continuation callbacks: return the next callback for the same actor (or None)
    def recover(me):
        if me.fx & 4:
            play(me, slot(me, 4), me.target)
            return None
        return recover

    def hit(me, crit=False):
        def f(_):
            if not A.fx & 2:
                return f
            damage(A, T, 3 if crit else 1)
            A.fx |= 0x10
            s = reaction_script or slot(A, 8 if crit else 2)
            play(T, s, A)
            return recover
        f.cont = "crit" if crit else "hit"
        return f

    def miss(_):
        if not A.fx & 1:
            return miss
        play(T, slot(T, 3), A)
        return recover

    def reprisal(_):
        if not A.fx & 1:
            return reprisal
        play(T, slot(T, 3), A)
        conts["target"] = reprisal_continue
        return None

    def reprisal_continue(_):
        if not T.fx & 2:
            return reprisal_continue
        T.fx = 0
        play(T, slot(T, 5), A)
        return apply_counter

    def apply_counter(_):
        if not T.fx & 2:
            return apply_counter
        damage(T, A)
        T.fx = 0
        play(A, slot(T, 2), T)
        conts["attacker"] = recover
        return None

    def covered(_):
        if not A.fx & 2:
            return covered
        damage(A, L)
        A.fx |= 0x10
        play(L, slot(A, 2), A)
        play(T, COVER_AFTER_SCRIPT, L)
        return recover

    # frame 0: the executor (turn logic, step 1)
    if path == "cover":
        play(L, COVER_ALLY_SCRIPT, T)
        play(T, COVER_TARGET_SCRIPT, L)
    play(A, slot(A, 1), T)
    first = {"hit": hit(A), "crit": hit(A, True), "miss": miss, "counter": reprisal,
             "cover": covered}[path]
    conts = {"attacker": first, "target": None}
    order = [k for k in index_order if k in conts]
    # continuation function addresses, for comparing against a live +0x50 log
    addr = lambda fn: 0 if fn is None else CONT_ADDR.get(getattr(fn, "cont", fn.__name__), 0)
    first.cont = {"hit": "hit", "crit": "crit"}.get(path, first.__name__)
    transitions = [(0, "attacker", addr(first))]
    seen = dict(conts)

    busy_prev = {k: 0 for k in actors}
    clears = {k: [] for k in actors}
    sets = {k: [] for k in actors}
    sim.blocked = None
    while sim.frame < MAX_FRAMES:
        for k in order:                                 # step 2: +0x50 callbacks, index order
            f = conts[k]
            if f is not None:
                nxt = f(actors[k])
                if conts[k] is f:                       # callback may have re-armed another actor
                    conts[k] = nxt
                elif nxt is not None:
                    conts[k] = nxt
        for k in conts:
            if conts[k] is not seen.get(k):
                transitions.append((sim.frame, k, addr(conts[k])))
                seen[k] = conts[k]
        sim.tick()                                      # actor pass
        for k, x in actors.items():
            if x.busy and not busy_prev[k]:
                sets[k].append(sim.frame)
            if busy_prev[k] and not x.busy:
                clears[k].append(sim.frame)
            busy_prev[k] = x.busy
        live = [x for x in sim.actors if x.cursor is not None and x.saved not in (0, 1)]
        if not live and all(c is None for c in conts.values()):
            break
        quiet = sim.frame - (sim.events[-1][0] if sim.events else 0)
        if quiet > 400:
            waiting = [k for k, c in conts.items() if c is not None]
            x = live[0] if live else None
            sim.blocked = ("%s waits at op %d (native handler %s)" % (
                x.name, x.saved, "0x%08x" % x.vfx if x.vfx else "none") if x
                else "continuation for %s never fires" % ",".join(waiting))
            break
        sim.frame += 1

    out = {"path": path, "damage": rolls, "blocked": sim.blocked,
           "script_rand": [(f, who) for f, who, w in sim.events if w.startswith("rand()")]}
    for k in actors:
        # busyUntil: the frame the actor's busy byte last dropped to 0 (free from the next
        # frame); None if it never set busy, "stuck" if it ends busy
        if actors[k].busy:
            out[k + "_free"] = "stuck"
        else:
            out[k + "_free"] = clears[k][-1] if clears[k] else None
        out[k + "_busy_set"] = sets[k][0] if sets[k] else None
        out[k + "_busy"] = sorted([(f, "set") for f in sets[k]] + [(f, "clear") for f in clears[k]])
    out["attacker_dodge_point"] = fx_set_frame(sim.events, "attacker", 1)
    out["transitions"] = transitions
    return out


def enemy_key(rec):
    return "%s@%s" % (rec["name"], rec["actionScriptTableAddress"])


def add_scripts(e, loader, attack):
    for key, fn in (("attack", attack),
                    ("recover", lambda: walk_self(loader(), 4))):
        try:
            e[key] = fn()
        except (Unresolvable, TypeError) as x:
            e[key] = {"unresolvable": str(x)}


def main():
    with open(BESTIARY) as f:
        recs = json.load(f)["enemies"]
    args = [x for x in sys.argv[1:] if x != "-v"]
    verbose = "-v" in sys.argv
    if args and args[0] == "--json":
        out = {"_meta": {
            "description": "Frames from an attack script's start (frame 0 = the tick the attack "
                           "executor calls play_attack_animation, right after the hit/crit rolls) "
                           "to IMPACT (script sets attacker enemy_data+0x40 & 0x2) and to "
                           "damage_roll (calc_damage rand(), one frame later). Generated by "
                           "scripts/python/AttackTimingWalker.py from the raw disc files; slot 1 = "
                           "basic Attack script. blocked/unresolvable entries need a native "
                           "handler or runtime data the walker doesn't model yet.",
            "slot": 1}, "enemies": [], "party": []}
        for rec in recs:
            e = {"key": enemy_key(rec), "name": rec["name"], "file": rec["_sourceFile"],
                 "actionScriptTableAddress": rec["actionScriptTableAddress"]}
            add_scripts(e, lambda: load_monster(rec), lambda: walk(rec, 1))
            out["enemies"].append(e)
        for code in sorted(f[:-4] for f in os.listdir(ROOT + "data/04_play") if f.endswith(".bin")):
            rid, pname = party_identity(code)
            e = {"key": code, "name": pname, "rosterId": rid, "file": "04_play/%s.bin" % code}
            add_scripts(e, lambda: load_party(code),
                        lambda: walk(None, 1, False, load_party(code)))
            out["party"].append(e)
        enemies = [(enemy_key(r), load_monster(r)) for r in recs]
        party = [(c, load_party(c)) for c in sorted(f[:-4] for f in os.listdir(ROOT + "data/04_play")
                                                     if f.endswith(".bin"))]

        def matrix(attackers, targets, slot, script=None):
            out_m = {}
            for ak, att in attackers:
                row = {}
                for tk, tgt in targets:
                    try:
                        r = walk_reaction(att, tgt, slot, script)
                        row[tk] = r["self_busy8_clear"] if not r["blocked"] else None
                    except (Unresolvable, TypeError):
                        row[tk] = None
                out_m[ak] = row
            return out_m
        out["_meta"]["reaction"] = (
            "reaction.<kind>[attacker][target] = frames after the damage frame until the target "
            "clears its own busy bit 8 (null = unresolved). Target keys: enemy = 'Name@table', "
            "party = file code. party_rune_piece_1/_4 = party attacker with Rune_Piece_Type 1 "
            "(Fire) / 4 (Thunder), which swap in main.exe reaction scripts.")
        out["reaction"] = {
            "party_hit": matrix(party, enemies, 2),
            "party_crit": matrix(party, enemies, 8),
            "party_rune_piece_1": matrix([("any", party[0][1])], enemies, None, 0x8016c56c),
            "party_rune_piece_4": matrix([("any", party[0][1])], enemies, None, 0x8016c648),
            "enemy_hit": matrix(enemies, party, 2),
        }
        path = os.path.join(os.path.dirname(BESTIARY), "AttackTimings.json")
        with open(path, "w") as f:
            json.dump(out, f, separators=(",", ":"))
        ok = lambda l: sum(1 for e in l if e["attack"].get("impact"))
        print("wrote %s: enemies %d/%d, party %d/%d resolved"
              % (path, ok(out["enemies"]), len(out["enemies"]), ok(out["party"]), len(out["party"])))
        return
    if args and args[0] == "--path":
        # --path <hit|crit|miss|counter|cover|all> <attacker> <target> [ally]
        #   combatant = party:<code> | <monster name> | <monster name>@<script table>
        def resolve(spec):
            if spec.startswith("party:"):
                return load_party(spec[6:])
            name, _, table = spec.partition("@")
            hits = [r for r in recs if r["name"] == name
                    and (not table or r["actionScriptTableAddress"] == table)]
            if len(hits) != 1:
                raise SystemExit("%s matches %d records; use Name@table" % (spec, len(hits)))
            return load_monster(hits[0])
        which = PATHS if args[1] == "all" else (args[1],)
        att, tgt = resolve(args[2]), resolve(args[3])
        ally = resolve(args[4]) if len(args) > 4 else None
        first = args[2].startswith("party:")
        for p in which:
            if (p == "cover" and ally is None) or (p == "crit" and not first):
                continue                                # cover needs an ally; enemies never crit
            try:
                print(p, walk_path(att, tgt, p, ally, first, verbose=verbose))
            except (Unresolvable, TypeError) as e:
                print(p, "unresolvable:", e)
        return
    if args and args[0] == "--slot":
        slot = int(args[2]) if len(args) > 2 else 2
        if args[1].startswith("party:"):
            targets = [(args[1][6:], load_party(args[1][6:]))]
        else:
            targets = [(r["name"], load_monster(r)) for r in recs if r["name"] == args[1]]
        for name, loaded in targets:
            try:
                print(name, walk_self(loaded, slot, verbose))
            except Unresolvable as e:
                print(name, "unresolvable:", e)
        return
    if args and args[0] == "--party":
        codes = args[1:2] or sorted(f[:-4] for f in os.listdir(ROOT + "data/04_play")
                                    if f.endswith(".bin"))
        slot = int(args[2]) if len(args) > 2 else 1
        for code in codes:
            try:
                s = walk(None, slot, verbose and len(codes) == 1, load_party(code))
                print("%-4s impact=%-10s dmg=%-10s rand=%s end=%s%s"
                      % (code, s["impact"], s["damage_roll"], s["script_rand"], s["end"],
                         ("  BLOCKED: " + s["blocked"]) if s["blocked"] else ""))
            except (Unresolvable, TypeError) as e:
                print("%-4s unresolvable: %s" % (code, e))
        return
    if args:
        slot = int(args[1]) if len(args) > 1 else 1
        for rec in [r for r in recs if r["name"] == args[0]]:
            print("%s (%s) slot %d" % (rec["name"], rec["_sourceFile"], slot))
            try:
                print("  ", walk(rec, slot, verbose))
            except Unresolvable as e:
                print("   unresolvable:", e)
        return
    for rec in recs:
        try:
            s = walk(rec, 1)
            print("%-20s %-24s impact=%-10s dmg=%-10s rand=%.40s end=%s%s"
                  % (rec["name"], rec["_sourceFile"], s["impact"], s["damage_roll"],
                     s["script_rand"], s["end"],
                     ("  BLOCKED: " + s["blocked"]) if s["blocked"] else ""))
        except Unresolvable as e:
            print("%-20s %-24s unresolvable: %s" % (rec["name"], rec["_sourceFile"], e))


if __name__ == "__main__":
    main()
