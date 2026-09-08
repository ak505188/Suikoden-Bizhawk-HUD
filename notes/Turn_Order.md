# Turn Order — investigation history

This is the history behind
[docs/game_mechanics/Turn_Order.md](../docs/game_mechanics/Turn_Order.md):
corrections, dead ends, live-testing sessions, and open questions that
shaped the current clean write-up. Section headers below correspond to
sections in that doc.

## Turn-order weight formula

The stat at `combatant_rec+0x2a` is confirmed by direct match, not
inference — see "How this was confirmed" below. This corrects an earlier
guess in `Battle_Damage_Formula.md` that guessed `+0x26` for this role,
based on indirect usage in `calc_hit_chance`/`check_critical_hit` —
`+0x26` is a real stat used by those two functions, but it is not the
turn-order speed stat.

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

## Methodology lessons from two earlier false leads

Before the tied-stat savestate was available, two wrong conclusions were
drawn and then corrected — worth keeping for the general RE lessons, not
the specific history:

1. A stat-dominant battle seemed to "confirm" a completely unrelated
   sequential scan (`FUN_800f8578`, which just returns the first party
   member with no action queued) as the turn-order writer, purely because
   the highest-stat character also happened to be first in that scan
   order. Caught by noticing every combatant shared an identical
   precondition before the roll — meaning the traced function's output
   couldn't possibly depend on the stat difference being tested.
2. A legitimate RNG-caused divergence (a missed attack instead of a hit)
   was momentarily misread as a counter-attack trigger, because the
   differing value happened to sit in a field also cross-referenced from
   `battle_check_counter_attack`. An address being cross-referenced from a
   function doesn't mean landing on it implies that function's outcome —
   check actual game state, not just a plausible-sounding label.

General takeaways: (a) naive "scan forward N instructions for a matching
store" produces false positives whenever the base register gets
reassigned first — scan *backward* from the store to find the register's
real most recent definition, and treat `jal`/`jalr` as clobbering all
caller-saved registers; (b) before trusting a live A/B differential,
confirm the "before" state wasn't already deterministic for the path being
tested; (c) **a savestate engineered for a genuine tie is far more useful
for confirming a comparison formula than an arbitrary real battle**, which
will often have one candidate dominate enough that no jitter term could
ever matter. `FUN_800f8578` is a genuine, deliberate alternate path (see
the roll-gate section below), just gated behind a flag — it was only ever
wrongly credited as *the* writer in this one earlier test, not a red
herring in general.

## Naming note

`battle_select_enemy_target`'s name and original plate comment (from an
earlier, separate pass at this codebase) describe it purely as "which
party member does the current enemy's basic attack target," backed by a
live test against a specific boss fight. That may still be a genuine use
of this function — nothing in this investigation disproves it — but it is
now also confirmed to implement turn-order selection (see docs). A future
pass could confirm the enemy-targeting claim still holds and give the
function a name reflecting both uses (or split into two once the callers
are fully distinguished).

## Combatant record read timing for enemies

Building a live battle-state viewer (see the project's own
`modules/RNG/submodules/Combat`) to cross-check these addresses against
real gameplay surfaced two corrections and one behavioral quirk:

- `combatant_rec+0x10` is max HP, `+0x12` is current HP — initially
  guessed reversed.
- **An enemy's combatant record can read as all-zero/junk during command
  selection and even during another combatant's action animation** — it
  only becomes accurate once that specific enemy's own turn starts (see
  docs for the current write-up of this quirk). Most likely explanation:
  the game populates an enemy's live combatant record on-demand right
  before it's needed rather than up-front like it does for the party (a
  plausible memory/performance optimization on the original hardware).
  Confirmed by watching the same fields turn correct once the enemy
  actually acted.

## The roll-gate countdown and the pending→current copy

An earlier pass wrongly attributed `+0x1330 = 0`'s reset to `FUN_800dee44`
— full re-verification found `FUN_800dee44` never touches `+0x1330` at
all. The real writer, `battle_refresh_combatant_derived_stats`, and the
mechanism it implements, are documented in the current doc.

**Confirmed live which encounter populates a non-null `+0x1334`**: the
user's own suggested candidate — Queen Ant's fight, where her 3rd turn
always ends the battle — is exactly right. Her own AI function
(`queen_ant_ai_self_heal_and_select_move`, `va7.bin @ 0x80010ae0`) has no
round-count check or `+0x1330`/`+0x1334` reference at all, so the
mechanism isn't in her regular AI — but a user-supplied savestate sitting
at round 3 (`QueenAntT3End.State`) read live as `+0x1330=1`,
`+0x1334=0x8001139c`, resolving into a SEPARATE function in her own
overlay: `queen_ant_end_of_round_callback` (`va7.bin @ 0x8001139c`).
Decompiling it explains both "3rd turn always ends the fight" and, as an
unprompted bonus, her canonical ant-respawn mechanic (the same function
also revives any dead/removed enemy slot back to full HP every round) —
full writeup in
[Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md#queen-ants-round-3-battle-end-and-ant-respawn-mechanic).

**The user's second candidate — the scripted Ted-vs-Queen-Ant Hell-cast
fight — is ALSO confirmed** (a follow-up savestate, `QueenAntTed.State`):
the same hook family drives a completely different 3-stage forced-turn
chain there that forces Ted's turn (already-preset to cast Hell at Queen
Ant) to fire next with no player input, bypassing the normal roll entirely
— full writeup in
[Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md#the-scripted-ted-vs-queen-ant-forced-hell-cast-fight).
Seeing `SyncSignals+4` set in this unrelated context (obviously about
forcing a turn, not ending a fight) corrected an earlier framing of that
signal as literally an "end the battle" flag — it's a general "resync"
signal.

`FUN_800f8578`'s scan behavior (documented in the current doc) was traced
by direct decompilation. **Who arms `+0x48` to `1` (enabling this bypass)
was never located** — a naive instruction search for stores to offset
`0x48` returns 40+ hits in `main.exe`, almost all unrelated (the same
small offset is reused by many unrelated per-spell structs) — too generic
to search this way without a way to filter by base register. User's
hypothesis (plausible, unconfirmed): fires when a character is
mid-animation/busy while every other combatant has already finished
acting this round, so their turn needs to be handed over once they're free
without a fresh weighted roll — consistent with the bypass's own behavior,
just not yet proven to be the actual trigger condition.

**What resets `+0x1264` back up after a normal successful roll+copy** took
a dedicated pass to fully reconcile: found every write site
(`nRollGateCountdown`, `BattleState+0x1264`) via a targeted instruction
search — 9 real hits, no undisassembled-code gaps for this specific
offset. The resulting model is documented in the current doc's own "What
resets `ROLL_GATE_COUNTDOWN`" subsection. One item from that pass isn't
fully pinned down: the phase-4→5 round-cleanup function's own conditional
reset to `30` isn't tied to an exact real-world trigger — flagged for a
future pass if it matters. **Side-finding**: the same round-start function
also gives any combatant with status bit `0x20` (`id5`, "Sleep") a
50%-per-round chance (`rand()%100<50`) to have that bit cleared — nice
independent supporting evidence for the tentative "Sleep" identification
(see
[Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md)'s
status-effects section).

**Why the earlier (7-call, stat-dominant) savestate showed exactly 7
`rand()` calls in one frame**: resolved with no hidden loop needed —
`battle_select_enemy_target` calls `rand()` once per eligible candidate
inside its own weighted-selection loop (both the first-candidate and every
subsequent-candidate branch independently roll), now documented in the
current doc. This was always implied by the loop structure, just never
connected to the "7 calls" observation until this pass. If a savestate is
captured right at round start, before anyone has acted (every combatant
still `action_tag==0` and not busy), one single call to this function
rolls once per eligible combatant — a 6-party + 1-enemy fight is exactly 7
calls in that one tick, no unrolled loop or extra phase required.

## How a turn actually starts: `battle_dispatch_current_actor_action`

Prompted by a concrete question: is there a separate "go" flag, distinct
from `ActionType`/`AbilitySlot`/`TargetIdx` themselves, that tells the
engine "this combatant's action is ready, execute it now" — the kind of
thing a Lua script would need to set to drive a party member's action
without touching a real controller. Traced by function-boundarying and
decompiling the state `LAB_800f3fec` schedules for the *next* tick after
copying `PENDING_INDEX` into `CURRENT_ACTOR`, now named and commented in
Ghidra as `battle_dispatch_current_actor_action` (`0x800f40fc`).

The enemy-AI call site documented in the current doc was, at the time this
was traced, the enemy AI action-selection call site the project's docs had
flagged as "not yet located." **Zombie Dragon's own AI function body was
the first one traced and validated** (10/10 against live capture data —
see
[Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md)'s
"AI/enemy move selection" section); at that point every other monster's
own AI function was still untraced. (This is now stale — the linked
section's "Story boss AI roster" table shows most story bosses and several
regular enemies traced since.)

**Practical implication, corrected**: writing `ActionType`/`AbilitySlot`/
`TargetIdx` is necessary but **not sufficient** to script a party member's
action with no controller input — this was tested and found incomplete.
Pre-writing valid fields *and* a candidate "confirmed" flag while the
Fight/Run/Bribe/Free Will and command/target menu UI was still up did
nothing across 750 tested frames. The real gate and the practical
scripting recipe are documented in
[Scripted_Battle_Actions.md](../docs/game_mechanics/Scripted_Battle_Actions.md).

## Finding a living enemy's move-choice probability, per-instance

Prompted by a concrete question: given move-choice thresholds
(`Battle_Damage_Formula.md`'s per-monster `~51%`/`~77%`/etc. splits) are
confirmed hardcoded `slti` immediates compiled into each monster's own AI
function, is there still a way to locate a given *living* enemy's own
threshold starting from nothing but its combatant slot — i.e. a genuine
per-enemy (per-species) pointer chain, not a re-run of static analysis?
The resulting technique and its validation are documented in the current
doc.

**`p1` (`MonsterRecord+0x28`) is `EnemyData.pActionScriptTable`** — this
was confirmed live after the user asked "what's the attack script table?
at 0x28," since it was previously only a GUESSED label in
`scripts/ScanMonsterRecords.py`'s own comment, never verified. Confirmed
via `scripts/CheckAttackScriptTable.lua`: three separate call sites
(`ant_commanded_attack_damage`, `ant_commanded_attack_cleanup`, and
`apply_uncovered_attack_damage`) independently converging on the same
field is about as solid a confirmation as this gets. Renamed in Ghidra:
`EnemyData`'s previously-unnamed `+8` sub-field (part of a 6-byte
`aUnk_0x06` blob) is now `pActionScriptTable` (`void *`), main.exe struct,
saved.

## Open questions / not yet done

- Whether `battle_select_enemy_target` is genuinely dual-purpose (enemy
  targeting AND turn order) or whether the original targeting analysis
  needs revisiting — not re-verified in this pass.
- Tie-breaking behavior when two weights are exactly equal (not just
  close) — not tested.
- **Is `battle_execute_player_attack` called from anywhere besides the
  enemy-AI-decline fallback documented in the current doc?** `get_xrefs_to`
  finds exactly one real code-level call site (the one already
  documented). There's a second, `DATA`-only xref into it from an
  unlabeled table at `0x8016b6b0` (12 mixed entries — some clearly generic
  engine utilities in the `0x8014xxxx` range, a couple of already-known
  animation-adjacent helpers in `0x800e2xxx`, and this function at index
  5) — but nothing in currently-disassembled code reads *from* that
  table's own address (no xrefs to `0x8016b6b0` either, and no
  `lui`/`addiu` construction of it found via byte-pattern search), so its
  actual reader is invisible to every search tried, most likely sitting in
  undisassembled bytes or reached via computed/per-combatant addressing
  rather than a fixed instruction. Doesn't change the standing conclusion
  — real player-side Attack actions go through `battle_execute_enemy_
  attack`, not this function — but the second reference is a loose end
  worth revisiting if more of `main.exe` gets disassembled later.
- Full confirmation of the `DAT_8017be3c` struct layout as a real Ghidra
  struct — **done**, see
  [Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md#the-central-battle-state-struct):
  `DAT_8017be3c` is now typed `BattleState *` (renamed `g_pBattleState`),
  with real `CombatantRec`/`EnemyData`/`ClassPtrEntry`/`MonsterRecord`
  struct types for the nested arrays. Large regions with known-but-unpinned
  fields (sync-signal array, per-status duration-slot table,
  animation-interpreter scratch state) remain explicit padding rather than
  guessed layouts.
