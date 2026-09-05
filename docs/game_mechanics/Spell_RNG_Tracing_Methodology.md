# Spell RNG Tracing Methodology

A runbook for reverse-engineering how a given spell/magic cast consumes the
RNG stream (and, as a free byproduct, how long its animation actually
takes). Written after doing this three times (Explosion, Earthquake, Charm
Arrow, Flaming Arrow — see
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md)'s "How spells call
RNG" section for the results), since the process is the same each time and
worth following as a checklist rather than re-deriving from scratch.

**Goal of the exercise**: a validated, pure-code simulator in
`lib/Magic.lua` that reproduces a spell's exact `rand()` call count given a
starting RNG seed — not a live-emulator tool. Live captures are only ever a
means of generating ground truth to validate the simulator against; they
are never the deliverable itself.

Prototyping the mechanism in Python first (in a scratchpad, not committed
to the repo) is a good way to iterate quickly before writing the final Lua
version directly in `lib/Magic.lua` — Python's arbitrary-precision integers
and native floor-shift semantics make it much less error-prone to get the
formula right the first time, and it's much faster to debug there than in
Lua. But nothing under `tools/` is a project deliverable — the repo only
keeps the validated Lua port plus its tests.

## 0. What you need from the user

- A savestate one frame *before* the spell's first `rand()` call (ask them
  to save it right at that point if they haven't already — they've
  generally been able to identify the right moment by watching the RNG
  value stop and then jump).
- Ideally a rough frame-count estimate for how long the whole cast takes,
  to size the capture window. Doesn't need to be precise — pad it.

## 1. Find the active handler

Read `base+0x14` off the battle-state struct (`DAT_8017be3c`) the instant
the savestate loads — this is the code pointer to whatever tick-state-
machine function is about to run. Compare against already-known spell
handler addresses to identify which one you're looking at (or it'll be a
brand new `FUN_xxxxxxxx` needing `create_function` first, per
[[feedback-ghidra-overlay-identification]]-style analysis gaps).

## 2. Capture a live per-frame RNG trace

Spawn a separate EmuHawk instance (never touch the user's live session —
see [[feedback-live-emulator-sessions]]), load the savestate, and step
frame-by-frame for the estimated duration (+ generous padding), logging
the raw RNG value (`0x9010`) every frame to a scratch file. See
[[feedback-emuhawk-cli-lua-scripts]] for the CLI-launch gotchas (absolute
`--lua=` path, no `require`, `print()`/errors are GUI-only so redirect
stdout won't show them).

If the user gives you a first-frame call count (e.g. "the first frame
advances RNG N times"), sanity-check it immediately against the shape
you'd expect from N discrete VFX particles/objects × some small per-object
call count (4 is common) — this is often your first real clue about the
particle count and per-object cost before you've decompiled anything.

## 3. Decompile the handler chain

Every spell follows the same 3-function shape (a heap-allocated,
tick-resumable "coroutine" context, same pattern as `battle_advance_turn`
elsewhere in this codebase):

- **`spell_<name>_cast_entry`** — tiny, just schedules the next phase via a
  shared (non-spell-specific) scheduler. Nothing interesting here.
- **`spell_<name>_vfx_setup`** — one-time setup, often itself a real RNG
  sink (particle scatter, etc.) — usually consumes calls in a single frame,
  not spread across ticks.
- **`spell_<name>_tick_state_machine`** — the actual per-tick driver, a
  `switch` on a phase counter (usually `context+0x2e` or similar). This is
  where the bulk of the analysis happens.

Decompile the tick-state-machine function whole. Identify:

- How many phases (cases) there are.
- **For each phase, the hardcoded immediate constant its own tick counter
  is compared against before advancing** (e.g. Flaming Arrow's
  `if (piVar6[0x2d] < 0x60) goto ...` — that `0x60` is phase 1's fixed
  96-tick duration). This is a completely mechanical thing to read off the
  decompile and needs no live data — see §6 below, it's the whole basis for
  the animation-duration numbers.
- Which phase(s) actually call `rand()`, and exactly how many times per
  tick, per active object.
- Which phase applies the final damage (usually `apply_elemental_multiplier`
  with a specific `(element, base_power)` pair worth cross-checking against
  already-documented spell parameters) — confirm it has **no** RNG in that
  step (every spell traced so far has been this way; call it out
  explicitly rather than assuming).

## 4. Watch for known gotchas while porting the formula to code

These have each cost real debugging time on more than one spell — check
for all of them up front rather than rediscovering them one at a time:

- **C's `/` truncates toward zero for negative operands; Python's `//` and
  Lua's `//` both floor toward -∞.** Any decompiled `(x*a)/b` with a
  possibly-negative `x` needs a `c_div(a, b)` helper
  (`abs(a)//abs(b)` with a sign correction), not a bare `//`.
- **A decompiled `>>` on a signed value is an arithmetic (sign-extending)
  shift. Lua's native `>>` operator is a *logical* (unsigned, zero-fill)
  shift regardless of operand sign** — using it directly on a value that
  can be negative silently produces garbage. Use `math.floor(x / 2^n)`
  instead wherever the source does a signed right-shift. (Python's `>>` on
  ints already does the correct arithmetic/floor shift natively — this is
  a Lua-only gotcha.)
- **A field write that only ORs new bits into part of a word** (e.g.
  `field = field & 0xfff | (new_high_bits << 12)`) **preserves whatever was
  already in the untouched bits.** If that field is memory the game reused
  from some earlier, unrelated purpose (a shared VFX particle pool, etc.),
  those preserved bits are stale garbage specific to *this savestate*, not
  derived from the RNG stream at all — the simulator needs to seed with the
  real residual value, or it'll silently diverge many ticks later, once
  the residue has accumulated through repeated arithmetic on the field.
  Dump the *raw* pre-cast memory (before any tick runs) for every relevant
  object/particle to check for this before assuming a clean-zero start —
  cheap to check, expensive to debug around blindly (this is exactly what
  happened with Flaming Arrow's `trail_x` field).
- **A matching aggregate total does not prove per-tick correctness.**
  Always validate exact per-tick call counts against the live trace, not
  just the grand total — a coincidentally-correct total can be hiding a
  compensating error that only shows up once you check individual ticks or
  once you broaden the seed set (Flaming Arrow's original 95-tick
  assumption matched the captured seed's total by pure chance; the true
  bound was 96 ticks, only caught once 20 more seeds were validated).

## 5. Build and validate the simulator

Prototype in a throwaway Python script (scratchpad only, not committed) if
that's faster for iterating on the mechanism, then write the real,
self-contained version as a new function in `lib/Magic.lua`. Validate in
two passes:

1. **Per-tick, against the original captured seed.** Compare your
   simulator's per-tick `rand()` call counts (and, ideally, full relevant
   per-object state — position/lifetime/whatever drives despawn/branch
   decisions) against the live trace at several checkpoints, not just the
   final total. If anything mismatches, dump *more* live state (per-object
   fields, not just the aggregate RNG value) to localize exactly which
   object/tick first diverges — this is far faster than staring at the
   decompile again.
2. **Broad seed validation.** Inject ~20 varied seeds directly into the
   same savestate (`mainmemory.write_u32_le(0x9010, seed)` right after
   `savestate.load`), run until the RNG value settles (unchanged for N
   consecutive frames — pick N long enough to bridge any real internal
   lull the spell has, or gate it behind a minimum elapsed-frame count, so
   it can't misfire during a lull-before-burst shape), then recover the
   exact real call count via **LCG-step-counting**: forward-simulate the
   LCG from the start seed until it equals the settled final value (the
   LCG is a bijection, so this always terminates and gives an exact count
   without needing per-frame instrumentation). Compare against the
   simulator's prediction for each seed — expect 0 discrepancies. If a
   subset don't settle within your frame cap, that's very likely the next
   combatant's action bleeding into the capture window (contamination, not
   a simulator flaw) — increase the cap or accept the partial validation.

## 6. Read off the animation duration (free byproduct)

Sum the per-phase tick-count immediates you already noted in §3, divide by
60 (NTSC frames/sec) for seconds. No live data needed for this number — it
comes straight out of the decompile. Record it in the doc's per-spell
subsection alongside the mechanism writeup. Note any phase whose exit
condition has an extra internal branch (like Flaming Arrow's phase 2,
which runs a special call at tick 64 but still exits deterministically at
its own fixed tick bound) — the loop-exit comparison is what governs total
duration, an internal branch on the way doesn't change it, but it's worth
flagging if a phase's exit condition is *itself* data/condition-dependent
(not yet seen in practice, but check before assuming).

Running table of what's confirmed so far:

| Spell | Phase tick counts | Total ticks | ≈ seconds @ 60fps |
|---|---|---|---|
| Earthquake | 64 + 64 + 128 + 64 | 320 | ~5.3s |
| Charm Arrow | 64 + 32 + 64 + 64 | 224 | ~3.7s |
| Flaming Arrow | 64 + 96 + 74 + 60 | 294 | ~4.9s |

(Explosion not yet broken into phase tick-bounds — only its RNG mechanism
was traced, not its full duration.)

## 7. Deliverables checklist

Every spell trace should end with all of these, matching the depth already
given to Earthquake/Charm Arrow/Flaming Arrow:

- [ ] Ghidra: `create_function` if needed, `rename_function` for all 3
      handler functions (`spell_<name>_cast_entry` /
      `_vfx_setup` / `_tick_state_machine`, plus any spell-specific helper
      like a particle-spawn function), full `set_plate_comment`s
      documenting the mechanism, `save_program`.
- [ ] `docs/game_mechanics/Battle_Damage_Formula.md`: a new subsection under
      "How spells call RNG" following the existing spells' structure
      (mechanism, validation results, animation duration, any notable
      gotchas), plus a row added to this file's duration table above.
- [ ] Project memory (`project_suikoden_battle_system_re.md`): an entry
      summarizing the mechanism, validation, and any bugs hit + fixed —
      future sessions shouldn't have to re-read the whole doc to know
      what's been done.
- [ ] `simulate<Spell>` added to `lib/Magic.lua` — this is the only
      committed simulator artifact; any Python prototype stays in scratch.
- [ ] `Test<Spell>` class added to `tests/test_Magic.lua` (known-seed test +
      the ~20-seed validated-seeds test), run via `lua5.4 tests/test_Magic.lua`
      to confirm.
