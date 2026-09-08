# Enemy AI Tracing Methodology

A runbook for reverse-engineering which move a specific monster's AI picks and why - written
after doing this once (Zombie Dragon - see
[Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md#aienemy-move-selection)'s "AI/enemy move selection" section for
the result), since the process should be the same for every other monster and is worth following
as a checklist rather than re-deriving from scratch. Revisited and expanded after doing a second,
independent boss (Dragon - move selection, Lightning-attack RNG cost, and damage formula) - see
section 6 below for what that second pass confirmed generalizes versus what was Zombie-Dragon-
specific.

**Goal of the exercise**: a validated, exact formula for a monster's move/target selection (RNG
consumption included), confirmed against real captured game behavior - not just a
plausible-looking read of the decompile. The decompile alone is a hypothesis; only a live
validation pass turns it into a confirmed formula.

## 0. What you need from the user

- A savestate positioned at or just before the monster's turn (an early turn is easiest to
  reason about, since the round counter and party formation are simplest then).
- The monster's 1-indexed actor number in that savestate's roster (party count + enemy's
  position among the enemies, same convention `scripts/CaptureEnemyMoveResults.lua` already
  uses) - watch `battle_base+0x8` (`CURRENT_ACTOR`) the way that script does if it isn't already
  known.

## 1. Get an observational baseline first

Before touching Ghidra, capture what the monster actually does across a spread of RNG seeds -
`scripts/CaptureEnemyMoveResults.lua` already does this (edit `BASE_SAVE`/`ENEMY_ACTOR_ID`/
`SEEDS` for the new monster/savestate). This gives you:

- A rough sense of how many distinct moves exist (how many distinct `(ActionType, damage
  pattern, frame count)` shapes show up across seeds).
- Ground truth to validate any formula against later - **do this capture before deriving the
  formula, not after**, so the validation is a genuine held-out check, not something quietly
  fitted to match data you already had in front of you while reading the decompile.

## 2. Find the AI function - it's probably not in `main.exe`

The call site is already known and general: `battle_dispatch_current_actor_action` (`main.exe`,
`0x800f40fc`) reads a per-monster-`Id` function pointer from `attack_data_table[Id]+0x30` and
calls it with the battle-state pointer as its only argument. **This function pointer resolves
into the small overlay at `0x80010000`, not `main.exe`** (confirmed for Zombie Dragon; expect
this to generalize, per this project's own overlay-identification notes - per-monster AI is
exactly the kind of per-instance content that lives in an overlay, unlike the universal battle
engine which is confirmed resident in `main.exe` itself).

`scripts/LocateEnemyAIFunction.lua` automates finding the address and dumping the overlay:
edit `BASE_SAVE`/`ENEMY_ACTOR_ID` (and bump `OVERLAY_SIZE` if its own sanity-check warns the
found address falls outside the dumped window), run it, and it reports:

- The monster's `Id` (indexes `attack_data_table`, a separate id-space from ally roster `Id`s -
  don't assume it matches anything in `lib/Characters/Addresses.lua`).
- The resolved AI function address.
- Confirmation the dump covers that address (or a warning if not - the address could fall in
  the *other* overlay base, `0x80080000`, for a monster with a larger overlay; adjust and re-run).

If `get_function_by_address` on the reported address in `main.exe` already finds something,
skip the overlay dump entirely - not every monster's AI needs to live outside `main.exe`, this
was just true for Zombie Dragon.

## 3. Import the overlay dump into Ghidra and decompile

```
import_file(<dumped .bin path>, language="PSX:LE:32:default", compiler_spec="default", auto_analyze=false)
switch_program(<the imported program's name>)
set_image_base(0x80010000)   -- triggers auto-analysis
create_function(<AI function address>)   -- auto-analysis often won't find it on its own
decompile_function(<AI function address>)
```

Expect to `create_function` at more addresses as you read the decompile - a monster's AI is
rarely one function; Zombie Dragon's was two (an initial target/move selector, plus a second
function it schedules as a follow-up state for one of its move branches). Watch for:

- **Function-pointer calls through a double-indirection** (`(*(code*)**(ptr**)(base+OFFSET))()`)
  - this is a cross-overlay call back into `main.exe` (the overlay can't hardcode `main.exe`
  addresses at compile time). One confirmed slot so far: `*(base+0x1258)` is a `rand()`/RNG2
  wrapper (offset `+0` in whatever table that pointer points to); `+4` from the same table was a
  second, different shared function. Don't assume every such call is RNG - check what its
  return value gets used for (`%100`, `/0x7fff`, or something else entirely).
- **A byte that looks like a flag but is actually a plain index** (formation position, party
  slot number, etc.) - cross-check any "mystery byte" against known per-actor values (dump it
  for all living party members with names/positions you already know) before assuming it's a
  boolean or bitfield.
- **Struct-relative arrays pre-shifted by one stride**, the same convention already documented
  for the combatant/enemy-data arrays (`+0xb94`/`+0xdc` are 0-indexed shortcuts for the same
  1-indexed `+0xb40`/`+0x50` arrays) - if a loop's base pointer differs from the "standard"
  combatant-array base you already know by exactly one stride, it's probably the same array,
  just addressed for a 0-indexed loop variable.
- **The round counter** (`battle_base+0x4` - see
  [Scripted_Battle_Actions.md](../docs/game_mechanics/Scripted_Battle_Actions.md)) showing up as a gate. It's a
  legitimate, general-purpose signal (e.g. "guaranteed special move on round 1") - don't mistake
  it for something monster-specific.

## 4. Validate against the Step 1 capture - don't skip this

Re-implement the formula from scratch in Lua (not copy-pasted from the decompile - re-typing it
from your own understanding is what catches a misread branch polarity). For each already-captured
seed: load the savestate, inject the seed, advance to the exact frame the monster's turn begins
(same detection `CaptureEnemyMoveResults.lua` uses), read the *live* state your formula needs
(round counter, RNG seed, each candidate's eligibility fields) at that exact moment, run your Lua
re-implementation, and compare its prediction against the captured outcome.

**Anything short of matching every single captured seed exactly (move AND target, not just one
or the other) means the formula isn't confirmed yet** - a formula that matches "most" seeds
usually has a real bug in a branch that only some seeds exercise (a rejected-candidate retry
loop, an edge case in the eligibility check, a wrong RNG variant). Zombie Dragon's own
first-pass reasoning had the accept/reject branch polarity backwards - a quick eyeball comparison
against the roughly-60/40 observed split ("doesn't look far off either way") would have missed
it; only the exact per-seed re-check caught it immediately.

## 5. Watch for gotchas already caught once

- **A branch's probability threshold doesn't tell you which outcome is "the roll succeeding" in
  plain language** - a `< N` check reading like "probably-common path" can turn out to gate the
  *rarer* move once you trace what the caller actually does with each return value. Trust the
  caller's own handling (what happens on `-1` vs `0` vs nonzero, what `battle_dispatch_current_
  actor_action` already documents) over an intuitive guess at which branch "sounds like" the
  common move.
- **A rejected candidate in a per-candidate roll loop still consumes an RNG call** - only
  candidates that fail an *earlier*, roll-free eligibility check (dead, wrong formation slot,
  busy) are free. Miscounting which checks are "free" versus "cost a roll" will desync a
  multi-candidate simulation from the second candidate onward even if the first candidate's
  logic is right.
- **"Still deciding, retry next tick" (a `0` return from the AI slot) means genuinely fresh
  rolls next attempt, not a continuation of a partial roll sequence** - confirmed by
  `battle_dispatch_current_actor_action` re-invoking the exact same coroutine slot state, with
  nothing else running in between to consume RNG. Model a full retry as "start the per-candidate
  loop over from candidate 1 with fresh rolls," not as "resume where it left off."
- **The seed to validate against is the RNG state at the monster's own turn start, not the raw
  seed you inject at savestate load** - if any other actor (party or enemy) takes a turn earlier
  in the same round, their own rolls have already advanced the RNG by the time your monster's
  turn begins, and that advancement is seed-dependent (different amounts for different injected
  seeds), so it can't be corrected for with a constant offset. This cost an entire from-scratch
  re-derivation for Zombie Dragon on a mid-round savestate (`ZombieDragonT2.State`) before the
  real cause was found: the already-correct formula was being tested against the wrong seed.
  **Capture the live RNG value at the exact frame the monster becomes the active actor** (same
  detection this doc already uses elsewhere) and validate against *that*, not the injected value
  - a savestate positioned right at the very start of a round, before anyone else has acted, sidesteps
  this entirely (Dragon's own `Dragon.State` sweep needed no such correction for exactly this
  reason), so prefer capturing that shape of savestate when asking the user for one (see section 0).
- **Naive per-frame "did `Address.RNG` change" polling undercounts total roll counts, sometimes
  by an order of magnitude** - multiple `rand()` calls executing within a single game frame's CPU
  work collapse into what looks like one change when you only sample once per `emu.frameadvance()`.
  Fine for reading a specific RNG *value* at a known instant (e.g. "what's the seed when this
  monster's turn starts"); not reliable for *counting* how many rolls something consumed. For a
  real roll count, settle the RNG (wait for it to stop changing for N consecutive frames) and
  recover the exact count by forward-simulating from the start seed until it reaches that settled
  value (`scripts/SettleLightningRNG.lua` is a reusable template for this).

## 6. Before deriving a new formula, check whether it's already a shared one

Both move-selection and damage/RNG-cost formulas are reused heavily across monsters - a new
boss's own decompile matching an already-known shape is the expected case, not a coincidence
worth doubting:

- **Move/target selection itself is highly templated.** `lib/EnemyAIPredictor.lua`'s `KNOWN_AI`
  table already lists a dozen bosses whose decompile matches one of a handful of shapes (front-
  row scan + one threshold roll, sometimes with a round-counter override) without independent
  live validation for most of them - check there first. A genuinely live-validated formula (like
  Zombie Dragon's or Dragon's own) is strong evidence for the *shape* being right even for an
  unvalidated entry; what's worth re-checking per monster is the specific thresholds/eligibility
  rules, not the algorithm's overall structure.
- **Damage formulas are shared too, via `RngCallbackTable`** (`BattleState+0x1258`, a static
  cross-overlay function-pointer table every monster's overlay code calls back into `main.exe`
  through, since the overlay can't hardcode `main.exe` addresses at compile time). Only three
  distinct damage formulas are known to exist in the whole game so far: `calc_damage` (physical,
  ATK-DEF), `apply_elemental_multiplier` (player rune magic, base_power+MGC/2), and
  `calc_rune_element_attack_damage` (enemy elemental attacks, MGC-based - slot `86`/`+0x158`).
  Before assuming a new monster's attack needs a brand-new formula, check which `RngCallbackTable`
  slot its damage call routes through - it's very likely one of these three. A raw byte-pattern
  search for a slot's known call sequence (`lw v0,0x1258(reg) … lw v0,<slot offset>(v0)`) across
  every dumped overlay is how this project already found 11+ more `calc_rune_element_attack_damage`
  call sites across 7 other bosses without touching Ghidra's own (incomplete) xref search.
- **A quick live stat check beats guessing which stat a formula uses.** Before tracing which
  offset a damage formula reads, just read the attacker's own `CombatantRec` fields live
  (`ATK`/`+0x30`, `DEF`/`+0x32`, `MGC`/`+0x2c`) and sanity-check candidate formulas' *magnitude*
  against 2-3 observed damage values by hand - an ATK-based guess and an MGC-based guess are
  usually wildly different in scale (e.g. `250-DEF` vs `150-MGC`), so this alone often settles
  which stat is in play in under a minute, before opening a single decompile.
- **`calc_rune_element_attack_damage`'s "resistance" register-reuse bug is a general, predictable
  property of the shared function, not a monster-specific quirk** (see its own plate comment,
  `main.exe @ 0x800f8174`) - once you know a new caller's `element` argument and which register
  its own hit-loop reuses as a counter, you can *predict* which party slot gets an unearned
  accidental resistance from the decompile alone, then confirm it with one targeted live test,
  rather than discovering it via a broad live sweep first.

## Deliverables checklist

- [ ] Observational capture (`scripts/CaptureEnemyMoveResults.lua`, edited for the new monster)
      done *before* deriving the formula.
- [ ] Checked whether move selection matches an already-templated shape
      (`lib/EnemyAIPredictor.lua`'s `KNOWN_AI`) and whether the damage/RNG-cost formula reuses a
      known shared function (`calc_damage` / `apply_elemental_multiplier` /
      `calc_rune_element_attack_damage` via `RngCallbackTable`) before deriving either from
      scratch (see section 6).
- [ ] AI function address found and overlay dumped (`scripts/LocateEnemyAIFunction.lua`).
- [ ] Function(s) decompiled, renamed, and plate-commented in the overlay's own Ghidra program
      (`save_program` on that program specifically - it's a separate program from `main.exe`).
- [ ] Formula re-implemented from scratch and validated against every captured seed - move AND
      target, exact match, not just "close."
- [ ] Result written up in `Battle_Damage_Formula.md`'s "AI/enemy move selection" section
      (a compact pseudocode block plus the addresses) and cross-linked from `Turn_Order.md`.
- [ ] Project memory updated with the new monster's confirmed formula.
