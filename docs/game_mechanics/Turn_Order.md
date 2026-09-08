# Turn Order

Covers how Suikoden 1 decides which combatant acts next in battle.
Complements [Battle_Damage_Formula.md](./Battle_Damage_Formula.md) — that
page covers what happens once a combatant is already acting; this page
covers how that combatant gets chosen.

## Turn-order weight formula

```
weight = combatant_stat(+0x2a) * 10 - 5 + rand() % 10
```

Algebraically identical to `speed = AGL*10 + (rand()%10 - 5)`, the formula
an independently-derived PSP disassembly gives for this mechanic. Each
combatant's weight is computed once; the highest wins and acts next.
`rand()` here is **RNG2**, not the raw 32-bit RNG state (see below) — so
the `% 10` operates on RNG2.

The code lives in **`battle_select_enemy_target`** (`0x800f4698`), despite
that name (see "Naming note" below). It loops `idx = 1 .. DAT_8017be3c+0x24`
(**all** combatants, party and enemies both — not party-only), skipping
anyone whose action-tag (`combatant_rec+0x46`) is nonzero or whose
species-record `+5` byte is set, computes each remaining candidate's weight
from their own `+0x2a` stat, and keeps the running maximum (re-validating
each non-first candidate via `check_combatant_valid_target`). A "forced
target" flag (`+0xdc`-array `+5` byte) can make it return `-1` instead if no
valid candidate was found yet — likely a signal to the caller to route to a
different, forced-target-specific path.

Each eligible candidate consumes exactly one `rand()` call for its own
jitter roll (both the first-candidate and every subsequent-candidate branch
roll independently) — e.g. a 6-party + 1-enemy fight where nobody has acted
yet costs exactly 7 `rand()` calls for that single turn-order roll.

The stat at `combatant_rec+0x2a` (`DAT_8017be3c+0xb40+idx*0x54+0x2a`) is the
AGL/speed stat used for turn order — a different stat from
`combatant_rec+0x26` (SKL), which `calc_hit_chance`/`check_critical_hit`
use instead. The two are easy to confuse since they're both plausible
"speed-ish" fields at nearby offsets.

## Naming note

`battle_select_enemy_target`'s name describes it as "which party member
does the current enemy's basic attack target," but it also implements
turn-order selection when called from the `+0x3420`-writing function gated
on the `+0x1264` countdown (see below). Most likely explanation: a single
"pick the highest-weighted candidate, with jitter" utility reused for two
different purposes (enemy targeting priority and turn order), both keyed
off the same `+0x2a` stat. Not renamed here since extensive existing
documentation depends on the name.

## Does it use RNG or RNG2?

**RNG2.** `rand()` in `main.exe` (`0x80147e38`) is a thin wrapper straight
into the PS1 BIOS syscall table (`jr` to a fixed BIOS entry point) — not
custom game code. The PS1 BIOS's `rand()` is well-documented in the
homebrew community: it steps the LCG (`seed = seed*0x41c64e6d + 0x3039`)
and returns `(seed >> 16) & 0x7fff` — exactly this project's `getRNG2()`
formula (see [RNG.md](./RNG.md)). Every other RNG-consuming battle function
in this codebase (`calc_damage`, `check_critical_hit`, `calc_hit_chance`,
`check_dodge_counter`, `check_flee`, and `battle_select_enemy_target`)
calls this exact same `rand()`, with no exceptions found.

## Combatant record read timing for enemies

An enemy's combatant record (see
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md#the-central-battle-state-struct))
can read as all-zero/junk during command selection and even during another
combatant's own action animation — it only becomes accurate once that
specific enemy's own turn starts. Party members' records are populated
correctly from the start of battle; this lag is enemy-specific, most likely
because the game populates an enemy's live record on-demand right before
it's needed, rather than up-front like it does for the party. This is not a
bug in the documented offsets — the same fields read correctly once the
enemy actually acts — just something to know before assuming a zeroed-out
enemy row means the wrong address.

## The roll-gate countdown and the pending→current copy

`battle_advance_turn` (`0x800f3e98`) is the function that calls
`battle_select_enemy_target` and owns `+0x3420`. It's a per-tick
state-machine step — called once per game tick with a state-slot index,
and it writes the address of whichever handler should run *next* tick into
a per-slot function-pointer array (`(&DAT_8017da90)[slot_idx]`), a manual
coroutine pattern rather than a plain loop.

Each tick:
1. Decrements `DAT_8017be3c+0x1264` (the roll-gate countdown). If it's still
   `>0` after the decrement, the function returns immediately — no reroll
   this tick. This is what makes the turn-order roll happen once per
   round/transition instead of every single tick.
2. Once the countdown reaches 0: calls `battle_select_enemy_target()` and
   unconditionally stores the result into `g_nPendingIndex` (`+0x3420`).
3. An optional callback (`+0x1334`, enabled via `+0x1330`) can redirect to a
   different next-state (`LAB_800f4628`) instead of the normal path.
   `+0x1330` is automatically recomputed every round-start by
   `battle_refresh_combatant_derived_stats` (`0x800f707c`) as
   `(+0x1334 != 0) ? 1 : 0` — there's no separate "arm" step; the callback
   is simply enabled whenever a callback pointer has been configured.
   `+0x1334` itself is set by `FUN_800dee44` (a battle-init routine that
   runs on **every** battle, not just scripted ones) from a per-encounter
   setup table at `+0x1340`, populated by
   `battle_init_apply_scripted_encounter_callback` (`0x800de040`) during
   battle init. An ordinary random encounter resolves this to a null
   callback (`+0x1330` stays `0`); a scripted encounter with special
   end-of-battle/forced-turn logic provides a real one.

   Two confirmed real-world uses of this hook, both in Queen Ant's Mt.
   Seifu fight (`va7.bin`): her round-3 battle-end/ant-respawn callback
   (`queen_ant_end_of_round_callback`, `0x8001139c` — see
   [Battle_Damage_Formula.md](./Battle_Damage_Formula.md#queen-ants-round-3-battle-end-and-ant-respawn-mechanic))
   sets `SyncSignals+4 = 1` when `dwRoundNumber > 2`; and the scripted
   Ted-vs-Queen-Ant "forced Hell cast" fight uses the same hook family to
   drive a separate 3-stage forced-turn chain
   (`scripted_forced_turn_delay_arm` → `_tick` → `_commit`, all in
   `va7.bin`) that forces Ted's pre-set Hell cast to fire with no player
   input, bypassing the normal roll entirely (see
   [Battle_Damage_Formula.md](./Battle_Damage_Formula.md#the-scripted-ted-vs-queen-ant-forced-hell-cast-fight)).
   `SyncSignals+4` is therefore a general "force a full round-state resync"
   signal, not literally an "end the battle" flag.

   When the hook fires (`LAB_800f4628`): calls the `+0x1334` callback, and
   if it returns nonzero, sets `+0x30 = 1` (the "skip camera cue" flag) and
   re-enters `battle_advance_turn`'s own coroutine slot — i.e. this
   "override" just forces an immediate reroll, not a substitution of a
   different actor. A zero return schedules the normal `LAB_800f3fec`
   continuation, same as the non-override path.
4. If `+0x48 == 1`, also calls `FUN_800f8578`: scans party members for the
   first with `ActionTag(+0x46)==0` and not busy (`EnemyData+0x5==0`); if
   found, directly sets `g_nPendingIndex` (`+0x3420`) to that index,
   bypassing the weighted-RNG roll entirely — "someone still needs to act
   and isn't mid-animation, just give them the turn." If the loop completes
   with no valid candidate, it clears its own gate flag (`+0x48`) back to
   `0` so it isn't retried until something re-arms it.
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

### What resets `ROLL_GATE_COUNTDOWN` (`+0x1264`)

- **Round start**: `battle_refresh_combatant_derived_stats` (`0x800f6ea0`,
  the function that increments `dwRoundNumber`) unconditionally resets it
  to `0x1e` (30) as its last act before scheduling `LAB_800f72f0`.
- **Mid-round, per actor**: Defend resets it to `0` (immediate reroll of
  the next actor). A successful Attack dispatch
  (`battle_dispatch_current_actor_action`) resets it to whatever a
  separate, fixed-address global (`0x8017be44` — not `BattleState`'s own
  `dwCurrentActorIdx` field) holds. That global has exactly one writer in
  all of `main.exe`: `battle_menu_fight_run_bribe_freewill` (`0x800ea480`)
  sets it to the literal constant `10`, only on the Free Will branch
  (choice `3`) — Fight/Run/Bribe never touch it. So this reset really means
  "10 if the round was entered via Free Will, otherwise a stale leftover
  value" — a fixed constant, just conditionally written.
- Rune/Item/Unite never touch the field directly — they defer to their own
  wait-for-animation coroutine states.
- `battle_advance_turn`'s own "no eligible combatant" branch resets it to
  `30` (see step 5 above).
- A phase-4→5 round-cleanup function (`0x800f74a8`, tags a
  `BattleState+0x3428` phase counter) also conditionally resets it to `30`
  again after removing invalid combatants.

## How a turn actually starts: `battle_dispatch_current_actor_action`

`battle_dispatch_current_actor_action` (`0x800f40fc`) is the state
`LAB_800f3fec` schedules for the tick right after `PENDING_INDEX` is copied
into `CURRENT_ACTOR`. There is no separate "go" flag, distinct from
`ActionType`/`AbilitySlot`/`TargetIdx` themselves (see
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md#action-selection-combatant_rec0x460x49)),
that tells the engine "this combatant's action is ready, execute it now" —
the kind of thing a Lua script would need to set to drive a party member's
action without touching a real controller (see "Practical implication"
below).

This function runs every tick, reads `CURRENT_ACTOR` (`+0x8`), and
branches:

- **Enemy** (`CURRENT_ACTOR > PARTY_COUNT`): calls a per-monster-`Id`
  function pointer read from `attack_data_table[Id]+0x30` — the *same*
  per-`Id` row `calc_damage`/`apply_elemental_multiplier` read for elemental
  compatibility, so it doubles as a small vtable. It's passed the
  battle-state pointer, polled every tick (`0` = still deciding, retry next
  tick; `-1` = falls back to calling `battle_execute_player_attack(actor)`
  directly — a misleading name, since it's evidently a generic
  single-target-physical-attack executor reused here for any enemy whose AI
  slot declines to act specially, not something player-exclusive; anything
  else = done, advance). A combatant with `enemy_data+0x4a` bit `0x20` set
  skips the AI call entirely and immediately resolves as "did nothing"
  (marks `ActionTag=1`, forces an immediate reroll) — a "can't act this
  turn" flag, tentatively named "Sleep" (see
  [Battle_Damage_Formula.md](./Battle_Damage_Formula.md)'s status-effects
  section). `battle_refresh_combatant_derived_stats` gives any combatant
  carrying this bit a 50%-per-round chance to have it cleared — a random
  wake-up check.
- **Party member** (`CURRENT_ACTOR <= PARTY_COUNT`): reads `ActionType`
  (`+0x47`) **directly, with no other precondition** — not `ActionTag`, not
  any "confirmed" bit. `ActionType` `0`/`2`/`3`/`4` dispatch straight into
  `battle_execute_enemy_attack`/`battle_select_special_ability`/
  `battle_try_special_attack`/`battle_select_unite_attack` respectively
  (`battle_execute_enemy_attack` is genuinely shared between both party and
  enemy sides despite the name). `ActionType==1` (Defend) *and every other
  value*, including the `255` unset sentinel, fall through to the same
  call: **`battle_resolve_defend_action`** (renamed from `FUN_800f40b8`,
  `0x800f40b8`) — Defend needs no target/resolver, so the same "nothing to
  do, wrap up the turn" code doubles as the fallback for an
  invalid/not-yet-populated `ActionType`. Its body: set
  `combatant_rec(actor)+0x46` (`ActionTag`) `= 1`, force
  `ROLL_GATE_COUNTDOWN` (`+0x1264`) `= 0` (reroll the next actor on the very
  next tick instead of waiting out the normal countdown), set `+0x30 = 1`
  (the same "skip the camera cue" flag `battle_advance_turn`'s continuation
  checks).

**Practical implication**: writing `ActionType`/`AbilitySlot`/`TargetIdx`
directly is **not sufficient** to script a party member's action with no
controller input. There's a real, separate gate: the round's
Fight/Run/Bribe/Free Will prompt and each party member's own command/target
menu is a genuine input-driven UI system, distinct from this dispatcher,
and this whole coroutine chain simply never starts running until that UI's
own final "Ok?" confirm is processed. The practical recipe — simulate a
fixed, content-independent sequence of taps through that UI, then overwrite
the selections it produced before the final confirm — is written up in
[Scripted_Battle_Actions.md](./Scripted_Battle_Actions.md); this section's
`battle_dispatch_current_actor_action` mechanism is still exactly what
executes each action afterward, it just isn't the whole story.

## Finding a living enemy's move-choice probability, per-instance

Move-choice thresholds (see [Battle_Damage_Formula.md](./Battle_Damage_Formula.md)'s
per-monster `~51%`/`~77%`/etc. splits) are hardcoded `slti` immediates
compiled into each monster's own AI function — not loaded from any data
table, confirmed by reading the raw instruction word at the comparison site
in both the static overlay file and live RAM during a real battle
(byte-for-byte identical). A given *living* enemy's own threshold can be
located starting from nothing but its combatant slot, via a genuine
per-enemy (per-species) **pointer chain** — no static/Ghidra analysis
required at runtime. Ghidra already has the relevant structs fully typed
(confirmed via `get_struct_layout`, matching every offset this project had
already reverse-engineered by hand):

```
BattleState.pAttackDataTable   @ +0x1344  (void* - pointer to an array of per-species row pointers)
BattleState.EnemyDataArray     @ +0x50    (EnemyData[], stride 0x8c - the SAME array this
                                            project already knows as "the enemy AI-struct")
EnemyData.bId                  @ +0x00    (this slot's monster species ID)
EnemyData.bAnimTargetIdx       @ +0x04
EnemyData.bBusyMutex           @ +0x05
EnemyData.wEffectFlags         @ +0x40
```

The chain, entirely in live memory, needs no Ghidra/ROM access at all:

```
base       = BattleState (Address.BATTLE_STATE_PTR)
bId        = read_u8 (base + 0x50 + slot*0x8c)                    -- EnemyDataArray[slot].bId
rowArray   = read_u32(base + 0x1344)                               -- pAttackDataTable
speciesRow = read_u32(sanitize(rowArray) + bId*4)                  -- per-species row pointer
aiFuncAddr = read_u32(sanitize(speciesRow) + 0x30)                 -- the AI function's live address
```

`aiFuncAddr` is a real `0x80xxxxxx` code address, live and correct for
whichever species currently occupies that slot — the exact same lookup
`battle_dispatch_current_actor_action` performs every tick to call the
enemy's own AI. From there, scanning forward through **live instruction
memory** (not the static file) for the `ori v0,zero,0x7fff` signature word
(`0x34027fff` — see below for why this is a reliable anchor) and reading
the immediate off the `slti` that follows recovers that specific enemy's
own move-choice threshold(s), with zero prior knowledge of which function
or overlay it lives in.

Validated against `QueenAnt.State`
(`scripts/CheckPerEnemyThresholdPointerChain.lua`): resolved all 4 enemies
in that fight purely through this chain, with zero Ghidra involvement, and
every result matched the already-known static values exactly:

| slot | bId | resolved AI function | resolved threshold |
|---|---|---|---|
| 6/7/8 (Soldier Ants) | 2 | `0x800106b0` (matches `soldier_ant_ai_select_target_and_move`) | `0x4d` (~77%) |
| 9 (Queen Ant) | 1 | `0x80010ae0` (matches `queen_ant_ai_self_heal_and_select_move`) | `0x33` (~51%) |

**`speciesRow` IS the static `MonsterRecord` `Monster_AI_Static_Catalog.md`
already catalogs — the same struct, not a separate live copy.** Confirmed
by decoding the charmap name field (offset `+0`) at the live-resolved
`speciesRow` address (reads `"Soldier Ant"`/`"Queen Ant"` correctly), and
Soldier Ant's resolved address (`0x8006500c`) matches exactly what an
independent charmap search finds for that monster.
`scripts/ScanMonsterRecords.py`'s own `MonsterRecord` layout (used to
generate that catalog by scanning raw overlay bytes, no emulator needed) is
therefore the complete struct for `speciesRow`:

```
+0x00 (16 bytes)  name (charmap-encoded, null-terminated)
+0x10 (1 byte)    level
+0x11 (1 byte)    footprint
+0x12 (u16 x 7)   HP, PWR, SKL, DEF, SPD, MGC, LUK
+0x20 (8 bytes)   unidentified
+0x28 (u32)       p1 - "attack script table" pointer (unidentified further)
+0x2c (u32)       p2 - unidentified
+0x30 (u32)       pAiFunction - THE SAME field `battle_dispatch_current_actor_action` reads
```

So the live pointer chain and the static file-scanning tool converge on the
identical structure: `Monster_AI_Static_Catalog.md` finds every monster's
own copy of this record by scanning each overlay file's raw bytes offline;
`pAttackDataTable[bId]` finds the SAME record live, for whichever species
currently occupies a given battle slot, with the AI function pointer at the
same `+0x30` offset either way.

**`p1` (`MonsterRecord+0x28`) is `EnemyData.pActionScriptTable`.** The
static value at `MonsterRecord+0x28` is copied verbatim, per-instance, into
the live `EnemyData+8` field at battle setup (bit-exact match for both
Soldier Ant and Queen Ant) — this is the SAME pointer
`ant_commanded_attack_damage`, `ant_commanded_attack_cleanup`, and
`apply_uncovered_attack_damage` (main.exe `0x800f5960`, the generic
single-target attack resolver) all independently read as
`*(EnemyData(x)+8)+OFFSET` for that combatant's own action scripts.

Contents (per-monster, read live for Queen Ant/Soldier Ant; `+0x00`/`+0x0c`
not yet independently attributed to a confirmed call site):

| offset | role | confirmed via |
|---|---|---|
| `+0x00` | unidentified | - |
| `+0x04` | "primary action" script | Queen Ant's own value here (`0x8006c108`) exactly matches her already-documented self-heal script address |
| `+0x08` | "hit" script | `ant_commanded_attack_damage` (`*(EnemyData+8)+8`) and `apply_uncovered_attack_damage` (`*(iVar4+8)+8`) both read this exact slot |
| `+0x0c` | unidentified | - |
| `+0x10` | "return to idle" script | `ant_commanded_attack_cleanup` (`*(EnemyData+8)+0x10`) |

`p2` (`MonsterRecord+0x2c`) does NOT match the live resource-table pointer
— a separate, still unidentified field.

One gotcha worth recording: the gap between the `ori v0,zero,0x7fff`
anchor and its own `slti` is NOT constant — Soldier Ant's formula has an
extra `%100` step (`((roll*100)/32767)%100 < threshold`), inserting a whole
second `div`+`mfhi` sequence that pushes its `slti` out to +0x64 from the
anchor, versus Queen Ant's simpler `(roll*100)/32767 < threshold` shape
where the `slti` follows almost immediately. A byte-scanner needs a wide
enough search window (100+ bytes) after the anchor to catch both shapes —
an initial 64-byte window found Queen Ant's threshold but missed Soldier
Ant's entirely, silently reporting "not found" instead of a wrong value.
