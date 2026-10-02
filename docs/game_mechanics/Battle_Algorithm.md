# Battle Algorithm

The master battle loop, assembled from [Turn_Order.md](./Turn_Order.md),
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md), and
[Scripted_Battle_Actions.md](./Scripted_Battle_Actions.md) into one ordered,
tick-level walkthrough. This is the algorithm a pure-code battle simulator
needs to implement: it consumes a `BattleSnapshot`-shaped initial state
(`lib/BattleSnapshot.lua`) and produces a `TurnResult`-shaped outcome
(`lib/BattleRoundInput.lua:runTurn()`) without touching the emulator. Each
step is a pseudocode skeleton linking to the page with the full derivation.
★ marks every `rand()` call.

Rewritten 2026-09-24 from fresh decompiles of every function below. A copy
of the same model lives in the sibling Suikoden-RNG-lib project as
`TickBasedAlgorithm.md`. Anything not yet confirmed live is listed under
[Not yet confirmed](#not-yet-confirmed).

Two easy-to-trip-over facts:

- The attack executors are named backwards in Ghidra. A *party* basic Attack
  runs `battle_execute_enemy_attack`; an *enemy's* basic Attack runs
  `battle_execute_player_attack`.
- Enemy basic attacks never roll a crit. Only the party path calls
  `check_critical_hit`.

## RNG and timing

```
rand():  seed = seed * 0x41c64e6d + 0x3039;  return (seed >> 16) & 0x7fff   -- BIOS rand = RNG2
```

See [Turn_Order.md](./Turn_Order.md#does-it-use-rng-or-rng2) for why this is
RNG2. The engine is a set of coroutines that run one state per tick (each
writes its next handler into `(&DAT_8017da90)[slot]`). A function returning
"not done" (`0` or `-1`, depending on the function) just runs again on the
next tick. Every "retry next tick" below means that.

## Overview

```
loop:
    ROUND_INPUT()     -- Fight / Run / Bribe / Free Will menu + per-character commands
    ROUND_START()
    TURN_LOOP()       -- until the turn roll finds nobody eligible
    ROUND_END()
    (victory/defeat check: not traced)
```

## 1. Round input

- The party's `ActionType` / `AbilitySlot` / `TargetIdx` (`+0x47..+0x49`)
  come from the menu. See
  [Scripted_Battle_Actions.md](./Scripted_Battle_Actions.md) for how those
  fields get populated, and why writing them alone isn't enough without also
  driving the menu's final confirm.
- Choosing **Free Will** sets `g_FreeWillGate` (`0x8017be44`) to 10 — its
  only writer. Nothing ever resets it, so it's probably 0 until Free Will is
  first used.
- **Run** calls `check_flee` (★, formula not covered here).

## 2. Round start: `battle_refresh_combatant_derived_stats`

```
for idx in 1..total:                              -- loop at 0x800f6df4, no RNG
    ActionTag = (invalid(idx) or status bit 0x20 Sleep) ? 1 : 0
    -- invalid = check_combatant_valid_target fails: +0x45 set, or HP - pending dmg < 0
recompute party derived stats (ATK/DEF garbage for ~5 frames after confirm)
for each valid enemy with status bit 0x20 (Sleep):
    ★ r; if r*100/0x7fff < 50: wake (clear bit, ActionTag = 0)
RoundNumber += 1
★ r % 3  -> intro camera/animation choice        -- unconditional, every round
for each living party member:                     -- no RNG
    heal = 5 per regen source (certain items, Sunbeam) + 5 per Water Rune Piece
    if Poison: heal -= HPMax / 20
    apply(-heal) if heal != 0
gate = 30                                          -- ROLL_GATE_COUNTDOWN
```

See
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md#status-effects-combatant_rec0x4a-apply_status_effect-0x800e04dc)
for the status roster and Poison's tick.

## 3. Turn selection: `battle_advance_turn`, every tick

```
gate -= 1
if gate > 0: return                                -- no RNG while waiting
best = 0                                           -- 0 = none yet, -1 = none yet but someone busy
for idx in 1..totalCombatants:                     -- party AND enemies
    if ActionTag != 0: skip
    if busy(enemy_data+5): if best == 0: best = -1; skip    -- skipped for free
    ★ r; w = SPD(+0x2a)*10 - 5 + r % 10
    if best < 1: best = idx, bestW = w             -- first candidate: no validity check here,
                                                   -- but dead/invalid ones already have
                                                   -- ActionTag = 1 (see ROUND_START)
    elif bestW < w and valid(idx): best = idx      -- strict: ties keep the lower index
                                                   -- valid: +0x45 == 0 and HP - pending dmg >= 0
pending = best
if pending == -1: return                           -- nobody eligible yet but someone busy:
                                                   -- gate stays <= 0, roll again next tick
scripted-battle hook (+0x1330/+0x1334) may force an immediate reroll
if Spark flag (+0x48): pending = first party member with ActionTag == 0
                       and not busy (the rolls above were still consumed);
                       if none, clear the flag
if pending == 0: go to ROUND_END
next tick: currentActor = pending, then DISPATCH runs every tick
```

The gate (`ROLL_GATE_COUNTDOWN`, `BattleState+0x1264`) is a signed int,
decremented *before* the check:

- **Set to N (N ≥ 1):** the roll happens on the Nth tick after that.
- **Set to 0, or already ≤ 0:** the roll happens on the very next tick.

The countdown itself never consumes RNG, but busy status at the tick it
expires decides the roll's call count, so the gate value set by the previous
action matters (see the dispatch tables below). Full state machine in
[Turn_Order.md](./Turn_Order.md#the-roll-gate-countdown-and-the-pendingcurrent-copy).

The Spark flag (`SyncSignals+0x18`, i.e. `BattleState+0x48`) is armed by
`battle_execute_enemy_attack` when the attacker's `Rune.Id == 17` (Spark),
and consumed by `FUN_800f8578`.

The scripted-turn hook is used by
[Queen Ant round 3](./Battle_Damage_Formula.md#queen-ants-round-3-battle-end-and-ant-respawn-mechanic)
and the
[Ted-vs-Queen-Ant forced cast](./Battle_Damage_Formula.md#the-scripted-ted-vs-queen-ant-forced-hell-cast-fight).

## 4. Dispatch: `battle_dispatch_current_actor_action`

Full branch logic in
[Turn_Order.md](./Turn_Order.md#how-a-turn-actually-starts-battle_dispatch_current_actor_action).

### Enemy actor

```
if status bit 0x20 (Sleep): ActionTag = 1; reroll next tick
r = attack_data_table[Id]+0x30 AI(state)           -- runs again every tick
```

A typical AI's target pass (see the
[target-selection template](./Battle_Damage_Formula.md#target-selection-template-used-by-most-monsters)):

```
for each party idx: if alive and +0x44 < 4 and not busy:
    ★ r; if r % 100 > 50: target = idx; break
no target -> return 0, retry next tick: fresh scan, eligibility re-checked
no living front-row member at all -> ActionTag = 1 (turn skipped)
```

Then the move choice, per monster: ★ `r*100/0x7fff < threshold`, e.g. Zombie
Dragon's Attack threshold is `0x47`. Per-monster AIs are in
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md#aienemy-move-selection).

| AI returns | Result | Gate |
|---|---|---|
| `-1` | ENEMY_BASIC_ATTACK | `g_FreeWillGate` |
| `0` | retry next tick (reroll if ActionTag == 1) | unchanged |
| other | done; `+0xc` continuation runs if set | overlay's own value |

"Unchanged" means the gate is still ≤ 0 from the last roll, so the next roll
comes on the very next tick. A raw scan of every overlay found 51 stores to
`+0x1264`, with values 0/1/5/20/30/60/90 (mostly 30); Queen Ant (`va7.bin`)
and `vf2.bin` also decrement it. Zombie Dragon (`vb5g.bin`) never writes it.

### Party actor, by `ActionType`

| Type | Resolver | Gate |
|---|---|---|
| 0 Attack | PARTY_BASIC_ATTACK | `g_FreeWillGate` |
| 1 Defend, or invalid | `ActionTag = 1` | 0 |
| 2 Rune | per-spell cast state machine | unchanged |
| 3 Item | item resolver | unchanged |
| 4 Unite | unite resolver | unchanged |

- **Rune** (`battle_select_special_ability`): resolves a spell id (elemental
  ladder or the
  [unique-rune table](./Battle_Damage_Formula.md#the-unique-rune-ability-table-dat_8016a630),
  with a
  [Magic Unite check](./Battle_Damage_Formula.md#magic-unite-spells-battle_check_magic_unite-0x800f5398)
  on Lv4 spells), then runs that spell's
  [cast state machine](./Battle_Damage_Formula.md#how-spells-call-rng-the-cast-state-machine),
  which owns all of its ★ calls.
- **Item** (`battle_try_special_attack`): waits (no RNG) until every
  combatant is idle, then resolves the inventory slot and decrements its
  use count. No `rand()` calls. The next roll comes 20 frames after it
  resolves, while the target is busy, so the target is always skipped
  on that roll. See [Item turns](./Turn_Order.md#item-turns).
- **Unite** (`battle_select_unite_attack`): physical pairing table, or the
  Magic Unite path above.

## 5. Basic attack resolution

### PARTY_BASIC_ATTACK: `battle_execute_enemy_attack`

```
if target no longer valid: retarget to the first valid enemy (no RNG)
                            -- combatant order, no range/row check
if target busy, out, or HP - pending <= 0: wait, retry next tick (no RNG)
if Rune 14 (Double-Beat): toggle +0x4a bit 0x4000   -- attack repeats on the next target
if Rune 17 (Spark): set the Spark flag (+0x48)
if target species bit 15 (Neclord) or not ★HIT:   -- bit 15 skips the roll: no rand()
    target species bit 1 and attacker range != LONG
                                     -> the monster counters:
                                        ★ calc_damage on the attacker, later
    elif target species bit 2        -> plain miss, done
    else                             -> the failed roll is ignored: treated as a hit
★ CRIT
at the animation's damage frame (attacker enemy_data+0x40 & 0x2): ★ calc_damage, ×3 if crit
```

`range` is the weapon record's `+0x56` byte (1 short, 2 long, 3 medium), read
through `ClassPtrs[idx]+0x04`. So long-range characters can't be countered
(the script-based `counterEligible` flag is redundant with this), and
against a monster
with bit 1 but not bit 2 they can't miss either. See
[dodge and counter](./Battle_Damage_Formula.md#on-a-miss-or-a-hit-dodge-and-counter)
and [multi-target attacks](./Battle_Damage_Formula.md#multi-target-attacks-battle_enemy_attack_advance_multitarget).

### ENEMY_BASIC_ATTACK: `battle_execute_player_attack`

```
if target busy: return 0                           -- wait, retry next tick, no RNG
if not ★HIT:
    dodge/counter: needs attacker idx > partyCount+1 (so never the first enemy),
                   attacker species bit 0, and defender range != LONG
                   (the range byte's bit 0)
        Defending or Counter Rune (16) -> success, no RNG
        otherwise                      -> ★ r & 1
    success -> the party member counters: ★ calc_damage later
    elif attacker species bit 3 clear -> plain miss, done
    else -> the failed roll is ignored: treated as a hit
cover check, no RNG: target HP < floor(HPMax / 4) and a story pair
                     (e.g. Hero -> Gremio), or target has Phero Rune (26)
                     -> the next valid, non-busy opposite-gender ally
NO crit roll
at the damage frame: ★ calc_damage against the target or the cover ally
```

See the
[cover mechanic](./Battle_Damage_Formula.md#cover-mechanic-battle_check_counter_attack-find_cover_target).

### Animation timing: when damage lands and when busy clears

Nothing stores "how long an attack takes". Each combatant's animation scripts
decide it, and `scripts/AttackTimingWalker.py` computes the numbers statically
into `outputs/AttackTimings.json`. Frame 0 is the tick the attack executor
starts the attack script, right after the hit and crit rolls:

```
frame 0        attack script starts (attacker table slot 1)
               it sets attacker busy |= 1 and target busy |= 8
frame I        attacker's script sets its own +0x40 |= 0x2          -- IMPACT
frame I+1      damage function sees it: ★ calc_damage, sets attacker +0x40 |= 0x10,
               starts the reaction on the target: ATTACKER's table slot 2
               (slot 8 on a crit; party Rune_Piece_Type 1/4 -> main.exe
               0x8016c56c / 0x8016c648), run with the TARGET's own sprite sheet
frame I+1+R    reaction clears target busy bit 8 -> eligible again
frame E        attacker's script sets its own +0x40 |= 0x4
frame E+1      battle_enemy_attack_multitarget_continue: next multi-target hit, or
               the attacker's slot 4 return script
frame E+1+S    slot 4 clears attacker busy bits 1 and 8
```

The next turn roll doesn't wait for any of this: the gate starts counting
as soon as the executor returns. So these frames decide who is still busy
(skipped by the roll) when the gate expires. Both basic attacks also stall
while their target is busy; a party Attack also waits while its target's
pending damage is lethal but it isn't out yet (`check_combatant_alive`).

Frame rules, from the interpreter (`play_attack_animation`, runner
`FUN_800e358c`) and sprite player (`FUN_800e2044` / `FUN_800e2a9c`):

- **Order within a frame:** the turn coroutine runs first, then
  `FUN_800e09bc` walks party, enemies and sub-actors; for each it steps the
  sprite animation, then the script.
- **Script costs:** "play sequence + wait" (ops 4, 5) costs the sum of that
  sequence's frame durations. A delay (op 3) costs N frames, a move timer
  (ops 22/23/33/37 + op 21) N frames, and op 30 one frame. Everything else
  is instant.
- **RNG:** opcode 40 (`anim_op_roll_status_effect_chance`) is a `rand()`
  call made from inside an animation script, on animation timing.

- **Sub-actors:** a projectile or effect spawned mid-script takes a later
  slot, so it gets its first anim update and script tick in the same frame
  it was spawned.

Validated live:
- Whip Master's command script: busy at frame 48, bit `0x2` at 68,
  dependent code at 69. The walker gives 0 / 20 / 21.
- The Zombie Dragon fight (`ZombieDragonT2Start.State`, 4 seeds, round 2):
  every hit matched exactly on impact, damage roll, `0x4`, attacker-free
  and target reaction. That covers six party members (`vic` Viktor, `gre`
  Gremio, `shu` the Hero, `cre` Cleo, `kam` Camille, `tai` Tai Ho)
  attacking Zombie Dragon, including Cleo's projectile, and Zombie Dragon
  attacking two different party members. Tools: `scripts/VerifyAttackTimings.lua` and
  `scripts/AttackTimingCompare.py`.

Coverage (basic Attack, slot 1): the damage frame resolves for 120 of 124
enemies and all 78 party files, and every party↔enemy reaction pair
resolves. Party files are `data/04_play/<code>.bin` with file-relative
pointers (header `+0x20` = script table, `+0x24` = sprite resource); the
shared effect sheet is `data/00_init/battle.bin`, loaded at `0x800aa000`.

Many attacks hand timing to a **native per-frame handler** (opcode 35,
`EnemyData.pVfxEffectHandler`), called after the script and move step each
frame. Opcode 30 sets a phase, opcode 31 waits for the handler to advance
it. All the ones basic Attacks use are modelled in the walker, most as fixed
frame counts (projectile, flight curve, hop, vine, fixed-length loops).
What matters for RNG:

- **Handler-applied damage:** Neclord, Banshee and Crystal Core apply damage
  from the handler itself (`calc_rune_element_attack_damage` via callback
  `+0x158`, or `calc_damage` via `+0xc`), not through the impact bit.
  Crystal Core's timing assumes its controller's spin speed starts at its
  steady value of 48.
- **Handler `rand()` calls on animation time:** Slot man (one outcome roll,
  then at least one reroll per frame for 60 frames), Nightmare (a
  sub-attack pick plus 4 rerolls; one sub-attack also respawns particles
  with `rand()`), and Dragon (its documented Lightning / Fire Breath roll).
- **Not timed:** Slot man and Nightmare (per-outcome effects; Nightmare
  also waits on an async load of unknown length), Strong Arm (throws an
  ally and runs that ally's scripts) and Dragon (see its own section).

### Miss, counter, cover and death timing

Every outcome after the executor is a chain of `combatant_rec+0x50`
callbacks (step 2 of each tick), each waiting for a flag bit in some
combatant's `EnemyData+0x40` that the animation scripts set (0x1
dodge/counter point, 0x2 impact, 0x4 done):

```
hit      atk 0x2 -> ★ calc_damage, target runs atk slot 2 (crit: x3, slot 8)
miss     atk 0x1 -> target runs its own slot 3 (dodge)
counter  atk 0x1 -> retaliator runs own slot 3
         retaliator 0x2 -> clear its fx, it runs own slot 5 (counter strike)
         retaliator 0x2 -> ★ calc_damage on atk, atk runs retaliator slot 2
cover    (dispatch: ally 0x8016c270, target 0x8016c29c)
         atk 0x2 -> ★ calc_damage on ally, ally runs atk slot 2
then     atk 0x4 -> atk runs own slot 4 (recover, clears its busy)
```

- A miss leaves the attacker's timeline unchanged; only the target's busy
  window differs. A counter adds ~50 attacker busy frames and a mid-turn
  damage roll.
- **Index order:** callbacks and the actor pass both walk party, enemies,
  then sub-actors. A party member dodging an enemy's miss sees the enemy's
  0x4 a frame later than attacker-first order would.
- **Flags persist** between actions (only the combatant's own executor and
  the counter steps clear them), so a combatant that dodged earlier skips
  the first wait of its next counter.
- **Death** (actor pass, after the combatant's own update, when HP < 1 and
  not busy, so after the hit reaction): an enemy plays its own slot 7 and
  its death-fade handler keeps it busy (~93 frames for a Soldier Ant); a
  party member dies with no busy time at all.
- **Sacrificial Buddha** (item 83 in the dying member's own inventory,
  battle phase `battle_state+0x3428 == 4`): the item is removed and a revive
  script runs instead of death. HP heals to `floor(HPMax / 2)` at +113 from
  the reaction's end, busy clears at +123, and the member keeps their
  ActionTag, so they still act that round if they hadn't yet.

All of this is simulated by `walk_path()` in `scripts/AttackTimingWalker.py`
and matched a live capture frame for frame (200 attacks, 6 revives). Full
tables in [TickBasedAlgorithm.md](../../TickBasedAlgorithm.md) ("Miss,
counter, cover and death timing") and
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md#continuation-chains-and-death).

## 6. Formulas

```
HIT:   c = clamp(atk.SKL - (tgt.SKL - 80), 60, 99)
       halve if: party attacker has Bucket status, or enemy attacks a Hazy (18) wearer
       ★ r % 100 < c

CRIT:  c = clamp((SKL + LUK) / 8, 3, 25);  ×2 with Killer (15), party only
       ★ r % 100 < c

calc_damage:   b = ATK - DEF
               ★ b < 10 ? (b + 1) - r % 4 : b + (b/2 - r % b) / 5     -- C truncation
               party target Defending: b /= 2
               party attacker, weapon/Rune-Piece element is the target's weakness: b += b/2
               Rune Piece Fire(1)/Earth(3): b += (b/20) * pieces
               max(b, 1)

spell (apply_elemental_multiplier):             -- no RNG
               t = power + MGC/2;  weak ×2 / resist ÷2 / immune 0;  Dark (7) ignores it

enemy elemental (calc_rune_element_attack_damage):
               b = atkMGC - tgtMGC;  same ★ variance step
               halve if target's rune category == element, or category 7 (Soul Eater)
               unlisted rune: category = caller's $s1 (the slot bug)
               max(b, 1)   -- doc and Lua disagree on floor-vs-halve order
```

Derivations:
[`calc_hit_chance`](./Battle_Damage_Formula.md#calc_hit_chance-0x800f7d5c),
[`check_critical_hit`](./Battle_Damage_Formula.md#check_critical_hit-0x800f835c),
[`calc_damage`](./Battle_Damage_Formula.md#calc_damage-physical-attack-formula-0x800f7e90),
[`apply_elemental_multiplier`](./Battle_Damage_Formula.md#apply_elemental_multiplier-0x80125b28),
[`calc_rune_element_attack_damage`](./Battle_Damage_Formula.md#enemy-elemental-attacks-calc_rune_element_attack_damage-0x800f8174).

## 7. Round end

```
gate = 30; count down; at <= 0, keep waiting while ANY combatant is busy
battle_process_round_end_status_and_formation:
    party status decay: ids 3, 7 and 8 only
    party front-row backfill (no restrictions)
    enemy front-row backfill (footprint rules; stops at the first candidate)
battle_bribe_check_and_apply, then the next round's input
```

The wait state is `0x800f43e0`, entered from `battle_advance_turn`'s
"nobody eligible" branch. Formation slots never change mid-round when
someone dies, on either side; both backfills land on the same frame, 3
frames after the last actor finishes (live-confirmed 2026-09-25,
`scripts/VerifyFormationBackfill.lua`). Enemies only seem to move up
mid-round because a party Attack whose target died retargets to the first
valid enemy with no range check, back row included. Backfill rules, including the Neclord's Castle
worked example, are in
[formation management](./Battle_Damage_Formula.md#formation-management-front-row-auto-backfill).

**Not yet traced**: how victory/defeat is detected and the battle loop ends.
`SyncSignals+4` is confirmed to trigger a general round-state resync (Queen
Ant's round-3 trigger and the Ted-vs-Queen-Ant forced cast both set it), but
the win/loss check past that point isn't pinned down — so
`lib/BattleRoundInput.lua`'s `Outcome` field is best-effort, not yet
live-validated.

## Not yet confirmed

- **Rolls between hit and damage:** the damage roll happens `I+1` frames
  after the hit and crit rolls (see Animation timing). One known consumer
  can land in that window: animation opcode 40, the status-effect roll. No
  basic Attack script in the static scan uses it (Rabbit Bird's does, at
  frame 95, after its impact).
- **Spark flag:** read from the decompile only. Rune 17 = Spark comes from
  Suikoden-RNG-lib's `lib/Game/Magic/Runes.js`.
- **Enemies never crit on basic attacks:** from the decompile only.
- **Party deaths without a Buddha:** decompile only. Custom (non-shared)
  death handlers aren't modelled.
- **Round end:** victory/defeat detection, and the exact order after the
  wait state, aren't traced.

## Terminology cross-reference

For implementers going directly from this doc to code, this page's terms map
onto `lib/BattleSnapshot.lua`'s `InitialState` and `lib/BattleRoundInput.lua`'s
`TurnResult` as follows:

This doc / RE docs → `BattleSnapshot`/`TurnResult` field:

- `BattleState+0x4`, round counter → `RoundNumber`
- `Address.RNG`, the 32-bit LCG state → `RNGSeed` (snapshot) /
  `RNGSeedBefore`+`RNGSeedAfter` (result)
- `combatant_rec+0x26`/`+0x2a`/`+0x2c`/`+0x2e` → `SKL`/`SPD`/`MGC`/`LUK`
- `combatant_rec+0x30`/`+0x32` (party — recomputed at round start) or
  `+0x14`/`+0x18` (enemy) → `ATK`/`DEF`
- `combatant_rec+0x10`/`+0x12` → `HPMax`/`HPCurrent` (snapshot) or
  `HPBefore`/`HPAfter`/`HPMax` (result)
- `enemy_data[i]+0x0` → `Id`
- `enemy_data[i]+0x5` → `Busy`
- persistent Stats `+0x4c` → `RuneId`
- `combatant_rec+0x47` → `ActionType`
