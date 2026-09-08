# Battles and Random Encounters

Covers random-encounter generation, the enemy-group/encounter-table memory
layout, "in battle" detection, and the Battles module's simulation tools.
See [RNG.md](./RNG.md) for the underlying RNG algorithm and
[Zones_Areas_and_Rooms.md](./Zones_Areas_and_Rooms.md) for how areas map to
encounter tables.

## Addresses

| Address | Name | Meaning |
|---|---|---|
| `0x1B9BBC` | `GAMESTATE` | Current gamestate byte |
| `0x1B9BB8` | `PREV_GAMESTATE` | Previous gamestate byte (disambiguates entering a Battle/Event from World Map vs. Overworld) |
| `0x1B8000` | `AREA_ZONE` | Sub-area/room zone index |
| `0x1B8001` | `SCREEN_ZONE` | Screen/room sub-index |
| `0x1B8002` | `WM_ZONE` | World-map region index |
| `0x17159D` | `ENCOUNTER_RATE` | Raw overworld encounter-rate byte (capped by the area's own max — see below) |
| `0x9010` | `RNG` | Live 32-bit RNG seed |
| `0x1B9BC0` | `EVENT_ID` | Determines the expected RNG-reset value after cutscenes/loads |
| `0x197F10` | `ENEMY_GROUP_PTR` | Pointer to the current enemy-group struct in an active battle |
| `0x197F14` | `ENCOUNTER_TABLE_PTR` | Pointer to the current area's runtime encounter table (array of pointers to enemy structs) |
| `0x16765C` | `ITEM_NAME_PTR_1` | Base of the item-name pointer table |

Gamestate enum (`lib/Enums/Gamestate.lua`):

```
TITLE = 0, WORLD_MAP = 1, OVERWORLD = 2, BATTLE = 3, EVENT = 4, GAME_OVER = 99
```

## Encounter roll

Evaluated once per RNG advance in `lib/Encounter.lua:isPossibleBattle(rng, isWorldmap)`,
using `rng2 = getRNG2(rng)`:

- **World Map**: `res = rng2 mod 256`; a battle candidate exists if `res < 8` (~3.1% per tick).
- **Overworld/dungeons**: `res = floor(rng2 / 0x7f) & 0xff`; a battle candidate exists if `res < 4`.

The division by `0x7f` (127) for overworld, instead of a power-of-two mask
like the world-map path, is unexplained in any comment and looks like it
mirrors the original PS1 assembly rather than being an arbitrary tool design
choice.

### Encounter rate gating

A candidate battle is only valid if `battle.encounter_roll < game_state.EncounterRate`
(`Worker:isValidEncounter`, `modules/Battles/worker.lua`):

- **World Map**: `EncounterRate` is a **hardcoded constant, `8`** — not read
  from any memory address. This means `Address.ENCOUNTER_RATE` is only ever
  meaningful for Overworld areas, and the `res < 8` roll above is effectively
  the only gate on the world map.
- **Overworld**: `EncounterRate = min(memory ENCOUNTER_RATE value, area's own encounterRate cap from EncounterTable.lua)`.
  Since `res` only ranges 0–3, a rate of `1` means only `res==0` triggers a
  fight, `2` allows `res<2`, etc. (values seen in `EncounterTable.lua`: 2, 3, or 4).

## Which enemy group spawns — the Champion Rune / "Champ Val" mechanic

Each area entry in `lib/EncounterTable.lua` has parallel arrays `champVals`
and `encounters` of equal length (positionally paired: `champVals[i]` is the
level-sum ceiling for `encounters[i]`).

1. `EncounterLib.getEncounterIndex(rng, tableSize, rng2)` picks an index into
   the encounter table: `divisor = floor(0x7fff/tableSize); index = floor(rng2/divisor) + 1`
   (clamped to `tableSize`) — the 15-bit RNG2 value is uniformly bucketed
   across however many encounter-group entries the area defines. This is
   precomputed for every known table size and stored in the RNG lookahead
   buffer (see [RNG.md](./RNG.md)).
2. If `game_state.IsChampion` (a Champion Rune, rune id `24`, is equipped by
   any party member — `lib/Party.lua:isChampionsRuneEquipped`), the candidate
   is only valid if `game_state.PartyLevel <= game_state.ChampVals[encounter_table_index]`.
   `PartyLevel` is the **sum** of all active party members' levels, not an average.
3. If the Champion Rune is **not** equipped, this level check is skipped
   entirely — any rolled group is accepted.

## Data structures

### `EncounterTable.lua` (per area)

- `name` — display name
- `areaType` — `1` (WORLD_MAP) or `2` (OVERWORLD), reusing `Gamestate` enum values directly
- `encounterRate` — overworld-only cap (absent for WORLD_MAP areas, which default to `8`)
- `champVals` — level-sum thresholds, parallel to `encounters`
- `encounters` — array of 6-character digit strings, one per possible
  enemy-group roll; each digit is a slot (6 enemy slots total), `0` = empty,
  `1..N` = index into that area's `enemies` list. **This digit → enemy
  mapping is never explicitly decoded anywhere in the code** — it's inferred
  by cross-checking digit ranges against `enemies` list lengths per area, and
  is only ever displayed as a raw string in the Battles UI.
- `enemies` — ordered list of enemy names appearing in that area, referenced
  positionally by the `encounters` digit strings

### Runtime enemy-group struct (in RAM, at `ENEMY_GROUP_PTR`)

- byte `0`: `groupSize` (u8)
- bytes `4..9` (6 bytes): up to 6 enemy slot indices into the current area's
  runtime encounter table (`0` = empty slot)

### Runtime encounter table (at `ENCOUNTER_TABLE_PTR`)

An array of 4-byte pointers (1-based, `addr + i*4`) to individual enemy
struct records, terminated by the first invalid pointer
(`Address.isValidPointer` fails). A code comment notes the stored
`encounterTableLength` byte **is inaccurate in Neclord's Castle**, so the
code deliberately walks pointers incrementally instead of trusting it.

### Enemy struct (60 bytes per enemy, `lib/Battle.lua:readEnemyTable`)

`readEnemyTable` reads the struct into a Lua array (`memory.read_bytes_as_array`,
1-indexed: `buffer[1]` is the first byte) and indexes it directly
(`enemyRawData[16]`, etc.) without correcting for Lua's 1-based indexing —
unlike `lib/Characters/Characters.lua`, which has an explicit comment ("All
addresses are offset by 1 because of lua tables starting at 1") and adjusts
for it. The **true memory offsets** (buffer index − 1) are:

| Offset | Field | Notes |
|---|---|---|
| 0–14 | Name | Custom charmap, via `Charmap.readStringFromList` (up to 15 bytes, null-terminated) |
| 15–16 | LVL | big-endian pair |
| 17–18 | HP | |
| 19–20 | PWR | |
| 21–22 | SKL | |
| 23–24 | DEF | |
| 25–26 | SPD | |
| 27–28 | MGC | |
| 29–30 | LUK | |
| 31–51 | *(unaccounted for)* | ~21-byte gap, likely other stats/flags not yet reverse-engineered |
| 52–53 | Bits | EXP/reward value, computed but never consumed elsewhere in the codebase |
| 54–59 | Drops[1..3] | `{id, chance}` pairs, up to 3 drop slots; `id == 0` = no drop. See [Drops.md](./Drops.md) |

Item name lookup: `item_name_addr = mem_u32(ITEM_NAME_PTR_1 + (id-1)*4) & 0x7fffffff`,
then read (24 bytes in the live `lib/Battle.lua:getItemName`; the dead legacy
`helpers/BattleDetector.lua` version reads only 16 bytes — an inconsistency,
not clear which is byte-accurate, though both may simply be over-reads
bounded by null-termination).

## "In battle" detection

The live detection path is `modules/Drops/worker.lua:run()`:

```lua
if StateMonitor.IG_CURRENT_GAMESTATE.current ~= Gamestate.BATTLE then return end
local is_enemy_group_ptr_valid = Address.isValidPointer(StateMonitor.ENEMY_GROUP_PTR.current)
local is_encounter_table_ptr_valid = Address.isValidPointer(StateMonitor.ENCOUNTER_TABLE_PTR.current)
if not (is_enemy_group_ptr_valid and is_encounter_table_ptr_valid) then return end
```

i.e. gamestate `== BATTLE` **and** both pointers read as valid KSEG0 pointers
(`0x80000000..0x801fffff`) — guarding against reading a battle struct on the
exact frame gamestate flips but before pointers are populated. A comment
directly above (`-- This doesn't work. Need to implement delay`) flags that
this guard is *not* considered a fully reliable substitute for an actual
frame delay. `issues.md` also lists "Battle Module sometimes doesn't track
at all, crashes, etc." as an open, unresolved issue.

`helpers/BattleDetector.lua` and `lib/Battle.lua:getEnemyData()` are **dead
code** — both reference `Address.ENEMY_STRUCT_PTR`/`Address.ENEMY_ENC_TABLE_PTR`,
names that don't exist in `Address.lua` (renamed at some point to
`ENEMY_GROUP_PTR`/`ENCOUNTER_TABLE_PTR` without updating these call sites).
Neither is called anywhere in the live module tree; treat them only as
historical artifacts, not documentation of current behavior.

## `StateHandler` (`modules/Battles/StateHandler.lua`)

Not a classic named-state FSM — it's a dual real/custom state holder:

- **Real state** (`updateState()`): populated only when
  `StateMonitor.LOCATION.current` is `WORLD_MAP` or `OVERWORLD` (a no-op for
  `Location.OTHER`, covering BATTLE/EVENT/TITLE/GAME_OVER). Resolves the area
  name via `ZoneInfo`, looks up that area's `EncounterTable` entry, and
  assembles `Location, AreaName, EncounterTable, Enemies, EncounterRate,
  EncounterTableSize, ChampVals, PartyLevel, IsChampion`.
- **Custom state**: a user-editable clone, toggled via
  `toggleCustomState()`/`useCustomState()`/`useRealState()`, letting the user
  override `AreaName`/`PartyLevel`/`IsChampion` independent of actual game
  memory — used to preview hypothetical encounter scenarios for routing.
- `isUpdateRequired()` refreshes state when
  `LOCATION/WM_ZONE/AREA_ZONE/ENCOUNTER_RATE/CHAMPION_RUNE_EQUIPPED/PARTY_LEVEL`
  changed. Note a likely copy-paste bug: the `PARTY_LEVEL` branch is gated on
  `StateMonitor.CHAMPION_RUNE_EQUIPPED` being *truthy* (always true — it's a
  non-nil table) rather than `.changed`, so in practice this branch reduces
  to "party level changed," regardless of whether the Champion Rune is
  actually equipped. Likely harmless in effect, but a real inconsistency
  with the apparent intent.

`modules/Battles/worker.lua` layers a "which RNG-table row is the current/
next battle" tracker on top: it maintains `TablePosition` (an index into
`RNGMonitor`'s precomputed per-location battle-roll table), advances it as
RNG changes, and lets the user jump the live RNG value directly to a chosen
future battle (`jumpToBattle` → `RNGMonitor:goToIndex`).

## Area Selection / Custom State menus

- **`modules/Battles/menus/area_selection.lua`**: browse the full
  `Areas_Random` list and press Cross to set
  `Worker.StateHandler:updateCustomStateArea(selected_area)`, swapping the
  custom state's area/encounter-table/enemies/rate/champVals to that area's data.
- **`modules/Battles/menus/custom_state.lua`**: the main scenario editor —
  Cross toggles custom state on/off; Triangle toggles `IsChampion`; Square
  opens Area Selection; Up/Down/Left/Right adjust `PartyLevel` by ±1/±10
  (clamped to `[1, 594]`, an undocumented magic number, plausibly 6
  characters × 99 max level).

Together these let a researcher/runner simulate "what battle groups would be
valid, at RNG index N, in area X, with the Champion Rune on/off, at total
party level L" — fully decoupled from the actual save state, for planning
routes around desired/avoided encounters.

The top-level `modules/Battles/menus/menu.lua` browses the live/custom
battle table (Up/Down ±1, Left/Right ±10, skipping invalid encounters via
`Worker:isValidEncounter`), and Cross calls `Worker:jumpToBattle`, which
writes the RNG memory value directly to force the emulator to the predicted
battle's pre-roll value.

## Known bugs / limitations (`issues.md` + inline comments)

- After setting a new RNG via the battle selection menu, the RNG monitor
  visibly blinks to a different value for one frame before settling.
- When Champ Val (or other means) filters out all battles, the table
  displays literal `nil` instead of an empty state.
- Battle Module "sometimes doesn't track at all, crashes, etc." — unresolved.
- `modules/Battles/worker.lua`: `findTablePosition`'s RNGIndex shortcut has a
  comment `-- FIX: Sometimes get an error here` (unfixed), and
  `isValidEncounter` has `-- FIX: I sometimes error here when loading saves`
  (unfixed).
- `modules/Drops/worker.lua`'s `isUpdateRequired` has `-- TODO: Handle start
  RNG change` — a starting-RNG change is not currently treated as a reason
  to rebuild battle/drop state.
