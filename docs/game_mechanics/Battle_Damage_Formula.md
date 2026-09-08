# Battle Damage Formula

Covers the actual combat-resolution *code* (damage formula, critical hits,
elemental affinity) as reverse-engineered from `main.exe` in Ghidra. This
complements [Battles_and_Encounters.md](./Battles_and_Encounters.md), which
documents the encounter/enemy-group *memory layout* found via live-memory-
diffing from the Lua HUD side.

## Where the code lives

The battle engine is not in an overlay like most per-room/minigame logic
(see the Ghidra RE workflow notes) — `data/05_batle/battle1.8`/`battle2.8`
are background/music asset packs (an SPU ADPCM audio block, no code). The
real battle engine is permanently resident in `main.exe`, located via a
retail debug string the compiler didn't strip (`printf("ZOKUSEI %d AISYO
%d\n", ...)` — "ZOKUSEI" = element, "AISYO" = compatibility) even though
player-facing text elsewhere uses a custom charmap invisible to a plain
string search.

## The central battle-state struct

`DAT_8017be3c` (Ghidra type `BattleState *`, global name `g_pBattleState`)
is a pointer to the main battle-state struct in RAM (590 cross-references
throughout `main.exe`). Known offsets:

| Offset              | Field                          | Notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `+0x04`             | `dwRoundNumber`                | The battle's round counter — e.g. Zombie Dragon's AI checks this for "guaranteed Fire Breath on round 1."                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| `+0x08`             | `dwCurrentActorIdx`            | The combatant index whose turn is currently executing. A mirror of `+0x3420` (`g_nPendingIndex`), copied over on the tick right after the turn-order roll resolves, so the two fields read as equal almost all the time in a live viewer.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `+0x1C`             | `player_count`                 | Boundary between "party member" and "enemy" indices into the combatant array below                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `+0x20`             | `max_enemy_idx`                |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `+0x2c`             | (unnamed counter)              | A shared "uses available this turn" pool checked by the Rune/Item/Unite resolvers. Not the per-combatant `+0x2c` MGC stat — this is a fixed base-struct offset.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `+0x30`             | sync-signal array              | Base-struct-relative array, gated on "am I the current actor" — plausibly Unite-attack pairing.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `+0x34`             | `SyncSignals+4`                | A general "force a full round-state resync now" signal — checked by `battle_process_round_end_status_and_formation`'s phase-4→5 cleanup, and set both by Queen Ant's round-3 end-of-round callback and by the scripted Ted-vs-Queen-Ant forced-turn mechanism (see below).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `+0x50`             | `enemy_data[]`                 | Stride `0x8c`, raw 1-indexed actor numbers (same convention as the combatant array below). `[i]+0x0` = **Id** — indexes `attack_data_table` for elemental compatibility; for party members this exact byte matches each character's roster `Id` (`lib/Characters/Addresses.lua`, e.g. Hero=8, Viktor=35) — a per-character/per-monster identity value, not a species/type category. `[i]+0x5` = a **busy/reaction mutex byte**: `0`=idle-or-dead (both read the same — don't use this to filter dead combatants), `1`=busy performing an action, `8`=being hit/targeted (stays `8` even on a miss), `9`=hit by a Unite attack. It is a genuine mutex maintained by dedicated opcodes in the per-combatant animation-script interpreter (`play_attack_animation`, `0x800e3820`, running a 45-entry opcode table `PTR_LAB_8016babc`): `anim_op_set_busy_flags` (opcode 15, `0x800e3eac`, ORs a script-supplied mask into this byte, targeting self or the attack's target), `anim_op_clear_busy_flags` (opcode 16, AND-NOT), `anim_op_wait_until_busy_flags_clear` (opcode 44, stalls the script until the bits clear). The ordinary Attack script sets bit `1` on the attacker and bit `8` on the target. A 16-bit field at `enemy_data+0x40` (opcodes ~23–26) is a second, separate flag system used for effect/counter gating. |
| `+0xb40`            | combatant stat array           | Stride `0x54`; combined party+enemy array, addressed by **raw 1-indexed actor numbers** — actor 1 = first party member, actor `player_count+1` = first enemy (`+0xb94` is the same array pre-shifted by one stride, a shortcut for 0-indexed callers; both conventions appear in the codebase). Field offsets: `+0x10`/`+0x12` = max/current HP, `+0x26` = **SKL** (hit chance, crit chance), `+0x2a` = **AGL/SPD** (turn-order speed stat, see [Turn_Order.md](./Turn_Order.md)), `+0x2c` = **MGC**, `+0x2e` = **LUK** (crit chance), `+0x30` = **ATK** (PWR + equipped weapon's attack bonus — a distinct stat from base PWR), `+0x32` = a DEF-like stat (also likely equipment-inclusive), `+0x44` = formation-position byte, `+0x45` = alive/valid flag (`0`=valid), `+0x46`–`+0x49` = action-selection fields (own section below), `+0x4a` = status-effect bitmask (own section below). Enemy-side records in some encounters (e.g. Queen Ant's fight) use a distinct layout for some fields — e.g. enemy MGC there is read at `+0x1c`, not `+0x2c`.                                                                                                                                                                                                                                                                       |
| `+0xF84`            | `class_ptrs`                   | Per-party-member pointer table (stride `0xc`, same 1-indexed convention); `[i]+0x1c` reaches the character's own **persistent Stats struct** (Ghidra type `PersistentStats`) — the same struct `lib/Characters/Characters.lua`/`lib/Party.lua` already read from save data, not a separate battle-only "equip record."                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `+0x1258`           | `RngCallbackTable` pointer     | A STATIC `main.exe` table at `0x8016b680` (not per-battle heap data). Known slots: `[0]`=`rand()`, `[1]`=`play_attack_animation`, `[3]`=`calc_damage`, `[4]`=`apply_hp_damage_display`, `[7]`=sub-animation-slot-finder (used by opcodes 24/32), `+0x158`=slot `86`=`calc_rune_element_attack_damage` (see below). Overlay/monster-script code reaches `main.exe` functions indirectly through this table.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `+0x1330`/`+0x1334` | scripted-turn-override hook    | When armed (`+0x1330=1`), `+0x1334` holds a function pointer (into a monster's own overlay) invoked as a per-round callback. Used by scripted/story encounters for two distinct purposes: forcing a battle to end after a fixed round count (Queen Ant, Mt. Seifu), and forcing a specific character's specific action with no player input (the Ted-vs-Queen-Ant scripted fight). See "Queen Ant" sections below.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| `+0x1344`           | `attack_data_table`            | Pointer table indexed by the combatant's `Id` (`*4`); each entry is a `MonsterRecord` (own section below).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| `+0x3420`           | `g_nPendingIndex`              | The next actor index to run its turn; normally set by the weighted-RNG turn-order roll, but can be forced directly by a scripted-turn override.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `+0x30a0`           | per-status duration-slot table | `BattleState + status_id*0x10 + combatant_idx*0x80 + 0x30a0`: per-combatant per-status record (active flag, a second flag, a counter, and a computed value from `FUN_800e1e3c`, likely a status icon/animation-loop handle). Used by the 6 status ids that don't have their own dedicated countdown byte (see status-effects section).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |

`CombatantRec`/`EnemyData`/`ClassPtrEntry`/`MonsterRecord` are Ghidra struct
types with known sizes (`CombatantRec=0x54`, `EnemyData=0x8c`,
`ClassPtrEntry=0xc`), declared as single array elements at their correct
starting offsets — index further via pointer arithmetic using each struct's
own size rather than array subscripting, since the real element counts vary
by battle. Several regions are known to hold fields not yet individually
pinned down (most of the `+0xdc`–`+0xb40` and `+0xb94`–`+0x1258` gaps,
`+0x1268`–`+0x1344`, `+0x1348`–`+0x3420`) and are left as `undefined1[]`
padding rather than guessed at.

## `calc_hit_chance` (`0x800f7d5c`)

`calc_hit_chance(attacker_idx, target_idx) -> bool`:

```
chance = attacker.SKL(+0x26) - (target.SKL(+0x26) - 80), clamped to [60, 99] percent
if (attacker is a party member and attacker has status "Bucket" (combatant_rec+0x4a bit 0x10))
   or (attacker is an enemy and target's Rune.Id (persistent Stats +0x4c) == 18, Hazy Rune):
    chance = chance / 2
return (rand() % 100) < chance   -- compiled as `-(uint)(cond)`, so true reads back as -1, not 1
```

Both sides use the same stat (SKL), so it doubles as both accuracy and
evasion. The two halving branches are asymmetric by design: a party
attacker's own Bucket status (an offensive accuracy debuff) halves their
own chance, while an enemy attacker's chance is halved by the *target's*
own Hazy Rune (a defensive evasion buff) — not the enemy's own equipment.

## Action selection: `combatant_rec+0x46..+0x49`

Every combatant record carries a "what did this combatant queue up this
turn" block, driven by a real dispatch jump table
(`g_actionTypeDispatchTable`, `0x800c13ec`, 5 entries reading `+0x47`) — the
same field the project's Combat viewer displays as `ACT`:

| Offset | Field | Notes |
|---|---|---|
| `+0x46` | `ActionTag` | `0` = no action queued/resolved yet, `1` = this turn's action is executing/executed. |
| `+0x47` | **`ActionType`** | `0`=Attack, `1`=Defend, `2`=Rune, `3`=Item, `4`=Unite. |
| `+0x48` | **`AbilitySlot`** | Selected Rune/Item/Unite menu-slot index; meaning depends on `ActionType`. Unused for Attack/Defend. |
| `+0x49` | **`TargetIdx`** | Selected target's combatant index — one shared field for all five action types. |

`ActionType`/`AbilitySlot`/`TargetIdx` all read `255` (`0xFF`) when a
combatant's action is uninitialized/cleared — a fill pattern, not a real
`ActionType==255` enum value, and distinct from `ActionTag`'s own `0`/`1`
flag.

Three resolver functions turn `AbilitySlot` into an actual spell/item/Unite
id and validate `TargetIdx` (Attack goes straight to
`battle_execute_enemy_attack`, genuinely shared between both party and
enemy despite the name, see
[Turn_Order.md](./Turn_Order.md#how-a-turn-actually-starts-battle_dispatch_current_actor_action)
— and Defend to `battle_resolve_defend_action`, `0x800f40b8`):

- **`battle_select_special_ability`** (`0x800f5500`, Rune): resolves
  `AbilitySlot` through a per-character ability-set table (keyed by the
  character's persistent-stats `Rune.Id`, `+0x4c`) into a spell id. Slot `4`
  (the character's Level-4 elemental spell) is special-cased — see Magic
  Unite below. A second, differently-tabled internal branch (`DAT_8016a630`)
  handles characters with a nonzero ability-set flag — see below.
- **`battle_try_special_attack`** (`0x800f5050`, Item): resolves
  `AbilitySlot` by indexing the attacker's inventory array
  (`equip_ptr+0x1c+0x20`, 4 bytes/entry: `ushort` item id + a use-count
  byte). Decrements the use-count on cast; at `0` calls
  `FUN_800ca408(class_ptr, slot_idx)` (removes the now-empty slot).
- **`battle_select_unite_attack`** (`0x800f5790`, Unite): resolves
  `AbilitySlot` through its own table (`DAT_8016d18c`) — the manually
  selected character-pair physical Unite Attack (e.g. Viktor+Flik "Twin
  Dragons"). Loops every other party member for one with matching
  `ActionType==4` and the same `AbilitySlot` this turn (and a valid
  target); defers (returns early) rather than firing immediately if a
  partner match is found — the "wait for your Unite partner to also
  select it" sync check.

All three resolvers re-validate `TargetIdx` via `check_combatant_valid_target`
and store a pointer from the resolved definition into their own base-struct
slot (`+0x14` Rune, `+0x10` Item, `+0x18` Unite) — an animation/effect
script pointer, one slot per action type.

### Magic Unite spells: `battle_check_magic_unite` (`0x800f5398`)

A separate mechanic from the `ActionType==4` command above: Suikoden 1 has
five **magic** Unite spells — Scorched Earth (Fire+Earth), Storm Fang
(Earth+Wind), Water Dragon (Wind+Water), Thor (Water+Lightning), Blazing
Camp (Lightning+Fire) — per
[Suikosource's Unite Magic page](http://www.suikosource.com/runes/unitemagic.php).
Each requires two Level-4 spells of adjacent elements cast the same round,
triggers automatically, and follows a strict targeting/resistance priority.

It lives entirely inside `battle_select_special_ability` (Rune resolver):
when a caster selects `AbilitySlot==4` (their own Lv4 spell),
`battle_check_magic_unite(attacker_idx, own_lv4_spell_id)` scans every other
still-unresolved party member for one who *also* queued `ActionType==2` +
`AbilitySlot==4` this round, checks the spell-id pair against a lookup table
(`DAT_8016c724`, 3 bytes/entry, 40 entries), and on a match marks the
partner's action resolved, plays a shared animation, and returns the
combo spell id (fed into the same spell table normal spells use). No match
falls back to the caster's own solo Lv4 spell.

The 40-entry table decodes to 8 raw pairings × 5 combo outputs (every
element has a Lv4 and Lv5 id):

| Element | Lv4 id | Lv5 id |
|---|---|---|
| Fire | `4` | `29` |
| Earth | `24` | `33` |
| Wind | `16` | `31` |
| Water | `12` | `30` |
| Lightning | `20` | `32` |

| id | Spell | Elements | Target type |
|---|---|---|---|
| `34` | Scorched Earth | Fire + Earth | AOE (all enemies) |
| `35` | Storm Fang | Earth + Wind | AOE (all enemies) |
| `36` | Blazing Camp | Lightning + Fire | AOE (all enemies) |
| `37` | **Thor** | Water + Lightning | single-target |
| `38` | Water Dragon | Wind + Water | `0` |

Thor is the only one flagged single-target, and only when the faster
caster's contribution was specifically Ball of Lightning (Lightning's own
Lv4, itself single-target). Element adjacency forms the expected
Fire–Earth–Wind–Water–Lightning 5-cycle.

### The unique-rune ability table (`DAT_8016a630`)

`battle_select_special_ability`'s ability-set record has a `+0x16` flag byte
that takes three distinct values, read from all 34 entries of the
equipped-rune lookup table (`DAT_8016a0e0`):

- `0` — the 5 basic elemental runes (Fire/Water/Wind/Earth/Lightning) + Soul
  Eater: normal leveled spell progression through `DAT_8016d33c`.
- `1` — exactly 6 entries, charmap-decoded by name as **Boar Rune, Shrike
  Rune, Falcon Rune, Hate Rune, Trick Rune, Clone Rune** — real Suikoden 1
  unique/single-character runes, distinct from the generic elemental set.
  `DAT_8016a630` is a separate special-ability definition table specifically
  for these unique runes, structurally parallel to (but a distinct pool of
  entries from) `DAT_8016d33c`'s elemental spell table, and read via the
  identical `+0x1c`=cast-handler / `+0x16&3`=target-type-flags shape.
- `2` — every remaining entry (from index 14 onward) — unconditionally
  **rejected** by `battle_select_special_ability` (`if (flag != 1) return
  -1`, inside the branch that only runs when flag isn't `0`) — these rune
  slots can never be selected as a normal Rune action through this code
  path at all.

The per-rune `DAT_8016a0e0` record also has an undocumented `+0x18` field
(slot count) and a fuller `+0x16` flags word (bit `0x8000` = roster-id
whitelist for character-restricted unique runes).

## Status effects: `combatant_rec+0x4a`, `apply_status_effect` (`0x800e04dc`)

**The field**: a 16-bit bitmask, `combatant_rec+0x4a` (same struct as
`ActionType`/`AbilitySlot`/`TargetIdx` at `+0x46..+0x49`). Mask table
(`DAT_8016baa8`, 9×u16): `id0=0x0001`, `id1=0x0002`, `id2=0x0004`,
`id3=0x0008`, `id4=0x0010`, `id5=0x0020`, `id6=0x0080`, `id7=0x0040`,
`id8=0x8000`.

**`id1`/`id2`/`id3` are one escalating ailment ("Balloon"), not three
separate ones**: stages 1/2/3 of the same status — repeated infliction
pushes the afflicted character from stage 1 to 2 to 3, and reaching stage 3
(`id3`) removes them from the party. `anim_op_roll_status_effect_chance`'s
`status_id==1` handling searches whether stage-slots 1, 2, or 3 are already
occupied and applies to the first free one, rather than unconditionally
targeting slot 1. `apply_status_effect` gives exactly `id1`-`id3` (and only
those three) a shared equipment-immunity check, since they're a related
family sharing one "immune to this ailment" accessory check.

**`apply_status_effect(combatant_idx, status_id)`**: two branches —
- **Enemy** (`combatant_idx > partyCount`): ORs the mask bit into `+0x4a`.
  No duration tracking, no immunity check — effectively permanent until
  cleared elsewhere.
- **Party member**: a switch on `status_id` sets an internal tick-duration
  regardless of any caller-supplied default: `id0=12, id1=4, id2=6, id3=8,
  id4=10, id5=15, id6=22, id7=21`. `id5` and `id7` also immediately set
  `ActionTag (+0x46) = 1`, marking the combatant's turn as already-resolved
  without ever going through normal action selection — their `ActionType`
  reads back as the `255` "cleared/uninitialized" sentinel, silently
  skipping their turn rather than forcing an uncontrolled Attack (`id7`
  additionally sets an unidentified `+0x4d=1`). `id8` takes a separate,
  simpler path: sets `combatant_rec+0x4c=2` (a distinct field from the
  persistent Stats struct's own `+0x4c` `Rune.Id` — a coincidental offset
  match, different struct) and skips straight to the same no-duration
  flag-set the enemy branch uses. For `id1`-`id3` specifically (party
  members only), first scans the character's equipment/item list for an
  entry of "type `3`" with a nonzero flag byte — if found, blocks the
  status entirely (an immunity accessory/rune). Otherwise sets the bit and
  populates a per-combatant per-status "slot" record (see the
  `+0x30a0` table above: active flag, a second flag, a counter, and a
  computed value from `FUN_800e1e3c`, likely a status icon/animation-loop
  handle).

**`anim_op_roll_status_effect_chance(combatant_idx)`** (animation-script
opcode 40, script args: `status_id`, `chance_arg`): rolls RNG2 against
`chance_arg` (inverted — roll `< chance_arg` means *skip*, so the real
infliction chance is `100-chance_arg`%). Party members get an extra
unconditional-immunity check first: if their persistent-stats `Rune.Id`
(`+0x4c`) `== 25` (Turtle Rune), the roll never happens at all — one of
several rune ids gating hardcoded passive effects on this same field
(`15`/Killer doubles crit chance, `18`/Hazy halves the wearer's attacker's
hit chance, `16`/Counter guarantees a successful dodge/counter — see
"Passive rune effects" below for the full list). This opcode always targets
its *own* `combatant_idx` (no self/target redirect like
`anim_op_set_busy_flags` has): a status-inflicting physical attack works by
the attacker's script marking the target hit (via `anim_op_set_busy_flags`)
while the target's own independently-running script (each combatant in
`enemy_data` runs its own script cursor) reaches this opcode as part of its
own hit-reaction sequence, inflicting the status on itself.

A battle-initialization routine (4 call sites clustered at
`0x800de85c`-`0x800de8b4`) reads each party member's *persistent* save-data
`Status` byte (`lib/Characters/Characters.lua`'s `Status = buffer[0x17]`,
real offset `+0x16`) bit-by-bit (`0x1`/`0x2`/`0x4`/`0x8`) and re-applies
`id0`-`id3` respectively to the fresh in-battle record if set — these 4 are
the classic "still afflicted from the overworld when you enter a new fight"
ailments (this is why only 4 of the 9 ids get an equipment-immunity check
in `apply_status_effect` too — the other 5 are battle-only, no carryover to
protect against).

**Round-end processing** (`battle_process_round_end_status_and_formation`):
- **`id3`** (bit `0x8`): the afflicted party member vanishes entirely from
  the HP list, sprite lies face-down on the battlefield — a one-shot,
  never-expiring effect (`+0x45=1`/`+0x46=1`) triggering front-row
  backfill — a KO/Petrify-equivalent removal from active combat.
- **`id5`** (bit `0x20`): `ActionType` reads back as the `255`
  "cleared/uninitialized" sentinel after a round passes, meaning the turn
  is silently skipped without ever going through normal action selection —
  a "can't act this turn" ailment, matching the enemy-side behavior
  documented for this same bit in `Turn_Order.md`. Tentatively named
  "Sleep."

`id7` (bit `0x40`) and `id8` (bit `0x8000`) use their own dedicated
one-byte countdown fields (`+0x4d` and `+0x4c` respectively, decremented
once per round, expiring via `clear_status_effect` when they hit `0`)
rather than the generic per-status duration-slot table the other ids use —
both resolve in only 1-2 rounds given the initial values `apply_status_
effect` sets. `clear_status_effect`'s own guard clause no-ops for every
status except `id8` unless the generic duration-slot's "active" flag is
also set — `id7`'s natural expiry depends on that slot-table data.

**`id0` (Poison)**: a periodic-damage effect (full formula below).

**`battle_menu_compute_command_availability`** (`0x800eedd0`) populates the
Fight-menu's 5 command slots (Attack/Defend/Rune/Item/Unite)
enabled/disabled before the player picks an action:
- **Attack slot** disabled if `combatant_rec+0x4a & 0x60` (bit
  `0x20`=`id5` OR bit `0x40`=`id7`).
- **Rune slot** disabled if `combatant_rec+0x4a & 0xe0` (bit `0x20`=`id5` OR
  bit `0x80`=`id6` OR bit `0x40`=`id7`).
- **Defend** always enabled; **Item**/**Unite** gated only by availability,
  never by status.

This means `id7` ("Unbalanced") disables Attack and Rune, leaving only
Defend/Item/Unite selectable for 1 turn. `id6` ("Silence-equivalent") is a
Rune-only disable, nothing else. `id5` ("Sleep") shares this exact same
Attack+Rune menu restriction with `id7`, layered on top of the harder
"skip the turn/AI call entirely" gate, consistent with `id5` being a
related but more severe ailment than `id7` (they also use different
duration/expiry mechanisms: `id5` the generic duration-slot table, `id7`
its own dedicated `+0x4d` countdown).

`id4` is "Bucket," the accuracy-halving status from `calc_hit_chance`'s own
`+0x4a` bit `0x10` check. The real game shows a visible bucket icon over
the afflicted character, which needs a real handle computed by
`FUN_800e1e3c` (spawned only through the genuine `apply_status_effect` code
path).

**Full roster**: `id0`=Poison, `id1`/`id2`/`id3`=**Balloon** (escalating,
stage 3 = removed from party), `id4`=**Bucket** (accuracy-halving),
`id5`=**Sleep** (Attack+Rune-restricted plus a harder skip-gate),
`id6`=**Silence-equivalent** (Rune-only block), `id7`=**Unbalanced**
(Attack+Rune restricted, "defend or item only"), `id8`=**Copper Flesh**
(HP-locked/damage-immune for 3 turns).

### Poison (`id0`): mechanics and per-tick damage formula

**Application**: `anim_op_roll_status_effect_chance` (opcode 40, script
args `status_id=0`, `chance_arg`) rolls RNG2 once regardless of the
outcome. For a party-member target the infliction condition is
`roll_pct(0-99) < chance_arg` — so `chance_arg=100` makes the roll
unconditionally succeed, and `chance_arg=0` would make it unconditionally
fail; the roll always consumes RNG, but the outcome can be scripted to be
deterministic on either end. Not gated by the Turtle-Rune immunity check
either way (that check runs before this roll, separately).

**The periodic tick itself: zero RNG, exactly `floor(HP_Max / 20)` per
round** — disassembly of `battle_refresh_combatant_derived_stats`'s
round-start processing (`0x800f6ea0`): for each living party member with
Poison active (`combatant_rec+0x4a & 1`), the code does

```
lh   v0, 0x10(s0)      ; v0 = signed HP_Max (combatant_rec+0x10)
div  v0, s2            ; s2 == 0x14 == 20 (set earlier in the same function)
mflo v0                ; v0 = floor(HP_Max / 20), C truncating division = plain floor since positive
subu a1, a1, v0        ; subtract from the round's accumulated regen total
```

i.e. Poison deals a flat 5% of max HP every round, rounded down — not a
random amount, not scaled by current HP, not affected by DEF or any other
stat. This gets netted against the same round's regen sources (`+5` each
from certain items, weapon-type-2 mastery×5, and Sunbeam Rune) before being
applied via `apply_hp_damage_display(idx, -total)` — so a character with
enough regen sources active can end up healing instead of taking poison
damage on a given round, and the whole thing is skipped (no call at all) if
the netted total is exactly 0.

**Duration**: `apply_status_effect`'s own switch sets Poison's initial
duration to `12` (rounds).

### Passive rune effects (`Rune.Id`, persistent Stats `+0x4c`)

`class_ptrs[idx]->+0x1c` reaches the character's persistent Stats struct
(`lib/Party.lua: getCharacterRune` reads the same struct), and `+0x4c` on
it is `Rune.Id` (0-33, the same 34-entry enum decoded above). There is no
separate "weapon-type" struct or field on this offset. A number of engine
functions hardcode per-rune checks against this field directly, rather than
routing through a generic passive-effect system:

| Value | Rune | Consumer | Effect |
|---|---|---|---|
| `14` (`0x0e`) | Double-Beat | `battle_execute_enemy_attack` | enables the multi-target attack-repeat path (e.g. Zombie Dragon's Fire Breath) |
| `15` (`0x0f`) | Killer | `check_critical_hit` | doubles crit chance (up to 50%) |
| `16` (`0x10`) | Counter | `check_dodge_counter` | guarantees a successful dodge/counter roll |
| `18` (`0x12`) | Hazy | `calc_hit_chance` | halves an attacking enemy's hit chance against whichever combatant has Hazy equipped (boosts the wearer's own evasion) |
| `19` (`0x13`) | Gale | `battle_compute_ally_derived_stats` | doubles the SPD stat slot in the per-round derived-stats computation |
| `20` (`0x14`) | Sunbeam | `battle_refresh_combatant_derived_stats` (battle) and `FUN_80126408` (a separate, non-battle subsystem) | in battle, contributes `+5` to a per-round REGEN total; via a shared helper `FUN_801261b0(20)` in the `DAT_8017db24` subsystem (very likely the overworld step-counter), heals every party-roster member by 1 HP (capped at max) per step |
| `21` (`0x15`) | Holy | `FUN_801328b0` (the `DAT_8017db24` subsystem) | gates a boolean check, OR'd with a separate roster-id-based check |
| `22` (`0x16`) | Fortune | `battle_calc_enemy_aggro` | doubles a per-party-member XP-related counter field (offset `+0x10` in the `DAT_80179fd0`-based array, distinct from the aggro score at `+0x14`) |
| `23` (`0x17`) | Prosperity | `battle_process_enemy_turns` | doubles a battle-wide accumulated total (`DAT_80179fd0+0x224c`) built by summing `MonsterRecord.wGoldDrop` (`+0x34`) across every living enemy. The encoding has a bit-0 "compressed large value" branch (`(raw/10)*100` when the low bit is set). |
| `24` (`0x18`) | Champion's | `FUN_80126228`/`FUN_801261b0` (the `DAT_8017db24` subsystem) | in a `rand()`-based weighted lottery/selection event, bypasses a luck-threshold check and forces success |
| `25` (`0x19`) | Turtle | `anim_op_roll_status_effect_chance` | unconditional immunity to status-effect infliction |
| `26` (`0x1a`) | Phero | `find_cover_target` | gates a fallback "cover for any opposite-gender ally" condition |

The numeric mapping (id → mechanism) is read directly from code. `MonsterRecord.wGoldDrop`
(`+0x34`) was formally added to the Ghidra struct (struct resized 52→54
bytes).

**Other persistent-Stats fields found**: a `+0x4d` byte checked against a
31-entry `DAT_8016b080` table in the out-of-battle rune-equip menu (a
mastery/eligibility gate, distinct from the cover-mechanic's classData
fields). One `+0x4c` reader, `0x800f81e8`, compares two combatants'
MGC-stat difference (`<10`) and conditionally calls the RNG wrapper — not
otherwise identified.

### Cover mechanic: `battle_check_counter_attack`, `find_cover_target`

**`battle_check_counter_attack`** (`0x800f4d5c`) is the cover mechanic's
real entry point (the name is a historical misnomer, kept unrenamed given
how many places already reference it — it is not a counterattack check).

When an attack is about to land on `target_idx`:

1. **`find_cover_target(target_idx)`** (`0x800f79e0`) resolves whether some
   *other* party member should intercept the hit instead, but only when
   `target_idx`'s own current HP is below 25% of max. Two independent
   trigger paths, checked in order:
   - **A designated low-HP story pairing**: `target_idx`'s own
     "classData[0]" byte (a field one level before the persistent Stats
     struct) is matched against a lookup table at `0x8016c814`, interleaved
     `(self_id, partner_id)` byte pairs, terminated by `0xFF`. Full table
     is 15 pairs: `(8,2) (8,6) (8,1) (1,6) (2,3) (32,38) (38,32) (33,63)
     (9,4) (0,30) (30,0) (62,0) (8,23) (32,45) (14,80)`. Resolving roster
     Ids via `lib/Characters/Addresses.lua` gives (self → cover partner, in
     priority order — a self-id appearing more than once yields a
     multi-candidate priority chain):

     | Self | Cover partner(s), in priority order |
     |---|---|
     | Hero | Gremio → Pahn → Cleo → Kasumi |
     | Cleo | Pahn |
     | Gremio | Camille |
     | Tai Ho | Yam Koo → Kimberly |
     | Yam Koo | Tai Ho *(mutual with Tai Ho's first pick)* |
     | Tengaar | Hix |
     | Sylvina | Kirkis |
     | Eileen | Lepant |
     | Lepant | Eileen *(mutual with Eileen)* |
     | Sheena | Eileen |
     | Kuromimi | Gon |

   - **Phero Rune fallback**: if the above found nobody, and `target_idx`'s
     `Rune.Id == 26` (Phero), scans every other valid, non-busy party
     member (wrapping from `target_idx+1`) for the first one whose own
     "classData+10" byte *differs* from `target_idx`'s — a gender byte.
2. If a cover character is found, `battle_check_counter_attack` plays
   reciprocal "jump in front" animations between the two, then sets the
   attacker's own per-actor "next micro-state" slot (`combatant_rec+0x50`)
   to **`apply_covered_attack_damage`** (`0x800f5e90`); with no cover
   found, to **`apply_uncovered_attack_damage`** (`0x800f5960`) instead.
   Either way, the attacker's main attack animation still plays against the
   *original* `target_idx` — the actual redirect happens later.
3. Once the animation reaches its "apply damage" point, whichever state
   function was set runs: `apply_covered_attack_damage` computes and
   applies damage against the **cover character** instead of the original
   target (who takes zero damage — full substitution, not a split or
   partial block); `apply_uncovered_attack_damage` applies it to the
   original target normally (with a couple of alternate hit-reaction
   animations gated on the target's own equip-record `+0x46` byte — a
   weapon/armor-class field, unrelated to `Rune.Id`).

**`PersistentStats`** (`classData+0x1c`) known fields: `+0x44`
(`bWeaponReachIndex`, byte) indexes a per-weapon-type ability/reach table
(`DAT_80165890`), used in `battle_menu_select_target`/`FUN_800eec20`,
gating whether a character can target the back row unassisted regardless
of formation position. `+0x46` weapon type, `+0x47`/`+0x49`
weapon-type-specific mastery bytes, `+0x4c` `Rune.Id`, `+0x55` item element
override, `+0x56` (`bDodgeCounterFlag`, byte) tested as a bitmask (`&1`) in
`check_dodge_counter` ("can counter/dodge" gate) and as an exact match
(`==2`) in `battle_execute_enemy_attack`.

Every classData (`+0xf84`) access site in `main.exe` touches it only via
offset `0`, `0x10`, or `0x1c` (the Stats-struct pointer) — classData itself
is at least `0x20` bytes (offset `0x1c` is a 4-byte pointer, ending at
`0x20`), and nothing else is read directly off its base.

## Formation management: front-row auto-backfill

`battle_process_round_end_status_and_formation` (`0x800f64f0`, a state
within the same turn-advance coroutine as `battle_advance_turn`) runs a
front-row auto-backfill system after status decay: it checks each side's
front row (formation positions `1-3`) for now-invalid combatants (KO'd, or
removed by a status effect like `id3`) and tries to backfill the gap from
the back row (`battle_swap_combatant_positions`). Party members have no
eligibility restriction. Enemies do: `mark_enemy_formation_slot_occupancy`
(`0x800f777c`) first builds a 6-slot occupancy map by scanning every valid
enemy and reading **`monster_record(enemy.Id)+0x11`** to decide how many
*additional* adjacent slots its sprite also occupies beyond its own current
position — `0`→just its own slot, `1`→also the next slot, `2`/`3`→also the
next two. The backfill loop then only pulls a back-row enemy forward if
enough *contiguous empty slots* exist to fit its own footprint.

So `+0x11` is a **formation-slot occupancy footprint**, not a target-scan
restriction, a species/type tag, or an attack-range flag. Values: `2` for
dragons (wide wingspan, need 3 slots), `1` for golem/statue-types (Golem,
EarthGolem, ClayDoll, Colossus, DevilArmor — need 2), `0` for everyone else
checked (Gigantes, Anji, Sydonia, CrimsonDwarf, BlackWildBoar, GiantSnail,
DevilShield, Killer Rabbit — need only 1 slot). Sprite height and
formation-footprint width are different axes: Gigantes is visually one of
the tallest sprites in the game (clips off the top of the screen) but is
narrow enough to need only a single formation slot.

## `calc_damage` — physical attack formula (`0x800f7e90`)

`calc_damage(attacker_idx, target_idx)`:

1. **Base value**: `attacker.ATK(+0x30) - target.DEF(+0x32)`.
2. **Random variance**:
   - If base `< 10`: `base = (base + 1) - (rand() % 4)`.
   - Else: `base = base + (base/2 - rand()%base) / 5` (C truncating division).
3. **Defend**: if the target is a party member and their `ActionType==1`
   (Defend), `base /= 2`.
4. **Elemental weapon bonus** (attacker must be a party member): the
   attacker's weapon type maps to an element id via
   `g_abWeaponTypeToElement` (`{0xff, 0, 1, 2, 3, 4}`, weapon types `1..5`
   → element ids `0..4`; an item can override this via its own element
   field). This is the same unified element numbering the magic-side
   `apply_elemental_multiplier` uses (`0` Fire, `1` Water, `2` Earth, `3`
   Lightning, `4` Wind, `5` Resurrection, `7` Dark/Soul-Eater) — both
   weapon and spell damage paths index the identical `attack_data_table`
   compatibility row. If that element's compatibility byte for the
   target's `Id` is `1` (weak), `base += base/2` (+50%, stacking with the
   variance already applied). Weapon types `1` and `3` get an additional
   `base += (base/20) * mastery_byte` bonus, where `mastery_byte` is
   self-indexed from `equip_struct + 0x46 + weapon_type` — `+0x46` onward
   is a small per-weapon-type mastery array, though `calc_damage` only ever
   reads two of its slots.
5. **Floor**: clamped to a minimum of `1`.

## `check_critical_hit` (`0x800f835c`)

```
chance = (combatant.SKL(+0x26) + combatant.LUK(+0x2e)) / 8, clamped to [3, 25] percent
if combatant is a party member and their Rune.Id (persistent stats +0x4c) == 15 (Killer Rune):
    chance *= 2   -- up to 50%
return (rand() % 100) < chance
```

## `apply_elemental_multiplier` (`0x80125b28`)

The magic/rune-attack equivalent of `calc_damage`:

```
base_total = base_power + floor(attacker.MGC_stat / 2)
if target's compatibility byte for element_id == 1 (weak):   damage = base_total * 2
if target's compatibility byte for element_id == 2 (resist): damage = floor(base_total / 2)
if target's compatibility byte for element_id == 3 (immune): damage = 0
otherwise (neutral):                                          damage = base_total
element_id == 7 (Dark/Soul-Eater) bypasses the compatibility check entirely,
always returning base_total unscaled
```

No random variance anywhere — magic damage is fully deterministic given
base_power, caster MGC, and target compatibility. The attacker stat term
reads the same combatant-record offset documented as MGC above. The target
lookup uses `attack_data_table`, indexed by `enemy_data[target]+0x0` (the
`Id` field).

Called from 21 sites spanning `0x800ff174`–`0x80117350`. Each site loops
over a target index, skips it if `combatant_rec(target)+0x45` is set (an
"already resolved/invalid target" flag), otherwise calls
`apply_elemental_multiplier(a0, element_id, target, attacker, base_power)`
with `base_power` as a compile-time constant. `a0` is **spell level (1–5)**
(`apply_elemental_multiplier` itself never reads it, but it fits every
undisputed spell mapping below with one exception).

### The 21 callers

| Address | Lvl | Element | Power | Spell |
|---|---|---|---|---|
| `0x800ff174` | 1 | 0 (Fire) | 100 | Flaming Arrows (single-target) |
| `0x800ffcbc` | 2 | 0 (Fire) | 150 | Firestorm |
| `0x80100bdc` | 3 | 0 (Fire) | 400 | Dancing Flames |
| `0x80101ac4` | 4 | 0 (Fire) | 700 | Explosion |
| `0x801028e4` | 5 | 0 (Fire) | 900 | Final Flame |
| `0x8010998c` | 2 | 4 (Wind) | 400 | The Shredding |
| `0x8010ace4` | 4 | 4 (Wind) | 500 | Storm |
| `0x8010b918` | 5 | 4 (Wind) | 500 | Shining Wind |
| `0x8010c6e8` | 1 | 3 (Lightning) | 150 | Angry Blow |
| `0x8010d3c8` | 2 | 3 (Lightning) | 100 | Rainstorm |
| `0x8010e064` | 3 | 3 (Lightning) | 600 | Raging Blow |
| `0x8010ef44` | 4 | 3 (Lightning) | 1000 | Ball of Lightning |
| `0x8010fea0` | 5 | 3 (Lightning) | 900 | Thunder God |
| `0x8011349c` | 2 | 2 (Earth) | 300 | Voice of Earth |
| `0x80111ce8` | 4 | 2 (Earth) | 700 | Earthquake |
| `0x801033e8` | 1 | 5 (Resurrection) | 70 | Scolding (double dmg vs undead) |
| `0x80105748` | 4 | 5 (Resurrection) | 500 | Charm Arrow (ROM value 500, not the reference's 400) |
| `0x80114300` | 1 | 7 (Dark) | 2 | Deadly Fingertips (instant-death; power is a non-HP-effect sentinel) |
| `0x8011519c` | 2 | 7 (Dark) | 300 | Black Shadow |
| `0x80116078` | 4 | 7 (Dark) | 2 | Hell (instant-death to all enemies) |
| `0x80117350` | 4 | 7 (Dark) | 1500 | Judgement |

Spell ids are cross-referenced against
`Suikoden-RNG-lib/lib/Game/Combat/Magic/Spells.js` (every undisputed match
lines up on damage value exactly — no in-binary name strings exist to
confirm against, see `lib/Charmap.lua`). Element `1` (Water) never appears
because every Water-rune spell in the reference data is ally-targeted
(healing/buffs) and never needs this lookup. Element `7` is the Dark/Soul-
Eater element specifically (not a generic "no-element" sentinel) — it
narratively bypasses normal resistances by design
(`apply_elemental_multiplier`'s `param_2 != 7` check implements the
exemption).

Hell (`0x80116078`) is confirmed by behavior: the code right after this
call site is structurally near-identical to Deadly Fingertips' confirmed
instant-death implementation (both check a target-immunity flag, then
decrement an alive-count and clear a status byte), with extra bookkeeping
consistent with hitting multiple targets (AOE) vs. Deadly Fingertips'
single target.

## Enemy elemental attacks: `calc_rune_element_attack_damage` (`0x800f8174`)

A third damage formula, distinct from both `calc_damage` (physical,
`ATK-DEF`, RNG variance, no elemental scaling) and `apply_elemental_
multiplier` (magic, `base_power+MGC/2`, fully deterministic, elemental
scaling). It combines pieces of both: RNG variance like `calc_damage`, but
with the MGC stat substituted in for both sides, and elemental scaling
folded on top via a different, rune-based resistance mechanism:

```
base = attacker.MGC(+0x2c) - target.MGC(+0x2c)   -- NOT target.DEF
variance: identical to calc_damage's RNG-variance step, one rand() call:
  if base < 10:  base = (base + 1) - rand() % 4
  else:          base = base + (base/2 - rand()%base) / 5   -- C truncating division
followed by a rune-category resistance check (see below)
floor at 1
```

This is a genuinely different resistance mechanism from the
species-compatibility table `calc_damage`/`apply_elemental_multiplier`
share. Since party members have no "species" entry in `attack_data_table`,
an enemy attack that wants to respect elemental resistance on a party
member has to key off something else: the target's own equipped Rune.

Reached indirectly: overlay/monster-script code calls this function through
`RngCallbackTable` slot `86` (`+0x158`), rather than a direct `jal` — which
is why a direct xref search on `calc_damage`'s address doesn't find these
call sites.

**Rune-category resistance table**: the target's own equipped `Rune.Id` is
looked up in a switch table mapping to one of several categories:

| Rune.Id | Rune | Category | Rune.Id | Rune | Category |
|---|---|---|---|---|---|
| `1` | Soul Eater | **7 (universal)** | `4` / `0x1d` | Wind / Cyclone | 5 |
| `2` / `0x1b` | Fire / Rage | 1 | `5` / `0x1f` | Lightning / Thunder | 4 |
| `3` / `0x1c` | Water / Flowing | 2 | `7` | Resurrection (alone) | 6 |
| `6` / `0x1e` | Earth / Mother Earth | 3 | `8`-`0x1a`, `0`, `>0x1f` | (Boar..Phero, Nothing, etc.) | — (see bug below) |

Damage is halved if the target's category equals the attack's own
`element` argument, or if the category is `7` — that second check is
unconditional, independent of `element`, making category `7` (Soul Eater
alone) a universal resist rather than an elemental match. Every other
category only protects against an attack passing the matching `element`
value. Clamped to minimum 1. Fire Rune's own category (`1`) does not match
Fire Breath's `element` argument (`6`) — Fire Rune does not resist Fire
Breath, despite the thematic naming.

### A compiled bug: a free "matching slot index" damage reduction

`calc_rune_element_attack_damage`'s only conditional modifier is a halving
(`if match: damage /= 2`) — there is no doubling/weakness branch anywhere
in this function, unlike `apply_elemental_multiplier` (which has real
weak/resist/immune ×2/÷2/×0 branches). This bug can only ever work in the
player's favor — a free damage reduction, never a hidden weakness.

For every `Rune.Id` *not* in the explicit table above (`0`, `8`-`0x1a`,
anything `>0x1f`), the switch statement jumps straight to the halving
comparison **without ever writing the "category" variable**, which lives
in register `$s1` (or `$s0`, depending on the caller). Since this register
is callee-saved, the comparison reads whatever the *caller* left there —
and in each monster's own damage-dispatch loop, that register is being
reused as **the loop's own target-party-slot counter**.

So for any character whose Rune doesn't explicitly override the category,
the "resistance" check accidentally becomes **`target's own party slot
index == element`** — a register-reuse bug, not a real elemental check.
Whichever party member currently occupies the slot matching the attack's
own `element` argument gets an accidental 50% reduction, regardless of what
(if anything) they have equipped, as long as it isn't one of the runes with
an explicit case. A character whose equipped rune *does* have an explicit
category masks the bug for that character.

This bug is a general property of the shared formula function combined
with how each monster's own calling loop happens to reuse registers — it
is present in at least 11 call sites across 7 different bosses/monsters:

| Monster | Overlay | `element` | Target register | Bug status |
|---|---|---|---|---|
| Zombie Dragon (Fire Breath) | `enemy_ai_overlay.bin` | 6 | `$s1` (loop) | Live — slot 6 |
| "Dragon" (mid-boss) | `dragon_overlay.bin` | 8 | `$s1` (loop) | Dormant (`>6`, no real slot can match) |
| " | " | 1 | `$s1` (loop) | Live — slot 1 |
| " | " | 4 | `$s0` | loop bounds not fully traced |
| Golden Hydra (final boss) | `vzv.bin` | 8 | `$s0` (loop) | Dormant |
| " | " | 4 | `$s1` (loop) | Live — slot 4 |
| " | " | 1 | `$s1` (loop) | Live — slot 1 |
| Golem | `va4.bin` | 3 | `$s1` (loop) | Live — slot 3 |
| Queen Ant's AoE Earth attack | `va7.bin` | 3 | `$s0` (loop) | Not bugged in practice — see Queen Ant below |
| Gigantes | `vc3.bin` | 1 | `$s0` (loop) | Live — slot 1 |
| Colossus | `vad.bin` | 5 | `$s4` (fixed single target, not a loop) | Likely dormant |

Max real party size is 6, so any `element` value `>6` makes that specific
instance permanently unreachable ("dormant" rows).

### Multi-target attacks: `battle_enemy_attack_advance_multitarget`

If the attacker's class/equip byte (`class_ptrs[attacker]->+0x1c->+0x4c`)
`== 0x0e` (14, Double-Beat Rune), `battle_execute_enemy_attack`
(`0x800f491c`) sets bit `0x4000` on the attacker's own
`combatant_rec+0x4a`. **`battle_enemy_attack_advance_multitarget`**
(`0x800f7c58`) checks that bit each cycle: if set (and the shared "uses
available" counter at `+0x2c` isn't exhausted), it advances `TargetIdx` to
the next valid combatant and signals "continue."
**`battle_enemy_attack_multitarget_continue`** (`0x800f5cd0`) is the
per-tick driver: it re-invokes `battle_execute_enemy_attack` against the
newly-advanced target, repeating until every living combatant has been
attacked once, and plays the animation using script-table slot `[4]`
(rather than the ordinary attack's slot `[1]`).

`scripts/CaptureEnemyMoveResults.lua` captures (move type, target,
damage-per-combatant) for an enemy's turn across candidate seeds given a
savestate positioned at/before that turn. It reports raw
`ActionType`/`AbilitySlot`/`TargetIdx` and observed HP deltas; it does not
compute a predicted damage value from the formula above.

## Monster record layout (`attack_data_table[Id]`, `MonsterRecord`)

| Offset | Field | Notes |
|---|---|---|
| `+0x00` | Name | Charmap-encoded, null/space-padded (same convention as the Rune/Unite tables). |
| `+0x10` | Level (u8) | |
| `+0x11` | Formation-slot occupancy footprint (u8) | See "Formation management" above. |
| `+0x12` | HP (u16) | |
| `+0x14` | PWR (u16) | |
| `+0x16` | SKL (u16) | |
| `+0x18` | DEF (u16) | |
| `+0x1a` | SPD (u16) | |
| `+0x1c` | MGC (u16) | |
| `+0x1e` | LUK (u16) | |
| `+0x20` | Unknown (u32) | Small integers observed (0-4 range). Not an AI-archetype tag. |
| `+0x24` | Unknown (u32) | Same. |
| `+0x28` | Pointer to a 9-entry pointer table | A catalog of this monster's own attack/animation scripts (bytecode for the `play_attack_animation` opcode interpreter). Every monster's own 9 entries are unique — a monster needs several scripts (normal attack, one or more special moves, hit-reactions, death, etc.). |
| `+0x2c` | Pointer | Same kind of data as `+0x28` (script bytecode neighborhood), likely a second, related catalog — possibly hit-reaction/damage-taken scripts. |
| `+0x30` | AI function pointer | The enemy AI action-selection function. |
| `+0x34` | `wGoldDrop` (u16) | Money ("bits") dropped, summed across living enemies at the end of an enemy turn; doubled by Prosperity Rune (see above). Has a bit-0 "compressed large value" branch (`(raw/10)*100` when the low bit is set). |

Neither `+0x28` nor `+0x2c` (nor `+0x20`/`+0x24`) encode which "shape" of
target-scan/move-gate logic a monster's AI uses — that information only
exists in the AI function's own compiled instructions.

## AI/enemy move selection

The AI function pointer at `attack_data_table[Id]+0x30` is invoked from
`battle_dispatch_current_actor_action`. Story-boss and many regular-enemy
AI functions live outside `main.exe`, in each monster's own small overlay,
rather than in a shared generic routine — every boss and regular enemy
traced has its own hand-written AI function, though several reuse the same
target-scan/move-gate templates (see below).

### Target-selection template (used by most monsters)

```
for each party member idx in formation order (1..PARTY_COUNT):
  if formationPos(combatant_rec[idx]+0x44) < 4          -- front 3 slots only
     and combatant_rec[idx]+0x45 == 0                    -- alive/valid
     and not busy(enemy_data[idx]+5):                    -- not mid-reaction
    roll = RNG2()                                        -- advances the shared LCG
    if roll % 100 > 50:                                  -- ~49% accept chance
      target = idx; break
if no target accepted this pass: retry next tick (fresh rolls, nothing carried over)
```

Only the front 3 formation slots are targetable by this template. Dead or
back-row members are skipped at zero RNG cost — no `rand()` call happens
for them. A front-row member who's merely busy is also skipped at zero
cost. Retrying costs extra frames but never extra unaccounted RNG advances.
The formation always keeps at least one living member in the front row
(characters automatically move up from the back row when a front-row
member dies), so this scan can never permanently stall while anyone in the
party is alive.

### Zombie Dragon (`enemy_ai_overlay.bin` / `vb5g.bin`, `0x80012968`)

```
-- Target selection: the shared template above.

-- Move selection, once target is locked:
if roundCounter (battle_base+0x4) == 1:
  move = FireBreath                                      -- guaranteed on round 1
else:
  roll2 = RNG2()
  move = Attack     if (roll2 * 100) // 32767 < 0x47      -- ~71% chance
  move = FireBreath otherwise                             -- ~29% chance
```

`RNG2()` means: advance `Address.RNG` one LCG step, then take `getRNG2` of
the new value — the same shared RNG stream every other system in this game
uses, reached via an indirect cross-overlay call back into `main.exe`
(`*(battle_base+0x1258)` for the target-roll, `+4` for the move-choice
dispatch). Ghidra addresses (in `enemy_ai_overlay.bin`):
`zombie_dragon_ai_select_target_and_move` = `0x80012968`,
`zombie_dragon_ai_await_target_then_fire_breath` = `0x80012b64`.

Ported to `lib/Enemies/ZombieDragon.lua`'s `simulateMoveSelection(seed,
numCandidates, roundCounter)`. The seed to hand it is the RNG state at the
exact frame Zombie Dragon becomes the active actor (not the raw
battle-start seed) — matching every `simulate<X>` function's own convention
of starting right at the decision's first roll.

Zombie Dragon has exactly two attacks: a single-target physical attack,
and Fire Breath, which hits every living party member. The single-target
Attack path goes through the ordinary multi-target mechanism described
above; Fire Breath's actual damage is computed by a separate mechanism —
Zombie Dragon's own `fire_func` subsystem (catalog slot 6 of her 9-entry
attack/script table, distinct from slot 1 = normal attack and slot 4 =
per-hit continuation animation), which calls `calc_rune_element_attack_
damage` directly (see above) rather than going through `calc_damage`. This
subsystem's own tick counter, once past 249 (~4 seconds into the effect),
loops every living party member and applies the MGC-based formula per
target.

### Story boss AI roster

| Boss | File | Address | Target scan | Move |
|---|---|---|---|---|
| Zombie Dragon | `vb5g.bin` | `0x80012968` | front-row only | round 1: Fire Breath guaranteed; else ~71% Attack / ~29% Fire Breath |
| Golem | `va4.bin` | `0x80010ea4` | front-row only | ~71% Attack / ~29% special |
| Gigantes | `vc3.bin` | `0x8001186c` | front-row only | ~51% Attack / ~49% special |
| Shell Venus | `vs1.bin` | `0x800178e4` | front-row only | ~51% / ~49% |
| Sonya Shulen | `vs1.bin` | `0x80018788` | front-row only | ~51% / ~49% |
| Ain Gide | `vac.bin` | `0x80013b1c` | front-row only | ~51% / ~49% |
| Varkas | `va7.bin` | `0x800103b0` | front-row only | always plain Attack (no special move) |
| Pirates (Anji/Kanak/Leonardo — all 3 share this address) | `vb8.bin` | `0x80010004` | front-row only | always plain Attack |
| Neclord (2 appearances, same logic, different compiled addresses) | `ve1.bin`/`ve3.bin` | `0x80013d18`/`0x8001675c` | front-row only | 3 moves: AoE Wind (~49.00%), single-target physical Bats (~26.01%, guaranteed Poison), AoE Lightning (~24.99%) — see below |
| Assassin | `vb5a2.bin` | `0x8001789c` | front-row only | round > 2: always special; else ~51% Attack / ~49% special |
| Sydonia | `va7.bin` | `0x8001234c` | **all 6**, not just front row | fully determined by the *chosen target's* row: front row → always special, back row → always plain Attack |
| Queen Ant (Mt. Seifu's scripted fight, lvl15 HP7000 — distinct from Seek Valley's random-encounter Queen Ant) | `va7.bin` | `0x80010ae0` | none (self/AOE) | resets own HP to full every turn, then ~51.0% her own AoE Earth attack (hits every living party member) / ~49.0% attempts to command every other living enemy to attack — see below |
| Crystal Core | `vf2.bin` | `0x800199c8` | front-row only (unless a global flag is set, in which case no scan at all) | always plain Attack on the scanned branch; unidentified special state on the flagged branch |
| "Dragon" (HP 6000, distinct from Zombie Dragon and from Golden Hydra, the true final boss) | `vc61.bin` (data section; code read from the live overlay dump `dragon_overlay.bin`) | `0x80012594` | front-row only | 2 moves: Lightning (single-target) normally; a per-frame callback rolls ~51%/~49% once a target locks, overriding to Fire Breath (AOE) — see below |

**Golden Hydra** — Level 75, HP 10000, PWR 570, SKL 105, DEF 55, SPD 75,
MGC 420, LUK 80, gold 3392 — is the true final boss (file `vzv.bin`,
`data/15_area.z`), distinct from and much larger than "Dragon" (HP 6000)
and Zombie Dragon (HP 3700). Her overlay has 3 `calc_rune_element_attack_
damage` call sites — more than her 2 known moves, so at least one move
likely has 2 damage phases.

`vc3.bin` hosts multiple monsters: CrimsonDwarf (`0x80010034`) and Gigantes
(`gigantes_ai_select_target_and_move`, `0x8001186c`). Cross-referencing
against `lib/EncounterTable.lua`'s `DWARVES_VAULT` roster ("Death Machine,
Crimson Dwarf, Death Boar, Death Machine") and charmap-searching `vc3.bin`
for those names confirms both Death Machine variants also live in
`vc3.bin` (`0x800420e0`, `0x80043618`).

Sydonia's boss AI (`sydonia_ai_select_target_and_move`) schedules a
counterattack structure after her special move — the party member she just
hit would strike back at her — gated on a bit in `enemy_data+0x40` that
only `anim_op_set_effect_flags` (opcode 26, `0x800e4fd8`) can set, using a
mask read from the invoking script's own embedded data. Opcode 26 never
appears in Sydonia's own special-move script (`0x800700c0`), so her own
attack can never arm this counter — it never triggers in game. This is
distinct from the player-side "Bandit Attack" Unite (`DAT_8016d18c` slot
18, same Varkas+Sydonia pairing), whose own resolved script address
(`DAT_8016d2d0[18]` = `0x800fcd1c`, in `main.exe`) doesn't match either
script address referenced in Sydonia's boss AI. This counter structure is
genuine but dead/leftover code, never wired to a real trigger.

### Dragon's move selection

Dragon has exactly two moves — Lightning (single-target) and Fire Breath
(AOE, hits every living party member):

```
loop:
  for slot in eligible front-row candidates (formation order):
    roll = rand()
    if roll % 100 > 50: target = slot; break        -- ~49% per candidate accepts
  if no candidate accepted: continue loop             -- retry the WHOLE scan fresh, new rolls
  else: break                                          -- target locked
roll = rand()
quotient = (roll * 100) / 32767
if quotient < 51:  Lightning, using `target`            -- ~51% chance
else:              Fire Breath (AOE), target ignored     -- ~49% chance
```

**Target-selection eligibility** (`dragon_ai_select_target_and_move`,
`dragon_overlay.bin @ 0x80012594`): the loop walks every party member in
formation order; only a member that is alive (`combatant_rec+0x45 == 0`)
and in the front row (`formationPos < 4`) and not busy (`enemy_data+5 ==
0`) gets a roll.

**The move-choice roll** happens in **`dragon_special_move_real_frame_
callback`** (`dragon_overlay.bin @ 0x800123b8`) — Dragon's own per-frame
animation callback, installed at `enemy_data[Dragon]+0x54` and invoked
every frame by `main.exe`'s `FUN_800e358c` once the windup completes. It's
a small state machine keyed on `enemy_data[self]+0x42`:

```
state 0:  allocate an 8-byte scratch block, zero it, advance to state 1
state 1:  THE ROLL - rand(), (raw*100)/32767 < 51 -> store dragon_lightning_path (0x80013264);
          else -> store dragon_firebreath_path (0x80012808); advance to state 2
state 2:  call whichever continuation was stored
state 99: cleanup (free the scratch block, clear the callback slot)
```

Same formula shape and divisor (`0x7fff`) as Zombie Dragon's own
Attack-vs-Fire-Breath roll, with a different threshold (51 here vs. Zombie
Dragon's 71). `dragon_lightning_path` allocates a 244-byte VFX buffer;
`dragon_firebreath_path` allocates 300 bytes. The 3 `calc_rune_element_
attack_damage` call sites in this overlay
(`dragon_special1_damage_call_element8_dormant` at `0x800113bc`,
`dragon_special2_damage_call_element1_LIVE` at `0x80012eec`, both
loop-shaped, consistent with Fire Breath's AOE hit pattern;
`dragon_special3_damage_call_element4_uncertain` at `0x800139e8`,
single-hit-shaped, consistent with Lightning) are reached further
downstream of `dragon_lightning_path`/`dragon_firebreath_path`.
Elemental-resistance "slot bug" status: `element=8` is permanently dormant
(can never match a 1-6 party index); `element=1` is live (slot 1 is always
populated, so an unhandled Rune there takes half damage from Fire Breath).

`lib/Enemies/Dragon.lua` models this as two functions matching the two
real phases: `simulateMoveSelection` (target-scan-with-retry + move-choice
roll) and `simulateLightning` (the VFX/particle phase below, taking the
seed `simulateMoveSelection` returns once resolved to Lightning).

#### Lightning's RNG cost

After the target-selection and move-choice rolls resolve to Lightning, the
attack proceeds through three phases:

1. **A 128-tick particle-spawn phase.** 30 independent "spark" line-segment
   particles each respawn (5 `rand()` calls each — X-offset, Y-offset, an
   unused point-B Z-offset, a Z-velocity, and a lifetime) whenever
   inactive, via `vfx_spawn_random_arc_particle` (`main.exe @ 0x80124040`,
   `RngCallbackTable` slot `0xe8`). A particle deactivates when either its
   random lifetime (`rand() % 0x46`, i.e. 0-69 ticks) expires, or its
   position — integrated every active tick by a random negative Z-velocity
   (`-(rand() % 5 + 5) * 4096`) inside the otherwise-RNG-free render
   function (slot `0xec`) — crosses below a fixed `-300` threshold,
   whichever comes first. The total varies because this is a real
   stochastic process (each particle's own random lifetime/velocity
   determines how many times it gets to respawn across the 128 ticks).
2. **A 124-tick phase with no further particle RNG.**
3. **Exactly one final `calc_rune_element_attack_damage` variance roll**,
   ending the attack.

Observed totals (VFX-phase calls only) range from 651 to 759 across a
16-seed sample — roughly an order of magnitude higher than naive
per-frame-polling would suggest, because many `rand()` calls can land
within a single frame's CPU execution and get collapsed into "one change"
by naive polling; the reliable method is to let the RNG **settle**
(unchanged for 30 consecutive frames) after the attack fully resolves, then
recover the exact call count by forward-simulating (LCG-step-counting)
from the start seed until it reaches that settled value.

`lib/Enemies/Dragon.lua`/`dragon_lightning_tick_state_machine`'s plate
comment (`dragon_overlay.bin @ 0x80013690`) has the full derivation;
`tests/test_Dragon.lua` for the test vectors (50 seeds for move-selection,
16 for the Lightning VFX).

#### Dragon's damage formula

Both Lightning and Fire Breath call the shared `calc_rune_element_attack_
damage` (`main.exe @ 0x800f8174`, `RngCallbackTable` slot 86) documented
above — not a separate formula. Both moves are MGC-based, not ATK-based
(Dragon's own `CombatantRec` has distinct `ATK=250` / `MGC=150`).

**Lightning** (`dragon_lightning_tick_state_machine`'s own inline call, the
final roll in the RNG-cost section above) passes `element=4`, no further
scaling beyond the shared formula's own rune-category halving.

**Fire Breath** (`dragon_special2_damage_call_element1_LIVE`,
`0x80012eec`) passes `element=1`, looping over all 6 party members, and
additionally halves the result unconditionally afterward (`iVar2/2`) — a
second, deliberate AOE-damage-reduction step on top of any elemental
halving, not present in Lightning's single-target path. Fire Breath also
carries the register-reuse resistance bug documented above: Dragon's Fire
Breath loop starts at 1 and passes `element=1`, so the bug hits slot 1 —
whichever party member occupies the first position in the hit order gets
an extra accidental 50% reduction if their rune isn't one of the explicit
cases, on top of the unconditional AOE halving.

`lib/Enemies/Dragon.lua`'s `calculateLightningDamage` /
`calculateFireBreathDamage` reuse `lib/EnemyElementalAttack.lua`'s existing
`calculateDamage`/variance primitives.

### Neclord (`ve1.bin`/`ve3.bin`)

Neclord's Castle fight (`ve3.bin`, HP 7500): monster record at
`0x8009ddc8` (`+0x30` = the AI function pointer, `0x8001675c`) — HP 7500,
PWR 450, DEF 80, MGC 275, SPD 75, SKL 100, LUK 30, level 55.
Target-selection (`neclord_ai_select_target_and_move`, `0x8001675c`) uses
the same template as every other monster (front-row scan, `roll%100>50`
accept, retry fresh on total reject).

Move choice, in the continuation `neclord_special_move_windup`
(`0x800168dc`): after a busy-wait gate, two sequential
`(roll*100)/32767 < 0x33` (~51%) rolls pick one of three attack scripts.
RNG2 is uniform over 32768 values; `quotient < 51` iff `roll ≤ 16711`
(16712/32768 values): `p = P(roll < 51%) = 16712/32768 = 0.510010`, `q =
P(roll ≥ 51%) = 16056/32768 = 0.489990`. Wind is picked outright on the
first roll's `q` branch; only the `p` branch spends a second roll to split
Bats vs. Lightning:

- **Wind** (`DAT_8009e078`) = `q` = **48.999% ≈ 49.00%**
- **Bats** (`DAT_8009e128`) = `p × p` = 279,290,944/1,073,741,824 = **26.011%**
- **Lightning** (`DAT_8009e0cc`) = `p × q` = 268,327,872/1,073,741,824 = **24.990%**

(sums to exactly 1 algebraically: `q + p² + pq = q + p(p+q) = q + p = 1`.)

Three genuinely different attacks:

- `DAT_8009e078` (~49%) → `neclord_wind_tick_state_machine` (`0x80016d14`):
  a 4-state tick handler (windup with knockback + sound cue `0x813`, then a
  hit-reaction script dispatch on every living party member followed by
  `calc_rune_element_attack_damage`, `element=5` (Wind/Cyclone) +
  `apply_hp_damage_display` per living target) — AOE, loops all 6
  combatant slots.
- `DAT_8009e0cc` (~25.5%) → its own tick machine (damage call site
  confirmed at `0x800177c0`): the same `calc_rune_element_attack_damage`
  call, `element=4` (Lightning/Thunder) — also AOE, same loop shape as
  Wind.
- `DAT_8009e128` (~25.5%) → `neclord_bats_tick_state_machine`
  (`0x80017f88`): a 7-state handler managing 20 spawned bat particles
  (`RngCallbackTable` slot `0xA4`, particle allocation) converging on the
  target, ending in a call to `RngCallbackTable` slot `0xC` = `0x800f7e90`
  = `calc_damage`, the ordinary physical ATK-DEF formula — single-target,
  using the locked `TargetIdx` directly rather than looping all 6.

**Bats' RNG advancement and poison**: total 86 `rand()` calls for a Bats
attack, broken down as 2 target-scan + 2 move-choice + 60 + 20 + 1 + 1:
- **Bat spawn setup** (`0x80017cd0`): for each of 20 spawned bat
  particles, (a) `RngCallbackTable` slot `0x120`
  (`main.exe @ 0x80123054`): a "random point in a sphere" position
  generator using exactly 3 `rand()` calls per bat = 60 calls total; (b)
  one direct `rand() % 60` "animation phase-offset" roll per bat = 20
  calls total.
- **Damage**: `calc_damage`'s own 1 internal variance roll.
- **Poison**: `neclord_bats_tick_state_machine`'s state 1, once its own
  63-tick converge timer elapses, dispatches a second script
  (`0x8009e1b8`) onto the target via `play_attack_animation` — a repeated
  red-flash + pad-rumble + wobble "bat bite" sequence, then calls opcode 40
  (`anim_op_roll_status_effect_chance`) with `status_id=0` (Poison) and
  `chance_arg=100` — a guaranteed application. The roll still consumes 1
  `rand()` call even at `chance_arg=100`.

Ported to `lib/Enemies/Neclord.lua`'s `simulateMoveSelection`/
`simulateWind`/`simulateLightning`/`simulateBats`, and
`calculateWindDamage`/`calculateLightningDamage` (reusing
`lib/EnemyElementalAttack.lua`'s primitives) /
`calculateBatsDamage` (the ordinary physical ATK-DEF formula, pre-Defend-
halving — callers apply that check themselves).

### Regular (non-boss) enemy AI

Ordinary field encounters use the same hand-scripted-per-monster AI shape
as story bosses, not a shared generic routine, though many reuse the same
templates. **CrimsonDwarf** (`vc3.bin` @ `0x80010034`), **Colossus**
(`vad.bin` @ `0x80010918`), **DevilArmor** (`vc6.bin` @ `0x80011638`),
**DevilShield** (`vc6.bin` @ `0x80010a78`), **GiantSnail** (`va8.bin` @
`0x8001115c`) all use the front-row-only target-scan template, differing
only in the post-selection move: CrimsonDwarf/Colossus/GiantSnail always
plain Attack; DevilShield uses the same `0x33`-threshold move-gate template
as several bosses; DevilArmor counts eligible targets and unconditionally
jumps to a "special" path if any exist. None of these read `+0x11`.

Per-area data files (`NN_area.X`/`X_data.bin`, e.g. `b_data.bin`,
`h_data.bin`, `g_data.bin`) load at runtime base `0x80080000`, not
`0x80010000` like the boss-specific `vXX.bin` overlays.

**Killer Rabbit** (`b_data.bin`, area B, `Id=1`, Level=10, `+0x11=0`) has
genuine long-range targeting: `killer_rabbit_ai_select_target_and_move`
(`b_data.bin @ 0x80080664`) rolls RNG2, and if `>50%`, picks `target =
RNG2 % partyCount + 1` — a raw index into all party members with no
formation-row check at all (every other monster's scan gates on
`combatant_rec+0x44<4`). Validates the pick via two callbacks (one of
which, `killer_rabbit_ai_prepare_leap_special` @ `0x80080988`, duplicates
sprite/animation data, consistent with a leaping/jumping special move),
then commits to it as a "can hit the back row" special attack. Otherwise
falls through to the ordinary front-row-only scan + plain Attack. This
back-row reach is hardcoded directly into the compiled branch logic
(skipping the formation check outright for the special move), not driven
by any per-monster data byte — `+0x11` is not read anywhere in
`b_data.bin`.

**Slasher Rabbit** (`va8.bin` @ `0x800108c0`
`slasher_rabbit_ai_select_target_and_move`, plus `0x80010be4`
`slasher_rabbit_ai_spawn_leap_clone`; record at file offset `0x3a5c4`,
stats HP=60 PWR=65 SKL=30 DEF=10 SPD=29 MGC=6 LUK=6, gold=70): shares
Killer Rabbit's exact leap-clone template — `>50%` RNG2 roll picks a raw
party index (no formation-row check) and spawns a duplicate enemy-slot
"clone" to execute the leap hit; otherwise falls back to the standard
front-row-only scan + plain Attack.

**Rabbit Bird** (`h_data.bin` @ `0x80080038`
`rabbit_bird_ai_select_target_and_move`; record at file offset `0x1f6d4`;
stats HP=300 PWR=305 SKL=110 DEF=50 SPD=60 MGC=160 LUK=110, gold=2200):
plain front-row-only scan template, but normalizes its RNG roll as `roll %
100` directly rather than the `(roll*100)/0x7fff` scaling seen elsewhere.

**Dagon** (`g_data.bin` @ `0x80080338` `dagon_ai_select_target_and_move`,
plus `0x80080254` `dagon_ai_await_animation_then_special`; record at file
offset `0x1e420`): front-row scan plus a second independent roll gate for
a special move, matching DevilShield's `0x33`-threshold move-gate
template.

## Queen Ant (Mt. Seifu, `va7.bin`)

Queen Ant (`va7.bin`) is the boss of a scripted fight accompanied by 3
Soldier Ants (distinct from Seek Valley's separate random-encounter Queen
Ant). Her own per-tick function, `queen_ant_ai_self_heal_and_select_move`
(`0x80010ae0`), does three things every turn, unconditionally: dispatches a
script onto herself, resets her own roll-gate countdown, and resets her own
current HP to max. Then one roll, `(roll*100)/32767 < 0x33`, splits into
two branches — brute-forced over the full RNG2 output range (0-32767, not a
modulo/hash that could bias the split): **AoE Earth = 2089/4096 =
51.0010%**, **CommandAnts = 2007/4096 = 48.9990%**.

- **AoE Earth** (`queen_ant_own_attack_windup` → `_wait_and_arm` →
  `_finish` drive the busy-wait/animation-sync scaffolding; the actual
  damage call is in a separate coroutine,
  `queen_ant_aoe_earth_cast`/`queen_ant_aoe_earth_damage_loop`
  (`0x80011900`/`0x80011c60`), reached via a raw callback install) — loops
  every living party member, calling `calc_rune_element_attack_damage
  (Queen Ant, target, element=3/Earth)` + `apply_hp_damage_display` for
  each; every target gets an independent roll off their own MGC/DEF/RuneId
  (not one shared value copied to everyone). No slot-based register-reuse
  bug is present in this loop — targets take the plain neutral formula
  result (matching Soldier Ant's own already-known stats). Queen Ant's own
  MGC is read at `+0x1c` in this fight's combined combatant array (this
  encounter's enemy-side records use a distinct layout from the party
  layout's `+0x2c`).
- **CommandAnts** (`queen_ant_command_all_ants_attack`, `0x80010edc`,
  reached through a small counter gate): fully deterministic, zero
  `rand()` calls in any code path — loops every enemy slot, commands every
  idle (`ActionTag==0`), non-busy one; for each, walks every party slot
  1..N keeping the last (highest-numbered) candidate satisfying alive +
  not-busy + state code `<4` as the target. In practice this branch is a
  no-op: turn order (see [Turn_Order.md](./Turn_Order.md)) picks the next
  actor by `weight = SPD*10 - 5 + rand()%10` among everyone who hasn't yet
  acted. Soldier Ant's SPD=22 gives weight range `[215,224]`; Queen Ant's
  SPD=20 gives `[195,204]` — these ranges never overlap, so every living
  ant is guaranteed to take its own independent turn before Queen Ant's
  turn ever comes up. By the time she rolls CommandAnts, every
  still-living ant already has `ActionTag=1` from its own turn, failing
  this function's own eligibility check for all of them —
  `queen_ant_command_all_ants_attack`/`ant_commanded_attack_damage`
  (`va7.bin 0x800110d8`) has never been observed to actually fire.

**Soldier Ant** (`va7.bin @ 0x800106b0`
`soldier_ant_ai_select_target_and_move`; monster record at `0x8006500c`:
level 4, HP 28, PWR 48, SKL 18, DEF 10, SPD 22, MGC 0, LUK 6; also part of
Mt. Seifu's random-encounter roster) is what actually produces every ant
attack in this fight: the standard target-scan template, then one
move-choice roll — brute-forced exactly: **Attack = 1577/2048 = 77.0020%**,
**DoubleStrike = 471/2048 = 22.9980%**. Attack falls back to the generic
`apply_uncovered_attack_damage`/`battle_execute_player_attack` resolver (a
single `calc_damage` roll, no elemental scaling).
`soldier_ant_special_double_strike` (`0x80010524`) is a single `calc_damage`
roll, physical, with the result simply doubled (`damage << 1`) before
applying — the doubled roll can exceed a target's own max HP.
`lib/Enemies/SoldierAnt.lua` models both branches;
`lib/Enemies/QueenAnt.lua` models `calculateAoeEarthDamage` (no slot-bug
logic) and the move-selection formula above.

Formation for this fight: exactly 5 party members + 3 Soldier Ants + Queen
Ant (9 combatants total).

### Queen Ant's round-3 battle-end and ant-respawn mechanic

`BattleState+0x1330`/`+0x1334` (the scripted-turn-override hook) is armed
for this encounter, pointing at **`queen_ant_end_of_round_callback`**
(`va7.bin @ 0x8001139c`), which does two things:

1. **Wait-for-everyone gate**: scans every combatant (party + enemies) for
   anyone who hasn't acted this round yet (`ActionTag == 0`) — returns
   immediately (no-op) if so, so the rest of the function only runs once,
   right as a round finishes.
2. **The 3rd-turn battle-end trigger**: once everyone's acted,
   `if (dwRoundNumber > 2) { SyncSignals+4 (BattleState+0x34) = 1; }`.
   `SyncSignals+4` is the same flag `battle_process_round_end_status_and_
   formation`'s own phase-4→5 cleanup sequence checks to trigger its
   larger reset/wrap-up sequence. It is better understood as a general
   "force a full round-state resync now" signal rather than literally "end
   the battle" by itself (see the Ted-vs-Queen-Ant encounter below, which
   sets the same flag for an unrelated purpose) — it plausibly leads to the
   battle ending here, via a generic coroutine-state write not itself
   traced further.
3. **Ant-respawn**: unconditionally (every call, any round), the same
   function also scans every enemy slot for one that's dead/removed and
   not busy, and fully revives it — HP restored to max, marked valid
   again, a spawn animation played. This is Queen Ant's "keeps spawning
   more ant adds during the fight" behavior.

### The scripted Ted-vs-Queen-Ant "forced Hell cast" fight

A separate scripted 1v1 encounter (`dwPartyCount=1`, `dwTotalCombatants=2`:
Ted at `55/55` HP, Queen Ant at `7000/7000` HP) also uses the
`+0x1330`/`+0x1334` scripted-turn-override hook, for a different purpose:
forcing Ted's own action (`ActionType=2`/Rune, `AbilitySlot=3`,
`TargetIdx=2`/Queen Ant — a forced Rune-level-3 cast, Hell, at Queen Ant)
with zero player input, via a 3-stage callback chain in `va7.bin`:

1. **`scripted_forced_turn_delay_arm`** (`0x800101c8`): sets a fixed
   countdown (`0x800716b8 = 0x3c`, 60 ticks ≈ 1 second, a dramatic pause
   before the forced cast plays), schedules the next stage.
2. **`scripted_forced_turn_delay_tick`** (`0x800101e8`): decrements the
   countdown each tick, returning nonzero (a no-op "keep waiting" signal to
   `battle_advance_turn`) until it reaches 0, then schedules the final
   stage.
3. **`scripted_forced_turn_commit`** (`0x80010220`): forces
   `g_nPendingIndex(+0x3420) = 1` (Ted, bypassing the normal weighted-RNG
   roll entirely), disarms the hook (`+0x1330=0`, `+0x1334=0`), sets
   `SyncSignals+4(+0x34) = 1` (a general resync signal in this context,
   not an "end battle" flag), and marks every other combatant's
   `ActionTag = 1` ("already acted") so the very next roll trivially
   resolves to Ted.

None of these 3 functions write Ted's `ActionType`/`AbilitySlot`/
`TargetIdx` themselves — those are set by this encounter's own initial
setup data before this chain even runs (analogous to how Queen Ant's own
encounter setup populates `EnemyData` via `battle_init_apply_scripted_
encounter_callback`/`FUN_800dee44` in `main.exe`, but for a different
per-encounter table).

Together, the two Queen-Ant-adjacent encounters show the
`+0x1330`/`+0x1334` hook is a general-purpose scripted-turn-override
mechanism reused for at least two distinct narrative purposes: ending a
fight on a round threshold, and forcing a specific character's specific
action with no input.

## How spells call RNG: the cast state machine

`apply_elemental_multiplier` itself has no RNG — but a spell *cast* is not
just that one call. Each spell's `DAT_8016d33c[id]+0x1c` field is a code
pointer into a per-spell entry function that schedules a multi-phase,
per-tick state machine (a heap-allocated context struct, phase counter
driving a `switch`) — the same tick-resumable-coroutine pattern used
elsewhere in this codebase (e.g. `battle_advance_turn`). Every spell traced
so far follows the same 3-function shape
(`spell_<name>_cast_entry` → `_vfx_setup` → `_tick_state_machine`), and in
every one, the phase that actually applies damage
(`apply_elemental_multiplier(level, element, target, attacker, base_power)`)
has zero RNG calls — the entire `rand()` cost of a cast is VFX/audio
polish (particle scatter, impact sound variety, screen shake), unrelated to
the damage number itself. See
[Spell_RNG_Tracing_Methodology.md](../../notes/Spell_RNG_Tracing_Methodology.md) for
the repeatable tracing process; this section only records the per-spell
results.

Duration numbers below come from summing each phase's hardcoded tick-count
immediate and dividing by 60 (NTSC fps). Two spells (Shining Wind, Hell)
run part of their state machine at non-1:1 tick:frame ratios (a
rendering-load quirk); their listed duration is the real measured span, not
the naive tick-sum.

| Spell | Element | Base power | Phase ticks | Total ticks (≈s @60fps) | RNG-call total |
|---|---|---|---|---|---|
| Explosion | Fire (Lv4) | 700 | not fully broken down | — | ~70 setup + more in impact phase |
| Earthquake | Earth (Lv4) | 700 | 64+64+128+64 | 320 (~5.3s) | seed-dependent, 1519–1786 range (mean ~1649) |
| Charm Arrow | Resurrection (Lv4) | 500 | 64+32+64+64 | 224 (~3.7s) | 24436 for the validated seed (core 64-tick phase) |
| Flaming Arrow | Fire (Lv1) | 100 | 64+96+74+60 | 294 (~4.9s) | 512 for the validated seed |
| Dancing Flames | Fire (Lv3) | 400 | 64+32+64+77+192+64 | 493 (~8.2s) | fixed 150, always |
| Shining Wind | Wind (Lv5) | 500 | 64+32+64+160+64 | 384 raw (~9s real, case3 runs at half framerate) | 1302 for the validated seed |
| Storm Fang | Earth+Wind combo | — | not decompiled past setup (provably zero RNG) | ~360 real frames | fixed 38, always |
| Hell | Dark (Lv4*) | 2 (instant-death) | 64+32+128+? | ≥224 ticks, real-frame span varies 260–318 by battle context | seed-dependent, ~10320–12220 across 20 seeds |
| Black Shadow | Dark (Lv2) | 300 | 64+32+80+? | ≥176 ticks | seed- and per-savestate-residual-dependent — see below |

### Earthquake

Setup (`spell_earthquake_vfx_setup`) costs ~100 fixed `rand()` calls (20
particles × 4 for position/velocity, + 20 × 1 for a second pass). The
128-tick phase's shared per-tick epilogue costs one `rand()` per currently-
active particle (of 20), jittering its velocity/drift; a particle only goes
inactive once its X-position crosses a fixed threshold. Particles activate
via `vfx_activate_and_position_particle` (`FUN_80122eb4`, shared with
several other spells below) at a staggered spawn tick (`i*2`), costing 2
more `rand()` calls each — one of which sets the particle's random spawn
X-position, which drives the variable *lifetime* (and therefore the
variable total call count) per seed, since velocity itself is a fixed
decay constant. Damage: `apply_elemental_multiplier(4, 2, ..., 700)`.

### Charm Arrow

Uses a different mechanic entirely: a 16384-byte pre-baked gradient/"charm
heart" grid (`lib/CharmArrowGrid.lua`, a fixed template, not randomized).
Only the 64-tick final phase touches RNG: each tick repeatedly draws
`idx = rand() % 16384` and decays `grid[idx]` on a hit (zeroing a
nonzero-and-<16 cell, or masking a ≥16 cell to its low nibble; an
already-zero cell is a wasted retry) until exactly 160 successes land that
tick. Since successes remove occupancy over time, later ticks need more
retries — call count ramps from 286 (tick 1) to 608 (tick 64) for the
validated seed. Damage: `apply_elemental_multiplier(4, 5, ..., 500)`. The
observed "tail" after the cast (~12–16 calls) is two things: a fixed
10-call block (`battle_select_enemy_target` rerolling once per still-
eligible combatant as 4 Defending party members drop out one by one) plus a
variable 2–6 calls (whoever's action wins the next roll) — neither is Charm
Arrow's own cost.

### Flaming Arrow

20 particles, all starting inactive. Phase 1 (96 ticks, fixed) respawns any
inactive particle every tick via `spell_flamingarrow_spawn_particle`
(4 `rand()` calls: spawn position, an unused Z roll, a randomized velocity
scale `(rand()%64)+128`, a `rand()%100` lifetime). Despawns on lifetime<1
or `|trail_x>>12|<5`. `trail_x` is written as `trail_x & 0xfff |
(new_high_bits<<12)` — preserving stale low-12 residual bits rather than
zeroing them; a raw pre-cast dump of `FlamingArrow.State` shows 3 of 20
slots carry nonzero leftover garbage (baked into the simulator as
`RESIDUAL_LOW12`). No damage-side RNG (no elemental scaling call site is
listed for this one at Lv1 — see the 21-caller table).

### Dancing Flames / Storm Fang (fixed constants, no seed dependence)

Dancing Flames: 15 embers, 2 `rand()` calls each at setup (30), then 4 more
identical 30-call reactivation waves in its 192-tick phase (a rhythmic
"flare up, die down" cycle) — 150 total, always.
`simulateDancingFlames()` returns the constant `150`.

Storm Fang (one of the 5 Magic Unite combo spells, Earth+Wind): 76
particles created at setup, the first 38 each cost 1 `rand()` (random
initial height), the rest are deterministic — 38 total, always, and the
entire tick-phase machine afterward has zero RNG.
`simulateStormFang()` returns the constant `38`.

### Shining Wind

Four particle pools (A/B/C/D, 20/20/30/20 objects), 120 `rand()` calls at
setup (all frame 0). Case 2: pools C+D activate together (all start
inactive) for a one-time 300-call burst. Case 3 (160 ticks) is the complex
part: Pool B fires once per object on a staggered schedule, checked in the
phase body (before the tick counter increments). Pool A uses the same
staggered schedule but is checked in the shared epilogue (after the
increment — a one-tick offset from B) and does not gate on "already
active" — it can numerically re-cross its own decaying countdown against
the ever-increasing tick counter and refire an already-active object,
producing a chaotic-looking but fully deterministic re-trigger pattern.
Pools C/D simply reactivate whenever inactive (6 `rand()` calls each). A
boundary quirk: case 3's own final tick (159) clears all pool-enable flags
before the shared epilogue runs, so nothing new can activate that exact
tick even though decay/process steps for already-active objects still
apply. Case 3 also runs at roughly half real framerate (a rendering quirk,
not an RNG-mechanism difference), which is why its real-frame duration
doesn't match its raw tick count. Damage: `apply_elemental_multiplier(5, 4,
..., 500)`.

### Hell and Black Shadow (Soul Eater family)

Both reuse the same 40-slot particle-vortex spawn function,
`spell_hell_spawn_particle` (`0x801137dc`, 4 `rand()` calls per respawn:
X circle-point, an unused Z roll, velocity scale `(rand()%64)+128`,
lifetime `rand()%120`), and both have a fixed-length RNG-consuming phase
(Hell: 128 ticks; Black Shadow: 80 ticks) — seed only affects *where*
particles spawn and how long they survive, never the tick count itself.
Each tick, a global `scaleAccum` value advances by a fixed step (a
deterministic vortex-rotation accumulator) and gets frozen into a
particle's `scale` field the moment that particle survives a tick — so a
particle's *first-ever* spawn uses whatever was already in its slot's
`scale` field, but every respawn after that uses the frozen `scaleAccum`.

**Hell's** 40-slot `scale` constant table is genuine spell-wide static
data, byte-identical across savestates — so Hell's total is a pure
function of the starting seed (~10320–12220 across 20 seeds). **Black
Shadow's** same field is uninitialized, stale VFX-pool memory that differs
per savestate — Black Shadow's RNG cost is not a pure function of seed
alone; it needs a one-time live capture of the per-savestate residual
table, which is exactly what
[Black_Shadow_Simulation_Workflow.md](../../notes/Black_Shadow_Simulation_Workflow.md)'s
tooling automates. `simulateBlackShadow` takes that table plus the
starting `scaleAccum` as explicit parameters; `simulateBlackShadowWind`/
`simulateBlackShadowBats` wrap two known captures.

Damage: Hell `apply_elemental_multiplier(4, 7, ..., 2)` (instant-death,
power is a non-HP sentinel); Black Shadow `apply_elemental_multiplier(2, 7,
..., 300)`.

`simulateHell`/`simulateBlackShadow` in `lib/Magic.lua`,
`TestHell`/`TestBlackShadow` in `tests/test_Magic.lua`.
