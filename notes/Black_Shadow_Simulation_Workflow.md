# Soul Eater Spell Offline Simulation Workflow

A two-step workflow for getting an exact `rand()`-call total and post-cast RNG state for any
Soul Eater-family spell (Hell, Black Shadow, ...) for a candidate seed, without frame-advancing
through the spell's own (potentially multi-thousand-call) cast in the emulator. Built to answer
a specific question: **can Black Shadow's RNG cost be predicted outside the game?** See the
"Why this exists" section below for the short answer (partially, with one required live step)
and [Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md#hell-and-black-shadow-soul-eater-family)'s "Black Shadow" section for the
full investigation this workflow is the result of.

## Why this exists

Every other spell traced in this project (see
[Spell_RNG_Tracing_Methodology.md](./Spell_RNG_Tracing_Methodology.md)) has a `rand()`-call
total that's a pure function of the starting seed - `lib/Magic.lua`'s simulators take a seed
and return a total, full stop. Black Shadow breaks this: its particle-spawn formula reads a
40-slot "scale" table and per-slot position residue from a shared VFX scratch struct
(`DAT_8017a060`/`Address.SOUL_EATER_CTX`) that is **not** reset before its cast - it's
whatever was last written there by some other, unidentified VFX effect. Investigating that
memory's origin (could it be derived from the same seed, in pure code?) found:

- The shared struct is already populated *before* the battle's first turn is even decided -
  it's not fresh per-cast.
- Something writes through it during other, unrelated battle activity (confirmed live: a
  40-slot before/after diff across Neclord's own turn-1 attack showed roughly half the slots
  changed), but that something isn't Black Shadow's own code, isn't reliably attributable to
  one single other spell, and isn't itself a "vortex-style" mechanism with the discipline
  (fixed tick count, clean phase transitions) the traced spells have - it looks like a
  reused-but-not-specially-managed scratch buffer, not a dedicated system with its own
  traceable mechanism.

Conclusion: fully deriving this data from first principles (i.e. from nothing but a seed and
pure code) is not practical - it would mean chasing down every VFX system in the game that
could plausibly touch this shared buffer, with no guarantee of a clean bottom. But the data
**can** be captured live, cheaply, for any specific battle scenario: everything that produces
it is deterministic given a starting seed, so a short live pass that fast-forwards to the
spell's cast boundary and reads the struct directly gives an exact answer - one real
(comparatively short) emulator pass per candidate seed, instead of one real (comparatively
very long) pass per candidate seed. That's this workflow.

## The two pieces

1. **`scripts/CaptureSoulEaterResidual.lua`** (runs inside BizHawk) - for a list of candidate
   seeds, loads a savestate positioned right before the target spell's cast, injects each
   seed, fast-forwards until that spell's RNG-consuming phase becomes active, and writes out
   a Lua-loadable data file with each seed's captured scale/residual table.
2. **`scripts/CalculateSoulEaterTotals.lua`** (plain `lua5.4`, no BizHawk) - reads that file
   and calls the matching `lib/Magic.lua` simulator for each entry, printing the exact total
   `rand()` calls and resulting RNG state.

Both are spell-agnostic: which spell's mechanism to use (handler address, context field
offsets, which `lib/Magic.lua` function to call) comes from **`lib/SoulEaterCapture.lua`**'s
`RECIPES` table, not hardcoded into either script. Adding a future Soul Eater-family spell
means adding one entry there (see "Adding a new spell" below) - no script changes needed.

## Requirement: the savestate must already be at the cast boundary

This is the one hard requirement, and it's not a tooling limitation - it's fundamental. Cap
capturing the residual only needs a *short* fast-forward (through whatever wind-up ticks
remain before the spell's own RNG-consuming phase), not a long one, but that only works if
the savestate is **already positioned right before the target spell's cast begins** - e.g.
`BlackShadowWind.State`/`BlackShadowBats.State`, both captured with the target handler
already active and its tick counter at its starting value.

Trying to start from an earlier point (battle start, a prior turn) doesn't work automatically:
getting from there to a specific cast requires real button input (menu confirmations, turn
and action selection), and there's no generic way to synthesize that - it was tried and hit a
real wall: fast-forwarding from a pre-turn-1 savestate with all inputs unbound (see
`config-headless.ini` below) got stuck indefinitely at a "Fight / Run / Bribe / Free Will"
prompt, since nothing was pressing a button to advance past it. If you need to start further
back, either play through to the cast boundary yourself and savestate there, or write your own
per-scenario driver script (see e.g. this project's `scripts/NeclordBlackShadowSimulator.lua`
for the shape that takes - it uses `Buttons:press()` to navigate a specific known battle) that
gets you to that point before invoking this workflow.

## Usage

1. **Get a savestate positioned right before the target spell's cast.** Confirm it's
   positioned correctly (optional but recommended): load it, check that
   `Address.BATTLE_STATE_PTR`'s handler field matches the recipe's `handler`, and that the
   recipe's `caseFieldOffset` on `Address.SOUL_EATER_CTX` already reads `caseValue`.

2. **Edit `scripts/CaptureSoulEaterResidual.lua`**: set `SPELL` (a key from
   `lib/SoulEaterCapture.lua`'s `RECIPES`), `BASE_SAVE` (your savestate's path), and `SEEDS`
   (the raw 32-bit seeds to test - not RNGTable indices; resolve an index to a raw seed
   yourself first if you're working from this project's `RNGTable(0x42, N):getRNG(index)`
   convention).

3. **Run it via the spawn wrapper** (never launch BizHawk directly for this - see "Spawning
   BizHawk without interrupting you" below):
   ```
   scripts/spawn-headless-emuhawk.sh scripts/CaptureSoulEaterResidual.lua "" 120
   ```
   The third argument is a timeout in seconds - budget roughly (number of seeds) x (a few
   seconds each); increase it for more seeds. Watch the console output (or the log at
   `/tmp/spawn-headless-emuhawk-last.log`) for a `captured at frame N (tick=M)` line per seed;
   `FAILED (timeout)` means the savestate likely isn't positioned at the cast boundary after
   all (check `MAX_FRAMES` in the capture script and the case-value check from step 1).

4. **Run the offline calculator** (no BizHawk needed for this step):
   ```
   lua5.4 scripts/CalculateSoulEaterTotals.lua
   ```
   This prints each seed's exact total `rand()` call count and the RNG state right after the
   cast completes (useful for chaining - e.g. planning what a seed choice does to whatever
   happens next). Pass a path as the first argument to read a capture file from somewhere
   other than the default output location.

### Example output

```
$ lua5.4 scripts/CalculateSoulEaterTotals.lua
spell: BlackShadow (lib/Magic.lua's simulateBlackShadow)
seed         startSeed        frames   tick   totalCalls finalSeed
0x00000001   0x00000001            0      0         6260 0x0322d04d
0x12345678   0x12345678            0      0         5736 0xe42181b0
0xdeadbeef   0xdeadbeef            0      0         5968 0x1fbfbe9f
```

## Spawning BizHawk without interrupting you

`scripts/spawn-headless-emuhawk.sh` is the only supported way to launch BizHawk for this
workflow (or any other automated Lua capture in this project) - never invoke `EmuHawkMono.sh`
directly for automated work, and never touch your own live/running EmuHawk session. It:

- Loads `config-headless.ini` (a full copy of the normal BizHawk `config.ini` with every
  input binding - hotkeys, controller buttons, autofire, analog, feedback/rumble - cleared,
  and audio disabled) via `--config=`, so a spawned instance can't pick up your real keyboard
  or controller input, and doesn't make noise. Your own `config.ini` is never touched.
- Prevents the spawned window from ever taking focus, via a KWin window rule
  (`scripts/kwin-headless-rule.py`) that forces Focus Stealing Prevention to Extreme for any
  window titled "BizHawk" or "Lua Console", added right before launch and removed right after
  (with `xdotool` window-minimizing kept as a redundant second layer). This is scoped **in
  time**, not by any property of your own usage - the rule doesn't exist except during a
  spawned instance's lifetime, so it never affects how BizHawk behaves when you launch it
  yourself normally. This matters in practice: simply minimizing the window after it appears
  isn't enough - the disruptive part (KWin kicking a fullscreen app out of fullscreen to make
  room for a focus-stealing window) already happens at window-creation time, before any
  after-the-fact fix can react. Preventing the focus request in the first place is what
  actually avoids that.

If you ever need to add a new capture-style script that spawns BizHawk, route it through this
wrapper rather than calling `EmuHawkMono.sh` directly.

## Adding a new spell

Once a new Soul Eater-family spell's mechanism is traced (following
[Spell_RNG_Tracing_Methodology.md](./Spell_RNG_Tracing_Methodology.md)) and confirmed to reuse
`spell_hell_spawn_particle`'s formula, add an entry to `lib/SoulEaterCapture.lua`'s `RECIPES`
table: the spell's `tick_state_machine` handler address, its own case/tick/scaleAccum
bookkeeping field offsets within the shared context struct, where its particle slot array
starts within that struct (`slotBaseOffset`), and the name of the `lib/Magic.lua` function
(`magicFn`) that simulates it. The per-slot layout itself (`slotStride=0x44`,
`slotScaleOffset=0x30`, `slotPosXOffset=0x1c`) has been identical for both spells traced so
far and is very likely universal across the whole family, but is left as explicit recipe
fields rather than hardcoded, in case a future spell turns out to differ.

If the new spell's particle-pool data turns out to be a fixed, spell-wide constant (like
Hell's) rather than genuine per-savestate stale memory (like Black Shadow's), this whole
capture workflow is unnecessary for it - its `lib/Magic.lua` simulator only needs a seed, no
live-captured data. `Hell` is included in `RECIPES` and this workflow works for it (used to
validate the tooling is spell-agnostic), but in practice you'd just call
`Magic.simulateHell(seed)` directly.
