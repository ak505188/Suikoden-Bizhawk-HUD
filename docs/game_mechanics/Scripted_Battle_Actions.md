# Scripted Battle Actions (No Controller Input)

Covers what it takes to drive a full battle round from a Lua script — choosing every party
member's action and having it actually execute — without any real controller input, for
simulation purposes. Complements
[Turn_Order.md](./Turn_Order.md#how-a-turn-actually-starts-battle_dispatch_current_actor_action),
which covers what happens *after* a round's commands are already locked in; this page covers
the part before that: the round-start command-selection UI itself.

## The round-start menu flow

A party member's queued action executes the instant `combatant_rec+0x47` (`ActionType`) holds
a valid value once it's their turn — no separate "confirmed" flag (see Turn_Order.md). Getting
an action into that field in the first place goes through a **separate, real input-driven menu
system**:

1. **Fight / Run / Bribe / Free Will** — the round-start prompt. Fight leads into per-character
   command selection (below). Free Will has the AI pick every command automatically — see
   [Battle_Damage_Formula.md](./Battle_Damage_Formula.md#free-will-automatic-action-selection)
   for exactly how it assigns each character's target. Run and
   Bribe set every living party member's `ActionType` to `1` (Defend) immediately and
   unconditionally, before anything else — `LAB_800ee124` (Run) and `LAB_800ee38c` (Bribe),
   neither yet a Ghidra-bounded function. Run then calls the escape-roll resolver
   (`FUN_800f8464`) and shows a success/fail message (strings at `0x8016bcd8`/`0x8016bcf8`);
   Bribe runs the identical Defend-everyone loop before its own gold-cost/roll logic.
2. **Per party member, in formation order** (not turn/speed order): a command menu (Attack /
   Defend / Rune / Item / Unite — the same 5 values as `ActionType`), then a target select.
   Confirming the target **immediately writes** `ActionType`/`TargetIdx` for that combatant and
   advances to the next party member — there is no per-character "Ok?" step.
3. **One final "Ok?" confirm** after all party members have a command queued (whether picked
   manually via Fight, or auto-picked via Free Will) — *this* is what actually starts the round.

Pre-writing `ActionType`/`AbilitySlot`/`TargetIdx` (and the `+0x46` `ActionTag` flag) directly
into `combatant_rec` before this whole UI flow runs does nothing — the round-start menu is
driven by real (or simulated) button-press edges, not by polling combatant state.

## The menu functions and their shared context struct

Two Ghidra-decompiled functions drive the round-start menu:
**`battle_menu_fight_run_bribe_freewill`** (`0x800ea2a8`, the Fight/Run/Bribe/Free Will prompt)
and **`battle_menu_select_command`** (`0x800ea934`, each party member's own
Attack/Defend/Rune/Item/Unite menu), which schedules **`battle_menu_select_target`**
(`0x800eb628`) for Attack specifically. `DAT_8017da90`'s coroutine slot 3 (absolute address
`0x17da9c`) holds the address of whichever of these is currently active — a third coroutine
slot, entirely separate from `battle_advance_turn`/`battle_dispatch_current_actor_action`'s own
slot.

Both menu functions share a **separate persistent context struct, `DAT_80179fe8`** (not the
battle-state `DAT_8017be3c`):

- `+0x4`: a phase counter, meaning defined per-function (see "Detecting when the round-start
  prompt is ready" below).
- `+0x8`: a reused "highlighted option" scratch field — Fight-menu: `0`=Fight/`1`=Run/`2`=Bribe/
  `3`=Free Will; command-menu: `0`-`4` matching `ActionType`'s own values.
- `+0x20` (via a generic UI-widget object pointer): a flags word, bit `0` = confirmed, bit `1` =
  initialized.

`battle_menu_select_command` is where `ActionType` actually gets written —
`combatant_rec(current_actor)+0x47 = <highlighted command>` — in its own confirm branch, then it
dispatches by that same value. Every command's own confirm step (Rune/Item/Unite included)
funnels through one shared convergence point, `LAB_800ea510` — `ActionType` is written exactly
once, in `battle_menu_select_command`'s shared pre-switch code, and nothing downstream ever
touches it again, so all 5 `ActionType`s (Attack/Defend/Rune/Item/Unite) survive identically
through to the final round confirm.

**Cursor movement and confirm are read from two small global flag words, not the widget's own
state**: `DAT_8017be4c` (`&0x41` = confirm, `&0x24` = cancel) and `DAT_8017c000` (`&0x5000
==0x1000`/`0x4000` = Up/Down). These aren't settable latches — see "Why a pure memory-only
bypass doesn't work" below.

## Target selection: `battle_menu_select_target`

`battle_menu_select_target` (`0x800eb628`): cursor Left/Right walks a precomputed valid-target
list (`DAT_80179fe8+0x38`); Cancel returns to `battle_menu_select_command`; Confirm checks
reachability via the attacker's weapon-type byte (`PersistentStats.bWeaponType`) indexing
`DAT_80165890[type]+0x56` (a "range class" byte — `2` = ranged/any target, else front-row-only
with a melee-vs-formation check), writes `TargetIdx`, and hands off to the shared convergence
point `LAB_800ea510`.

The other three commands each have their own continuation after `battle_menu_select_command`:
**Defend** (`LAB_800eba48`) is a trivial 2-phase wait with no targeting (`ActionType` was
already set earlier); **Item** (`LAB_800ebb0c`) and **Unite** (`LAB_800ed560`) are 2-phase setup
stages handing off to larger state machines (`0x800ebc08` Item, `0x800ed668` Unite) that
structurally mirror Attack's own target-select.

## Why a pure memory-only bypass doesn't work

Writing `DAT_8017be4c`/`DAT_8017c000` (or the widget's own confirm bit) directly, with no real
`joypad`/`Buttons` call, does not advance the menu: both fields are **recomputed from genuine
pad state by input-decoding code that runs earlier in the same frame**, before
`battle_menu_select_command`/`battle_menu_fight_run_bribe_freewill` ever read them. A Lua write
issued via `emu.frameadvance()` either lands *before* that frame's real input-decode runs (and
gets immediately overwritten, since no real button was ever held via `joypad.set()`) or *after*
the whole frame — including the menu's own read — has already completed.

`joypad.set()`-based simulated presses (this project's `lib.Buttons`) are therefore the correct
injection layer: the raw controller state read *before* any game logic runs each frame is the
one place a write actually sticks, which is exactly "no human touching a controller, fully
scripted," even though the bytes involved are the same ones a real press would set.

## Driving a round from a script: the 2-tap recipe

The round-start prompt's own "which option" field (`DAT_80179fe8+8`) can be written directly —
no cursor navigation needed — but only once its owning function
(`battle_menu_fight_run_bribe_freewill`) is stably in phase `2` (see next section). That
function unconditionally resets this field to `0` during its own one-tick phase `1→2`
transition, so a write timed during that transient gets silently clobbered; once phase is
stably `2`, a write sticks through the confirm that follows.

Overriding a command *after* it's been chosen (by the AI or otherwise), but *before* the final
confirm, also sticks: the confirm step reads `combatant_rec` fresh — it does not cache
selections elsewhere and reapply them — so it doesn't matter *how* an action got set (real
navigation, Free Will's AI, or a direct write), only what's there at confirm time.

Combined, driving a full round collapses to 2 taps regardless of party size:

1. Poll for the round-start prompt to be ready (next section).
2. Write `DAT_80179fe8+8 = 3` (Free Will) directly.
3. Tap Cross once — the AI populates every living party member's `ActionType`/`AbilitySlot`/
   `TargetIdx`.
4. Overwrite whichever party members' `combatant_rec+0x47/0x48/0x49`
   (`ActionType`/`AbilitySlot`/`TargetIdx`) should be controlled directly — the same fields
   `modules/RNG/submodules/Combat/ActionEditMenu.lua` edits live in the HUD. Anyone left alone
   keeps the AI's own pick (mixed manual/AI control is a supported use case, not just a
   stepping stone).
5. Tap Cross once more — the round starts, executing every combatant's (possibly overridden)
   action in turn order, as traced in `battle_dispatch_current_actor_action`.

Implemented as `lib/BattleRoundInput.lua` (`chooseRoundOption(choice)`,
`setAction(idx, actionType, abilitySlot, target)` / `setActions(list)`, `confirmRound()`), with
a working example in `scripts/SimulateZombieDragonRound.lua`.

The original manual-navigation recipe (Fight → per-character Attack+target selection for each
party member → Ok) also still works, and is the one path that exercises the real per-character
command/target menus directly — useful if that's specifically what's needed — but Free Will
plus targeted overrides is the preferred approach for scripted simulation.

## Detecting when the round-start prompt is ready

Poll for **`DAT_8017da90` slot 3 (`0x17da9c`) equal to `battle_menu_fight_run_bribe_freewill`'s
address (`0x800ea2a8`) AND that function's own phase (`DAT_80179fe8+0x4`) equal to `2`**, held
for a few consecutive frames to rule out a one-tick transient. Implemented as
`BattleRoundInput:waitForMenuReady()`.

- **Phase `1` is not the stable "ready" state for this function — phase `2` is.** Phase `1` is
  a single-tick step between "just initialized" and "genuinely idle," and is actively unsafe to
  write through, not just uninformative.
- **Each menu function defines its own meaning for the shared `DAT_80179fe8+0x4` phase
  counter.** `battle_menu_select_command` (the per-character command menu) has no phase `2` at
  all — its own stable "waiting for input" state is phase `1`. Always check which function is
  currently active (the coroutine-slot address) together with its phase, never phase alone.

## What the round confirm ("Ok?") step touches

- `ActionTag` (`combatant_rec+0x46`) resets to `0` for all six party members, clearing the way
  for `battle_dispatch_current_actor_action` to process them fresh.
- `DAT_8017be3c+0x4` is a **turn/round counter** (read as a full 32-bit value — the upper 3
  bytes stay 0), not a boolean "confirmed" flag. It increments by `1` the instant a round is
  confirmed — the very first frame after the "Ok?" tap — not when the round actually finishes;
  HP can keep changing for 900+ more frames as combat resolves. `lib/BattleSnapshot.lua` exposes
  it as `RoundNumber`. **Do not use this field to detect "has this round finished"** — the
  correct completion signal is the round-start menu becoming ready again (the same check used to
  start a round) or the gamestate leaving `BATTLE` entirely. Writing this counter directly (with
  valid actions already in place) while the round-start menu is still up does nothing on its
  own — the menu UI's own state, not this counter, is the real gate on whether
  `battle_dispatch_current_actor_action`'s coroutine chain is running.
- `enemy_data+0x40` (the 16-bit flags field noted in Battle_Damage_Formula.md) gets bulk-cleared
  across every allocated enemy-data slot (not just the combatants in the current battle),
  consistent with a per-monster "reset for the new round" state.

## Enumerating a character's available actions

Beyond *executing* a chosen action, simulation also needs to know what a character *can*
choose — every legal `(ActionType, AbilitySlot, TargetIdx)` combination for them right now.
Status per `ActionType`:

- **Attack (0) / Defend (1)**: a single option each — nothing to enumerate.
- **Item (3)**: `lib/Characters/Characters.lua`'s `character:read()` returns all 9 inventory
  slots (`Id`/`Quantity`/`Equipped`), and `lib/Battle.lua:getItemName(id)` resolves names.
  **Targeting is always ally-only** — items can never target enemies in this game. The item
  definition table's own target-type byte (`+0x16`, same field/values as Rune's) doesn't
  actually distinguish `2` (ally) from `3` (enemy) in `battle_try_special_attack`'s resolver — a
  single shared code path handles both — so the enumerator hardcodes ally-only for either value
  rather than trusting the raw byte the way Rune's resolver does.
- **Rune (2)**: a character's equipped rune id is `Addresses.lua`'s `Stats` address `+0x4C`
  (`Rune.Id`, already documented in `Characters_and_Stats.md`, already read by
  `lib/Party.lua:getCharacterRune`). From there:
  1. `DAT_8016a0e0[rune_id]` (a 34-entry pointer table, index 0-33 matching every id through
     True Holy) gives that rune's own "ability set" record.
  2. That record's `+0x1a`-`+0x1e` are 5 bytes indexed by `AbilitySlot` (0-4). Slot `0` is a
     `0`/unused sentinel; **slots 1-4 are that rune's actual Level 1-4 spell ids**, indexing
     `DAT_8016d33c` (the same spell-definition table Magic Unite combo ids use).
  3. Slot 4 additionally runs through `battle_check_magic_unite` first (see
     `battle_select_special_ability`'s own comment) — the ability-set's own byte there is just
     the solo fallback when no combo partner is found this round.
  4. **Level 5 spells are not reachable through this table via any slot 0-4** (e.g. Fire's Final
     Flame, id 29, never appears).
  5. **Two independent gates decide whether a given level (1-4) is actually selectable in
     battle**, both live in `battle_menu_select_rune_level`/`battle_menu_confirm_rune_level`
     (`0x800ec7a8`/`0x800ec8b8`):
     - **MP**: a level needs `Stats+0x08+level > 0` (the character's own MP pool for that
       tier — 4 separate pools, `Characters_and_Stats.md`'s `Stats+0x09..0x0C`).
     - **A separate story/scenario-flag lock, independent of MP.** The observable data lives at
       `DAT_80179fe8+0x80`, a position-index → `AbilitySlot` (1-4) lookup table populated by
       `compute_selectable_rune_levels` (`0x800ef67c`, called from
       `battle_menu_compute_command_availability`): it reads `Rune.Id`, walks
       `DAT_8016a0e0[rune_id]`'s ability-set record levels 4→1 requiring both a nonzero
       per-level spell-id byte AND nonzero MP for that tier, and writes eligible levels to
       `DAT_80179fe8 + level*4 + 0x7c` (level `1` lands at `+0x80`). This function has no
       explicit story-flag check of its own — only the static spell-id-byte + MP checks — so
       the actual mechanism behind some Soul Eater levels being locked independent of MP is not
       fully pinned down (see `notes/Scripted_Battle_Actions.md` for the evidence and leading
       hypothesis).
     - **Practical takeaway for the enumerator**: `lib/ActionEnumerator.lua`'s
       `enumerateRune(ctx, actorIdx, lockedLevels)` checks MP directly (always correct) and
       accepts an explicit `lockedLevels` table as a stand-in for the story-flag mechanism
       (caller-supplied per battle/character, e.g. `scripts/EnumerateCharacterActions.lua`
       hardcodes McDohl's `{[2]=true, [3]=true}` for `ZombieDragonT2.State`'s roster
       arrangement) — sufficient for scripted brute-force purposes even without the underlying
       flag's storage location.
- **Unite (4)**: `battle_select_unite_attack` resolves `AbilitySlot` through `DAT_8016d18c` — a
  **32-entry** table (index `0` unused/sentinel, `1`-`32` populated). Each entry's own leading
  bytes are a charmap-encoded name, followed by `+0x18` = required participant count (2/3/4),
  `+0x19` = an animation index, and `+0x1a` onward = exactly `count` bytes — the required party
  members' roster `Id`s (the same `Id` used everywhere else, e.g. `Addresses.lua`).
  Cross-referenced against the
  [Suikosource Unites Guide](http://www.suikosource.com/games/gs1/guides/unites.php) — matches
  on all 32 entries, both decoded names and required-`Id` bytes.

  `battle_menu_compute_command_availability` calls **`compute_unite_eligible_slots`**
  (`0x800ef104`) to filter this table down to what the current party can actually perform: it
  walks all 32 entries, checks the actor's own roster Id against each entry's required-Id list,
  and validates the other required Id(s) are present and alive in the living party
  (`check_combatant_valid_target` + `wStatusFlags & 0x61 == 0`), writing eligible slots to
  `DAT_80179fe8+0x80` and the count to `+0xa8` — this drives the Unite command slot's
  enable/disable in the menu. A script enumerating "what a character can currently Unite into"
  without reading the menu's own state can instead check each entry's required-`Id` list against
  the live party roster directly.

  | Slot | Name | Required party (roster `Id`s) |
  |---|---|---|
  | 1 | Talisman Attack | Gremio (2), Pahn (6) |
  | 2 | Fisherman Attack | Tai Ho (32), Yam Koo (38) |
  | 3 | Wild Arrow Attack | Kirkis (4), Sylvina (9) |
  | 4 | Elf Attack | Kirkis (4), Stallion (75), Sylvina (9) |
  | 5 | Pirate Attack | Anji (11), Kanak (43), Leonardo (41) |
  | 6 | Blacksmith Attack | Maas (70), Moose (72), Meese (69), Mace (71) |
  | 7 | Bumpy Attack | Krin (15), Humphrey (21) |
  | 8 | Pretty Boy Attack | Flik (17), Alen (48), Grenseal (49) |
  | 9 | Pretty Girl Attack | Camille (3), Tengaar (33), Kasumi (23) |
  | 10 | Beauty Attack | Cleo (1), Eileen (0), Valeria (36) |
  | 11 | Flash Attack | Liukan (7), Fukien (18), Kai (91) |
  | 12 | Kobold Attack | Kuromimi (14), Gon (80) |
  | 13 | Dragon Knight Attack | Futch (19), Milia (29) |
  | 14 | Fatal Attack | Gen (20), Kamandol (67) |
  | 15 | Trickster Attack | Juppo (39), Meg (76) |
  | 16 | Warrior Attack | Hix (63), Tengaar (33) |
  | 17 | Couple Attack | Lepant (30), Eileen (0) |
  | 18 | Bandit Attack | Varkas (12), Sydonia (31) |
  | 19 | Carpenter Attack | Gen (20), Sansuke (95) |
  | 20 | Wild Arrow Attack | Kirkis (4), Rubi (51) |
  | 21 | Wild Arrow Attack | Kirkis (4), Stallion (75) |
  | 22 | Blacksmith Attack | Maas (70), Moose (72), Meese (69), Mose (5) |
  | 23 | Blacksmith Attack | Mose (5), Moose (72), Meese (69), Mace (71) |
  | 24 | Blacksmith Attack | Maas (70), Mose (5), Meese (69), Mace (71) |
  | 25 | Blacksmith Attack | Maas (70), Moose (72), Mose (5), Mace (71) |
  | 26 | Beauty Attack | Cleo (1), Eileen (0), Sonya (10) |
  | 27 | Kobold +1 Attack | Fu Su Lu (65), Kuromimi (14), Gon (80) |
  | 28 | Beat'Em'Up Attack | Pahn (6), Ronnie (13) |
  | 29 | Ninja Attack | Kasumi (23), Fuma (55), Kage (22) |
  | 30 | Martial Arts Attack | Eikei (66), Pahn (6), Morgan (52) |
  | 31 | Lepant Family Attack | Lepant (30), Eileen (0), Sheena (62) |
  | 32 | Master Pupil Attack | Hero (8), Kai (91) |

  Several names repeat across multiple slots (Wild Arrow ×3, Blacksmith ×5, Beauty ×2) — each is
  a distinct valid partner combination for the same physical attack/animation, not a duplicate;
  `AbilitySlot` must still match exactly one specific slot number, so enumerating "what can this
  party currently perform" needs to check every slot independently even when several share a
  name.

## The InitialState snapshot (`lib/BattleSnapshot.lua`)

The plan for brute-forcing multiple turns is a pure-code simulator (running the
already-documented damage/RNG formulas natively, without the emulator) validated against real
emulator runs. The shared contract between the two is an **InitialState snapshot**: a plain-data
capture of everything the formulas need, taken at the pre-round-confirm moment (battle struct
stably populated, but before the round-start "Ok" is ever tapped — zero RNG consumed for the
round).

`BattleSnapshot:extract()` captures, per combatant: `Id`, HP, `SKL`/`SPD`/`MGC`/`LUK` (straight
from the live per-battle combatant array — already correct and stable at this point), `ATK`/
`DEF`, and (allies only) `Name`, `RuneId`, `MP`, `Items`. Plus the live 32-bit RNG seed
(`Address.RNG`), which alone determines every future roll.

**ATK/DEF are not simply readable pre-confirm.**

- For **party members**, `combatant_rec+0x30`/`+0x32` (where `calc_damage` itself reads them)
  hold stale/garbage values until the round actually starts — every party member's value changes
  on the first tick after confirm, the same tick the turn-order RNG roll fires, so there is no
  window where they're both valid and RNG-untouched.
- The actual populating code: `battle_refresh_combatant_derived_stats` (`0x800f6ea0`, runs once
  per round-start) calls `battle_compute_ally_derived_stats` (`0x800d4ec0`) once per party
  member, which computes derived stats fresh from each character's own persistent Stats struct
  (base PWR/SKL/DEF/SPD/MGC/LUK at `+0x10..+0x15`), applies a Gale Rune SPD-double, any equipped
  stat-boosting accessory's flat bonuses (item def `+0x1c` bit `0x80`, only if the item's own
  Equipped byte is set — these bonuses can land directly in the final ATK/DEF accumulator slots,
  not just the base PWR/DEF slots), and a weapon-type/weapon-level power-table lookup
  (`DAT_80165890` → `+0x54` class byte, then `PTR_DAT_801659cc[level*2 + class*0x20 + 2]`).
  `BattleSnapshot.lua`'s `computeAllyATKDEF()` replicates this exactly, verified byte-for-byte
  against the real post-confirm ATK/DEF for all 6 party members.
- For **enemies**, by contrast, `combatant_rec+0x14`/`+0x18` (not `+0x30`/`+0x32`, which stay
  stale for enemies too) already hold the correct final value pre-confirm — monsters have no
  equipment system, so their stats are set up once at battle/monster load rather than recomputed
  at round start. `BattleSnapshot.lua` reads these directly for enemies instead of replicating
  any formula.

Not yet extracted into the snapshot (needed by a simulator, but static/unchanging across every
battle, so planned as a separate one-time reference dump rather than re-captured per snapshot):
the Rune ability-set table, spell definitions, the Unite table, item definitions, and
`attack_data_table`'s elemental compatibility rows — all located during the action enumeration
work above.

## The TurnResult capture (`BattleRoundInput:runTurn()`)

The counterpart to the InitialState snapshot: given a round's `actions` (same sparse per-actor
shape `setActions()` takes), `BattleRoundInput:runTurn(actions)` applies them via the Free Will +
override recipe above, waits for the round to genuinely finish, and returns a `TurnResult` —
`RoundNumber`, `Outcome` (`"ongoing"`/`"victory"`/`"defeat"`), `RNGSeedBefore`/`RNGSeedAfter`, and
every combatant's `HPBefore`/`HPAfter`/`HPMax`/`Alive`. `RNGSeedAfter` alone determines the
entire future roll stream, so it's what lets a caller chain straight into the next turn's
snapshot.

The correct "round complete" signal reuses the round-start prompt's own ready check
(`waitForMenuReady`'s handler/phase check), or the gamestate leaving `BATTLE` entirely — the
round counter at `DAT_8017be3c+0x4` increments at round-*start*, not round-completion, so it
cannot be used here (see "What the round confirm ('Ok?') step touches" above). `Outcome`
detection: `"defeat"` reads `Gamestate.GAME_OVER` directly; `"victory"` is inferred from the
gamestate leaving `BATTLE` without hitting `GAME_OVER` first.
