# Turn Order

Covers how Suikoden 1 decides which combatant acts next in battle.
Complements [Battle_Damage_Formula.md](./Battle_Damage_Formula.md) — that
page covers what happens once a combatant is already acting; this page
covers how that combatant gets chosen. **The formula and stat offset are
now confirmed** via live gameplay verification against a real tied-stat
scenario, cross-checked against an independently-derived PSP disassembly.

## The confirmed formula

```
weight = combatant_stat(+0x2a) * 10 - 5 + rand() % 10
```

Algebraically identical to `speed = AGL*10 + (rand()%10 - 5)`, the formula
an externally-supplied PSP disassembly gave for this mechanic. Each
combatant's weight is computed once; the highest wins and acts next.
`rand()` here is confirmed to be **RNG2**, not the raw 32-bit RNG state
(see below) — so the `% 10` operates on RNG2.

**The code lives in `battle_select_enemy_target` (`0x800f4698`)**, despite
that name (given by an earlier, less complete pass at this codebase) —
see "Naming note" below. It loops `idx = 1 .. DAT_8017be3c+0x24` (**all**
combatants, party and enemies both — not party-only), skipping anyone
whose action-tag (`combatant_rec+0x46`) is nonzero or whose species-record
`+5` byte is set, computes each remaining candidate's weight from their
own `+0x2a` stat, and keeps the running maximum (re-validating each
non-first candidate via `check_combatant_valid_target`). A "forced
target" flag (`+0xdc`-array `+5` byte) can make it return `-1` instead if
no valid candidate was found yet — likely a signal to the caller to route
to a different, forced-target-specific path.

The stat at `combatant_rec+0x2a` (`DAT_8017be3c+0xb40+idx*0x54+0x2a`) is
the AGL/speed stat — confirmed by direct match, not inference (see next
section). This corrects an earlier guess in `Battle_Damage_Formula.md`
that guessed `+0x26` for this role, based on indirect usage in
`calc_hit_chance`/`check_critical_hit` — `+0x26` is a real stat used by
those two functions, but it is not the turn-order speed stat.

## How this was confirmed: a real coin-flip test case

Earlier passes at this investigation tried a battle where one character's
stat dominated so heavily that no jitter could ever change the winner —
useless for confirming the formula plays a causal role at all. The
breakthrough was a savestate the user prepared specifically to remove that
confound: **the main character (slot 1) and Viktor (slot 2), both with an
identical stat of 102** — a genuine tie where RNG jitter alone determines
the winner. The user had independently verified via their own (PSP-based)
tooling: with RNG unmodified, Viktor acts first; advancing RNG by one LCG
step before the roll flips it to the main character acting first.

Reproduced live in BizHawk: loaded the savestate twice, once unmodified
and once with `Address.RNG` advanced by one LCG step
(`rng' = rng*0x41c64e6d + 0x3039`) immediately after load, then compared
outcomes after 10 frames. Confirmed:

- `DAT_8017be3c+0x3420` read `2` (Viktor) in the unmodified run and `1`
  (main character) in the RNG-advanced run — matching the user's
  independently-derived expectation exactly, in both directions.
- A full-RAM scan (every 4-byte-aligned location across all 2MB) for
  "reads `2` in one run, `1` in the other" turned up only two addresses:
  this field and `DAT_8017be3c+0x8`, which copies from it. No decoy
  candidates anywhere else in memory.
- Both combatants' `combatant_rec+0x2a` read exactly `102`, matching the
  user's stated stat value precisely.

This is about as clean a confirmation as static analysis plus live testing
can produce: a real tied-stat race, an independently-predicted RNG-driven
flip, and a memory field that reproduces the correct answer in both
directions with no other candidate field anywhere in RAM.

## Two false leads corrected along the way (kept for the methodology lessons)

Earlier in this same investigation, before the tied-stat savestate was
available:

1. **Wrongly claimed a stat-dominant battle "confirmed" the winner.**
   Traced `DAT_8017be3c+0x3420`'s writers and found `FUN_800f8578` — a
   *non-RNG* sequential scan that just returns the first party member
   with no action queued. In a battle where the highest-stat character
   also happened to be sequentially first, this returned the "correct"
   answer for a completely unrelated reason. Caught by checking:
   **every** combatant had an identical precondition (`action_tag==0`)
   before the roll, meaning that scan's output couldn't possibly depend
   on the stat difference. The tied-stat test later proved
   `FUN_800f8578` isn't the relevant writer at all in the RNG-driven
   case — `battle_select_enemy_target` is, reached via a different
   writer function (~`0x800f3ea0`, gated on a countdown at `+0x1264`
   reaching zero) that this investigation had already found but hadn't
   yet actually decompiled to see what it really computes.
2. **Misread a legitimate RNG-caused divergence as a counter-attack
   trigger.** Running the same stat-dominant battle with a forced RNG
   seed produced a different outcome in a callback field also referenced
   from `battle_check_counter_attack`; assumed this meant a counter had
   triggered. The user corrected this directly by watching both runs:
   one attack hit for 87 damage, the other simply *missed* (no counter)
   — an entirely ordinary consequence of `calc_hit_chance`'s own `rand()`
   roll landing differently once the RNG stream is perturbed, several
   rolls downstream of the original turn-order calls. Lesson: an address
   being cross-referenced from a function doesn't mean landing on it
   implies that function's "positive" outcome — check what the actual
   game state shows, not just what a plausible-sounding label suggests.

General methodology notes worth keeping for future RE work here:
- Naive "load global, scan forward N instructions for a matching store"
  produces false positives whenever the base register gets reassigned
  before the store (three separate false "writers" of `+0x8` were found
  this way — unrelated code that happened to also use offset `8` from a
  *different*, coincidentally-reused base register). Fix: scan *backward*
  from the store to the register's actual most recent definition, and
  treat `jal`/`jalr` as clobbering all caller-saved registers even though
  a static decoder can't know a callee's real return-register usage.
- Before trusting a live A/B differential result, check whether the
  "before" state was already deterministic for the code path involved —
  the first false lead above happened because every combatant's
  precondition was identical, making the traced function's output
  independent of the very thing (RNG) being tested.
- **A savestate engineered for a genuine tie is far more valuable for
  confirming a comparison formula than an arbitrary "real" battle** — an
  arbitrary battle will often have one candidate dominate enough that no
  jitter term could ever matter, which looks like confirmation but proves
  nothing.

## Naming note

`battle_select_enemy_target`'s name and original plate comment (from an
earlier, separate pass at this codebase) describe it purely as "which
party member does the current enemy's basic attack target," backed by a
live test against a specific boss fight. That may still be a genuine use
of this function — nothing here disproves it — but it is now also
confirmed to implement turn-order selection when called from the
`+0x3420`-writing function gated on the `+0x1264` countdown. Most likely
explanation: a single "pick the highest-weighted candidate, with jitter"
utility reused for two different purposes (enemy targeting priority and
turn order), both keyed off the same `+0x2a` stat. Not renamed here since
extensive existing documentation depends on the name; a future pass could
confirm the enemy-targeting claim still holds and give the function a name
reflecting both uses (or split into two once the callers are fully
distinguished).

## Does it use RNG or RNG2?

**RNG2.** `rand()` in `main.exe` (`0x80147e38`) is a thin wrapper straight
into the PS1 BIOS syscall table (`jr` to a fixed BIOS entry point) — not
custom game code. The PS1 BIOS's `rand()` is well-documented in the
homebrew community: it steps the LCG (`seed = seed*0x41c64e6d + 0x3039`)
and returns `(seed >> 16) & 0x7fff` — exactly this project's `getRNG2()`
formula (see [RNG.md](./RNG.md)). Every other RNG-consuming battle
function already verified in this codebase (`calc_damage`,
`check_critical_hit`, `calc_hit_chance`, `check_dodge_counter`,
`check_flee`, and now `battle_select_enemy_target`) calls this exact same
`rand()`, with no exceptions found.

## Live-tool cross-check findings (2026-09, `modules/RNG/submodules/Combat`)

Building a live battle-state viewer (see the project's own module of that
name) to cross-check these addresses against real gameplay surfaced two
corrections and one behavioral quirk worth recording:

- `combatant_rec+0x10` is max HP, `+0x12` is current HP — initially
  guessed reversed.
- **An enemy's combatant record can read as all-zero/junk during command
  selection and even during another combatant's action animation** — it
  only becomes accurate once that specific enemy's own turn starts. Party
  members' records are populated correctly from the start of battle; this
  lag is enemy-specific. Most likely explanation: the game populates an
  enemy's live combatant record on-demand right before it's needed rather
  than up-front like it does for the party (a plausible memory/performance
  optimization on the original hardware). This isn't a bug in the offsets
  documented above — confirmed by watching the same fields turn correct
  once the enemy actually acted — just something to know before assuming
  a zeroed-out enemy row means the wrong address.

## The roll-gate countdown and the pending→current copy (solved)

The function that calls `battle_select_enemy_target` and owns `+0x3420` is
now identified, function-boundaried, and fully decompiled: **`battle_advance_turn`**
(`0x800f3e98`, previously only approximately located at "~0x800f3ea0"). It's
a per-tick state-machine step — called once per game tick with a state-slot
index, and it writes the address of whichever handler should run *next*
tick into a per-slot function-pointer array (`(&DAT_8017da90)[slot_idx]`), a
manual coroutine pattern rather than a plain loop.

Each tick:
1. Decrements `DAT_8017be3c+0x1264` (the roll-gate countdown). If it's still
   `>0` after the decrement, the function returns immediately — no reroll
   this tick. This is what makes the turn-order roll happen once per
   round/transition instead of every single tick.
2. Once the countdown reaches 0: calls `battle_select_enemy_target()` and
   unconditionally stores the result into `g_nPendingIndex` (`+0x3420`).
3. An optional callback (`+0x1334`, enabled via `+0x1330`) can redirect to a
   different next-state (`LAB_800f4628`) instead of the normal path — not
   traced further, likely a scripted/forced-turn override hook.
4. If `+0x48 == 1`, also calls `FUN_800f8578` — **this resolves an earlier
   open question**: the sequential "first party member with no action
   queued" scan (previously found and discarded as a false lead for the
   *stat-dominant-battle* miscall) turns out to be a genuine, deliberate
   alternate path, just gated behind this flag. It was never a red
   herring in general — only wrongly credited as *the* writer in that one
   earlier test.
5. Re-reads `g_nPendingIndex`:
   - `-1`: no valid target (a "forced target" block) — nothing more happens.
   - `0`: **no eligible combatant existed for the roll** (e.g. every
     combatant's `action_tag` was already nonzero — round complete, nobody
     left to act). Resets the countdown to `0x1e` (**30**) and moves to a
     wait-state (`LAB_800f43e0`) — i.e. try again in ~30 more ticks.
   - a real 1-based index: compares it against `PARTY_COUNT` (`+0x1c`)
     relative to the *current* `CURRENT_ACTOR` (`+0x8`) to detect a
     party↔enemy turn transition, setting a `+0x44` flag if the turn is
     crossing that boundary (likely a UI/camera cue), then moves to the
     normal continuation state (`LAB_800f3fec`).

**`LAB_800f3fec` is where `g_nPendingIndex` actually gets copied into
`g_nCurrentActorIdx`** — `*(base+0x8) = *(base+0x3420)` at `0x800f4068`,
right after also clearing `+0x30` and `+0x44`. Since this copy runs on the
very next state-machine tick after the roll (not some later, unrelated
event), **`CURRENT_ACTOR` and `PENDING_INDEX` will read as equal in a live
viewer almost all the time** — they only differ for the single internal
tick between the roll and the copy, which is far shorter than one visible
frame in practice. Seeing them match is expected behavior, not a bug.

## Open questions / not yet done

- Whether `battle_select_enemy_target` is genuinely dual-purpose (enemy
  targeting AND turn order) or whether the original targeting analysis
  needs revisiting — not re-verified in this pass.
- What resets the `+0x1264` countdown back up after a *normal* successful
  roll+copy (only the "no eligible combatant" branch's reset to 30 has
  been traced) — is it always a fixed value, or does it depend on the
  animation/action duration of the combatant that just acted?
- The `+0x1330`/`+0x1334` callback-redirect path (`LAB_800f4628`) and the
  `+0x48`-gated `FUN_800f8578` alternate path — not traced in detail.
- Why the earlier (7-call, stat-dominant) savestate showed exactly 7
  `rand()` calls in one frame (matching 6 party + 1 enemy) if the actual
  selection is a single function call per invocation, not an obviously
  unrolled 7-iteration loop in the disassembly — worth reconciling once
  more of `battle_select_enemy_target`'s callers and the surrounding
  control flow are mapped.
- Tie-breaking behavior when two weights are exactly equal (not just
  close) — not tested.
- Full confirmation of the `DAT_8017be3c` struct layout as a real Ghidra
  struct — still raw offset arithmetic throughout.
