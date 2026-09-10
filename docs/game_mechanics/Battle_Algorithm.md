# Battle Algorithm

The master per-round loop, assembled from [Turn_Order.md](./Turn_Order.md),
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md), and
[Scripted_Battle_Actions.md](./Scripted_Battle_Actions.md) into one ordered
walkthrough. This is the algorithm a pure-code battle simulator needs to
implement: it consumes a `BattleSnapshot`-shaped initial state
(`lib/BattleSnapshot.lua`) and produces a `TurnResult`-shaped outcome
(`lib/BattleRoundInput.lua:runTurn()`) without touching the emulator. Each
step below is a short pseudocode skeleton linking to the page with the actual
formula — this page is the glue, not a restatement.

## Overview

```
while battle not over:
  actor = SELECT_NEXT_ACTOR()                 -- 1. Turn selection
  if actor == nil:
    wait ~30 ticks; retry                     -- nobody eligible this pass
    continue
  DISPATCH_AND_RESOLVE(actor)                 -- 2. Action determination + resolution
  actor.ActionTag = 1
  if every combatant's ActionTag == 1:
    ROUND_END()                               -- 3. Round-end processing
    RoundNumber += 1
    reset every ActionTag = 0
    ROLL_GATE_COUNTDOWN = 30
```

## 1. Turn selection

```
weight(combatant) = combatant.SPD * 10 - 5 + rand()%10        -- rand() is RNG2
candidates = every combatant with ActionTag==0 and not busy
if candidates is empty: return nil                            -- round complete
return candidate with highest weight(...)                     -- one rand() call per candidate
```

Gated by a per-tick roll-gate countdown (`ROLL_GATE_COUNTDOWN`,
`BattleState+0x1264`) so this roll fires once per transition, not every tick;
see
[Turn_Order.md](./Turn_Order.md#turn-order-weight-formula)
for the formula and
[the roll-gate countdown section](./Turn_Order.md#the-roll-gate-countdown-and-the-pendingcurrent-copy)
for the full state machine, including what resets the countdown and the
"someone still needs to act" bypass that skips the roll entirely when a
non-busy party member with `ActionTag==0` exists.

A scripted-turn-override hook (`BattleState+0x1330`/`+0x1334`) can intercept
here and either force an immediate reroll or (via its own 3-stage chain) force
a specific actor's pre-set action directly, bypassing this roll entirely —
see the
[Queen Ant round-3](./Battle_Damage_Formula.md#queen-ants-round-3-battle-end-and-ant-respawn-mechanic)
and
[Ted-vs-Queen-Ant](./Battle_Damage_Formula.md#the-scripted-ted-vs-queen-ant-forced-hell-cast-fight)
encounters for the two confirmed uses of this hook.

## 2. Action determination and resolution

Once an actor is current, `battle_dispatch_current_actor_action` branches on
party vs. enemy — see
[Turn_Order.md](./Turn_Order.md#how-a-turn-actually-starts-battle_dispatch_current_actor_action)
for the full dispatch logic. The two branches are structured differently:
enemies select *and* resolve their move inside one polled AI call; party
members have their fields pre-populated by a menu UI, and dispatch just reads
and routes them.

**Enemy** (`actor.Idx > PARTY_COUNT`):

```
if actor.StatusFlags & 0x20 ("Sleep"):                  -- can't-act gate
  ActionTag = 1; return                                  -- resolves as "did nothing"
result = poll attack_data_table[actor.Id].AiFunction(actor)   -- called every tick
if result == 0:  return                                       -- still deciding, retry next tick
if result == -1: battle_execute_enemy_attack(actor)            -- generic plain-Attack fallback
                                                                -- (else: the AI already resolved
                                                                -- its own move+damage internally)
```

The AI function itself both picks the move and, for anything beyond a plain
Attack, calls its own damage/effect code directly (it does not necessarily
go back through the party-side `ActionType` dispatch below) — see
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md#aienemy-move-selection)'s
target-selection template and per-boss move tables for what each AI function
actually does.

**Party member** (`actor.Idx <= PARTY_COUNT`): reads `ActionType`
(`combatant_rec+0x47`) directly — no separate "ready" flag exists — and
dispatches straight into the resolver below. This never fires until the
round's Fight/Run/Bribe/Free Will prompt and the actor's own command/target
menu have already been confirmed; see
[Scripted_Battle_Actions.md](./Scripted_Battle_Actions.md) for how those
fields actually get populated (by the menu UI, or by direct field writes for
simulation purposes) and why writing them alone isn't sufficient without also
driving that menu confirm.

## 3. The resolution pipeline

Shared by both party and enemy attacks once `ActionType`/`AbilitySlot`/
`TargetIdx` (`combatant_rec+0x46..0x49`) are set — see
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md#action-selection-combatant_rec0x460x49)
for the field layout:

| `ActionType` | Resolver | Pipeline |
|---|---|---|
| `0` Attack | `battle_execute_enemy_attack` (shared by both sides despite the name) | [cover-mechanic check](./Battle_Damage_Formula.md#cover-mechanic-battle_check_counter_attack-find_cover_target) → [`calc_hit_chance`](./Battle_Damage_Formula.md#calc_hit_chance-0x800f7d5c) → [`calc_damage`](./Battle_Damage_Formula.md#calc_damage-physical-attack-formula-0x800f7e90) (physical) or [`calc_rune_element_attack_damage`](./Battle_Damage_Formula.md#enemy-elemental-attacks-calc_rune_element_attack_damage-0x800f8174) (enemy elemental attacks) → HP delta applied |
| `1` Defend (or unset/invalid) | `battle_resolve_defend_action` | sets `ActionTag=1`, forces an immediate reroll, halves the next incoming physical hit this round |
| `2` Rune | `battle_select_special_ability` | resolves a spell id (elemental ladder or the [unique-rune table](./Battle_Damage_Formula.md#the-unique-rune-ability-table-dat_8016a630), with a [Magic Unite](./Battle_Damage_Formula.md#magic-unite-spells-battle_check_magic_unite-0x800f5398) pairing check on Lv4 spells) → per-spell [cast state machine](./Battle_Damage_Formula.md#how-spells-call-rng-the-cast-state-machine) → [`apply_elemental_multiplier`](./Battle_Damage_Formula.md#apply_elemental_multiplier-0x80125b28) |
| `3` Item | `battle_try_special_attack` | resolves the inventory slot, decrements its use-count |
| `4` Unite | `battle_select_unite_attack` (physical pairing table) or the Magic Unite path above | — |
| (any) multi-target continuation | `battle_enemy_attack_advance_multitarget`/`_continue` | repeats the Attack resolver against the next target while [Double-Beat Rune](./Battle_Damage_Formula.md#passive-rune-effects-runeid-persistent-stats-0x4c)'s bit is set |

## 4. Round-end processing

Once every combatant's `ActionTag == 1`, `battle_process_round_end_status_and_formation` runs before the round counter increments:

```
for each afflicted combatant:
  decay/tick status effects (Poison damage, Balloon escalation, duration countdowns, clears)
for each side:
  backfill empty front-row slots from the back row, respecting formation-slot footprint
check SyncSignals+4 -> triggers a larger reset/wrap-up sequence
```

See
[Battle_Damage_Formula.md](./Battle_Damage_Formula.md#status-effects-combatant_rec0x4a-apply_status_effect-0x800e04dc)
for the full status-effect roster and per-id mechanics (Poison's exact
`floor(HPMax/20)`-per-round tick in particular), and its
[formation management](./Battle_Damage_Formula.md#formation-management-front-row-auto-backfill)
section for the backfill rule.

**Not yet traced**: exactly how `SyncSignals+4` leads to detecting
victory/defeat and ending the battle loop. It's confirmed to trigger a general
round-state resync (the same signal Queen Ant's round-3 trigger and the
Ted-vs-Queen-Ant forced cast both set), but the actual win/loss check past
that point isn't pinned down — `lib/BattleRoundInput.lua`'s own `Outcome`
field is correspondingly documented as best-effort, not yet live-validated.

## Terminology cross-reference

For implementers going directly from this doc to code, this page's terms map
onto `lib/BattleSnapshot.lua`'s `InitialState` and `lib/BattleRoundInput.lua`'s
`TurnResult` as follows:

| This doc / RE docs | `BattleSnapshot`/`TurnResult` field |
|---|---|
| `BattleState+0x4`, round counter | `RoundNumber` |
| `Address.RNG`, the 32-bit LCG state | `RNGSeed` (snapshot) / `RNGSeedBefore`+`RNGSeedAfter` (result) |
| `combatant_rec+0x26`/`+0x2a`/`+0x2c`/`+0x2e` | `SKL`/`SPD`/`MGC`/`LUK` |
| `combatant_rec+0x30`/`+0x32` (party — recomputed at round start) or `+0x14`/`+0x18` (enemy) | `ATK`/`DEF` |
| `combatant_rec+0x10`/`+0x12` | `HPMax`/`HPCurrent` (snapshot) or `HPBefore`/`HPAfter`/`HPMax` (result) |
| `enemy_data[i]+0x0` | `Id` |
| `enemy_data[i]+0x5` | `Busy` |
| persistent Stats `+0x4c` | `RuneId` |
| `combatant_rec+0x47` | `ActionType` |
