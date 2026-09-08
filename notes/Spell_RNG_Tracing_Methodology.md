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
- **A "schedule == current tick" style condition may not gate on whether
  the object is already active.** If the decompile shows a bare equality
  check with no accompanying "is this thing currently inactive" test,
  don't assume it implicitly can't fire on an active object — a per-object
  countdown that resets and decays (e.g. "fire now, then count down from
  48") can numerically re-cross the ever-increasing tick counter later and
  spuriously re-trigger, producing a real, deterministic-but-chaotic-
  looking cascade once several objects' schedules start colliding (Shining
  Wind's Pool A). If two pools look mechanically identical but only one
  ever seems to re-fire unexpectedly, check whether one of them is checked
  in the *shared epilogue* (after the tick counter has already been
  incremented that same tick) versus inside the phase's own body (before
  the increment) — a one-tick offset between two otherwise-matching checks
  is easy to miss and can be the deciding factor in whether re-triggering
  is even numerically possible.
- **Check the very last tick of a phase for a flag-clearing boundary
  condition.** If a phase's exit code clears "this pool is active" flags
  before falling through to a shared per-tick epilogue, no new activations
  can happen on that specific final tick even though the epilogue still
  runs and processes whatever's already active. This kind of bug only
  manifests when some object happens to be eligible to fire on that exact
  tick — it can pass a full single-seed per-tick validation cleanly and
  only surface once a broader seed set is tested. If a broad validation
  gets most seeds right but a consistent subset are each off by a clean
  multiple of one event's cost, suspect a boundary condition like this
  before suspecting the per-object formulas themselves.
- **Re-verify your own hand-built reference data before trusting it over
  the simulator.** A live-per-tick "real" array assembled by hand (or by an
  earlier, less careful script) from a raw frame/RNG capture can itself
  contain a transcription error - if the simulator and the reference
  disagree, don't assume the simulator is wrong; regenerate the reference
  directly and mechanically from the raw capture (keyed by tick, not by
  eyeballed frame alignment) before spending more effort chasing a
  "simulator bug" that might not exist.
- **A "quiet for N frames" settle-detector can systematically under-run for
  some seeds even after being fixed for others**, if the spell's own
  mechanism can produce a genuinely chaotic, seed-dependent quiet-stretch
  length (e.g. a resonance/collision pattern between two counters). Prefer
  a definitive, content-independent signal when one exists — e.g. polling
  the phase/case counter directly and waiting for the phase that's known
  to have zero RNG calls — over raising an unchanged-frame threshold and
  hoping it's now long enough for every seed.

- **A fixed-looking per-object constant table isn't necessarily
  per-savestate garbage — it can be spell-wide static data.** Flaming
  Arrow's residual low-12-bits genuinely are leftover memory specific to
  one savestate. Don't assume every "weird-looking constant array" is the
  same kind of thing: Hell's 40-slot per-particle "scale" table looked
  like random noise (small integers mixed with `~2^31`-scale values) but
  turned out to be byte-identical between two completely different
  savestates (a scripted fight and a random encounter) — i.e. baked into
  the spell's own data, not derived from prior gameplay. Compare the same
  table across two *different* savestates before concluding it's
  per-savestate residue; if it matches, it's a constant to hardcode once,
  not a per-savestate capture to repeat for every test case.
- **A field that looks like a fixed per-object spawn-time constant can
  get silently overwritten by a global, evolving value on every tick the
  object survives.** If a decompiled per-tick "survivor" update writes to
  the *same* field a spawn function reads from (not just position/life,
  but something the spawn formula itself consumes, like a scale or
  orientation factor), that field's value at spawn time depends on
  whether this is the object's first-ever spawn or a later respawn — and
  if it's a respawn, on whatever tick it last survived, not the original
  constant table. This kind of bug produces a **slow aggregate drift**
  (each per-tick call count is only off by a small amount, and not always
  in the same direction) rather than an obvious single-tick mismatch,
  which makes it easy to mistake for an off-by-a-little formula error
  instead of a stale-field bug (Hell).
- **When a "tick" appears to span more than one real frame and you're
  trying to catch a transient, sample *every* frame, not just frames
  where a tracked counter changes.** Filtering a live dump to "only log
  when the tick counter changes" can hide an activate-then-partially-
  deactivate cycle that happens *within* what looks like one tick-value
  window, making a healthy, continuously-cycling population look like it
  never deactivates at all (Hell's "why do all 40 particles look
  permanently active" false paradox, resolved only once every single
  frame was dumped unconditionally).
- **A dense per-frame trace that derives "how many ticks does this phase
  run" by counting RNG-value transitions can undercount by exactly one
  tick.** If a phase's final tick happens to need zero `rand()` calls for
  the specific seed you captured (nothing eligible to reactivate/spawn
  that tick), it produces no visible RNG change and leaves no trace at
  all — a per-tick array built this way can look perfectly self-
  consistent and still be missing the phase's true last tick. Cross-check
  the total tick count against broad seed validation (exact final-RNG-
  state matching, not just a matching aggregate total) rather than
  trusting a single dense trace's tick count as ground truth (Hell: a
  127-tick model matched one dense trace bit-for-bit but was wrong by
  exactly one tick; 128 ticks was the figure that made every injected
  seed's final state match on both savestates).
- **A shared helper function's "constant" can be a per-object field, not
  a global one — and confirming it's uniform in every context you've
  checked so far doesn't make it a spell-wide constant.** Hell's spawn
  formula reads what looked like a fixed offset (`-178`) that turned out,
  on closer reading of the decompile, to be a per-slot signed-16 field —
  it only *happened* to be the same value in every Hell slot across three
  different savestates. When the exact same spawn function turned out to
  be reused by a second spell (Black Shadow), that per-slot field held a
  *different* uniform value (`-128`) there — still uniform within that
  spell, just not the same constant across spells. Don't assume a value
  that's uniform everywhere you've looked is baked into the function
  itself; check whether it's actually read from the caller's own
  per-object data, since that's what makes it safe (and necessary) for a
  second spell to reuse the same helper with different behavior.
- **The same field that's a fixed, spell-wide constant table for one
  spell can be genuine uninitialized stale memory for another spell
  reusing the identical code path.** Hell's per-slot `scale` field
  (read by its shared spawn helper) is confirmed byte-identical spell-wide
  data across three different savestates. Black Shadow calls the exact
  same spawn helper, on the exact same per-tick cadence, but its `scale`
  field is genuine leftover VFX-pool garbage that differs *per savestate*
  — confirmed by comparing two savestates that differ only in which
  attack a boss used the turn before, which is precisely what produced a
  dramatically different (not just seed-variance-sized) total RNG cost
  between them, and was initially suspected to be a deeper contextual
  factor (camera position) before the stale-memory explanation was found.
  Lesson: never assume a table's spell-wide-constant status transfers to
  a second spell just because it's the same field read by the same
  shared function — re-derive it independently for every new spell/
  savestate pairing, the same way you would for a spell seen for the
  first time.

## 5. Build and validate the simulator

**Not every spell needs this step.** If the decompile shows every phase
transition and call count is a hardcoded immediate (not derived from any
`rand()` return value — i.e. the RNG stream only ever affects *where*
something spawns, never *how many* calls happen or *when* phases change),
the total is a fixed constant regardless of seed. Confirm this against one
live capture, skip building a per-seed simulator entirely, and just record
the constant (Dancing Flames: `simulateDancingFlames()` in `lib/Magic.lua`
always returns `150` — no Python prototype, no broad seed validation, since
there's nothing seed-dependent to check). Otherwise:

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
comes straight out of the decompile. Record it in
[Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md#how-spells-call-rng-the-cast-state-machine)'s
per-spell table (the canonical copy of confirmed durations — don't
duplicate it here). Note any phase whose exit condition has an extra
internal branch (like Flaming Arrow's phase 2, which runs a special call at
tick 64 but still exits deterministically at its own fixed tick bound) —
the loop-exit comparison is what governs total duration, an internal
branch on the way doesn't change it, but flag it if a phase's exit
condition is *itself* data/condition-dependent (not yet seen in practice).

Two real gotchas to watch for while measuring this:

- **Tick count doesn't always map 1:1 to real elapsed frames.** Shining
  Wind runs part of its state machine at roughly half real framerate; Hell
  runs its (seed-independent, fixed-length) RNG phase at a real-frame
  duration that varies by battle context (260 frames in a scripted fight
  vs. 318 in a random encounter, for byte-identical mechanism/constants) —
  a rendering-load effect, not a mechanism difference. Dump phase+tick+
  frame together (not just RNG value) and confirm the ratio before
  assuming it's 1:1.
- **A user's own visual frame-count estimate is a genuine cross-check, not
  just a sanity bound** — Dancing Flames' summed phase ticks landed exactly
  on the user's ~430-frame estimate once its invisible final
  damage-application phase was excluded, confirming both the phase-boundary
  math and that the last phase really has no visible VFX.

## 7. Deliverables checklist

Every spell trace should end with all of these, matching the depth already
given to Earthquake/Charm Arrow/Flaming Arrow:

- [ ] Ghidra: `create_function` if needed, `rename_function` for all 3
      handler functions (`spell_<name>_cast_entry` /
      `_vfx_setup` / `_tick_state_machine`, plus any spell-specific helper
      like a particle-spawn function), full `set_plate_comment`s
      documenting the mechanism, `save_program`.
- [ ] `docs/game_mechanics/Battle_Damage_Formula.md`: a row in that page's
      "How spells call RNG" summary table, plus a short mechanism
      subsection if the spell has anything structurally unique to explain
      (following the existing spells' level of detail — mechanism,
      validation status, notable gotchas — not a full narrative).
- [ ] Project memory (`project_suikoden_battle_system_re.md`): an entry
      summarizing the mechanism, validation, and any bugs hit + fixed —
      future sessions shouldn't have to re-read the whole doc to know
      what's been done.
- [ ] `simulate<Spell>` added to `lib/Magic.lua` — this is the only
      committed simulator artifact; any Python prototype stays in scratch.
- [ ] `Test<Spell>` class added to `tests/test_Magic.lua` (known-seed test +
      the ~20-seed validated-seeds test), run via `lua5.4 tests/test_Magic.lua`
      to confirm.
