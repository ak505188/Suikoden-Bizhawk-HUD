# Zones, Areas, and Rooms

Covers how location is represented in memory at three different
granularities (world-map region, sub-area, and live room/actor data), and
how areas are categorized for encounter purposes. See
[Battles_and_Encounters.md](./Battles_and_Encounters.md) for how this feeds
into encounter-table lookups.

## Area / Zone / Screen / Room — distinct concepts

Three single bytes live contiguously at `GAMESTATE_BASE = 0x1B8000`, read as
one 16-byte buffer each frame by `monitors/State_Monitor.lua`:

| Address | Name | Meaning |
|---|---|---|
| `0x1B8000` | `AREA_ZONE` | Sub-area index inside whatever world-map region the party is in |
| `0x1B8001` | `SCREEN_ZONE` | Finer screen/room-transition tracking within an area |
| `0x1B8002` | `WM_ZONE` | World-map region index (0–11), top-level key into `ZoneInfo` |

`SCREEN_ZONE` is **not** consumed by the main zone-name resolution logic
(only `AREA_ZONE`/`WM_ZONE` feed `ZoneInfo`/`EncounterTable` lookups) — it's
only used ad hoc as an equality check against magic numbers (`0`, `10`) in
one-off scripts (e.g. `scripts/HolyBirds.lua`, as a loading/screen-boundary
signal), so its general meaning across all rooms is unconfirmed.

`ZoneInfo[WM_ZONE]` has a `name` field (the world-map region's own name) plus
`[AREA_ZONE] = AreaName` sub-entries. Resolution logic
(`modules/Battles/StateHandler.lua`):

- If `Location == WORLD_MAP`: area name = `ZoneInfo[WM_ZONE].name` (you're on the overworld map, so only the region matters).
- If `Location == OVERWORLD` (inside a town/dungeon/screen): area name = `ZoneInfo[WM_ZONE][AREA_ZONE]`.

`Location` (`lib/Enums/Location.lua`: `WORLD_MAP`/`OVERWORLD`/`OTHER`) is
derived from the gamestate byte at `Address.GAMESTATE` (`0x1B9BBC`) —
`Gamestate.WORLD_MAP=1`, `Gamestate.OVERWORLD=2`; `OTHER` covers
battle/event/title states where zone data isn't meaningful.

**"Room" is a different, lower-level concept**: not an ID, but a pointer to a
live in-memory struct array of the current screen's dynamic actors — see
below. Area/Zone = the static named location (for encounter-table/story
purposes); Room = the current screen's dynamic actor table.

`lib/ZoneInfoComplete.lua` is a fuller version of `lib/ZoneInfo.lua` (more
`AREA_ZONE` sub-indices filled in per region, e.g. actual town names) but is
**never `require`d anywhere** — only `ZoneInfo.lua` is used, exclusively by
`StateHandler.lua`. It contains a raw-string placeholder
`"Cave of the Past (Inaccessible)"` and a comment `--Not listed in my
spreadsheet`, both signaling unfinished/unverified mapping work.

## Area categories: Forced / Random / Random_Forced / All

Defined in parallel under `lib/Enums/Areas/` (keyed dicts) and
`lib/Lists/Areas/` (flat arrays derived from the dicts — see below).

- **`Areas_Random`** — the 27 areas with an entry in `lib/EncounterTable.lua`
  (a data-driven random encounter table). Confirmed 1:1 against
  `EncounterTable.lua`.
- **`Areas_Forced`** — 18 areas with scripted/one-time story battles, not
  driven by the random encounter table (e.g. Castle, Kouan, Lenankamp,
  Rockland, Pirates' Hideout, Seika, Warriors' Village). Some of these have
  **no** `EncounterTable` entry at all — they can only ever have forced battles.
- **`Areas_Random_Forced`** — the set union `Areas_Forced ∪ Areas_Random`
  (36 entries): "every area where a battle of any kind can happen."
- **`Areas_All`** — the full 55-entry superset, including areas with no
  battles at all (peaceful towns/world-maps, e.g. Antei, Gregminster, Kirov, Lorimar).

An area appearing in **both** Forced and Random (e.g. Pannu Yakuta, Seika,
Shasarazade, Soniere Prison, Toran Castle, Great Forest, Dwarves' Vault,
Magician's Island, Neclord's Castle, and the `WORLD_MAP_*` regions) has both
a random encounter table *and* at least one scripted/forced trigger (e.g. a
boss ambush on the world map, or a mandatory fight partway through a
dungeon). This distinction matters for RNG manipulation/routing: only
`Random`/`Random_Forced` areas are relevant to encounter-rate/RNG-roll
planning, whereas `Forced`-only areas guarantee a battle regardless of RNG state.

### Known bug: `TORAN_CASTLE_DUNGEON`

`lib/Enums/Areas/Areas_Forced.lua` and `Areas_Random_Forced.lua` both set
`TORAN_CASTLE = AREAS_ALL.TORAN_CASTLE_DUNGEON` — but **`TORAN_CASTLE_DUNGEON`
does not exist as a key in `lib/Enums/Areas/Areas_All.lua`** (only
`TORAN_CASTLE = "Toran Castle"` exists), so this evaluates to `nil` in both
enums. `lib/Lists/Areas/Areas_Forced.lua` then compounds this by referencing
`AREAS_FORCED.TORAN_CASTLE_DUNGEON` — a key that was never even defined in
that enum (whose key is `TORAN_CASTLE`) — also `nil`. Net effect: the
"forced battles" list silently contains a `nil` entry where a distinct
"Toran Castle dungeon/interior (forced-only)" area, as opposed to the
regular overworld map (random battles, `areaType=2`, `encounterRate=2`),
should exist. This is a live bug affecting anything that iterates the Forced
or Random_Forced lists, and should be fixed by adding the missing area name
to `Areas_All.lua`.

### `Enums/Areas/*` vs `Lists/Areas/*`

Not duplicates — the **Lists** are mechanically derived flat, ordered arrays
built from the corresponding keyed **Enums** dict, because Lua dicts aren't
indexable/orderable and at least one UI element
(`modules/Battles/menus/area_selection.lua`) needs a cursor-navigable array
to drive a scrolling menu. The Enums are used elsewhere as symbolic
constants for name lookups/equality checks and as table keys into
`ZoneInfo`/`EncounterTable`.

One inconsistency: `Lists/Areas/Areas_Random_Forced.lua` pulls its values
straight from `Enums.Areas_All` rather than from `Enums.Areas_Random_Forced`
(unlike its three sibling List files, which each pull from their
correspondingly-named Enum). It happens to produce the same 36-area set
today (since `Areas_Random_Forced` was verified to equal `Forced ∪ Random`),
but would silently diverge if either underlying enum changed without the
other being updated.

## Room data structure

`Address.ROOM_POINTER = 0x17DAA0` holds a 32-bit KSEG0 pointer (validated via
`Address.isValidPointer`) to the start of an array of fixed-size
actor/NPC structs for the current room/screen. Struct size is `0x18` (24)
bytes:

`modules/RoomInfo/worker.lua` reads this into a Lua array
(`mainmemory.read_bytes_as_array`, 1-indexed: `buffer[1]` is the first byte)
and indexes it directly (`buffer[1]`, `buffer[6]`, `Utils.readFromByteTable(buffer, 7, 2)`,
etc.) without correcting for Lua's 1-based indexing. The **true memory
offsets** (buffer index − 1) are:

| Byte offset | Field | Notes |
|---|---|---|
| 0 | X | u8 position |
| 1 | Y | u8 position |
| 2 | SubpixelX | u8, sub-tile interpolation |
| 3 | SubpixelY | u8 |
| 4 | *(unlabeled)* | Comment: "This isn't actually direction, has some correlation though" — a prior assumption it was facing-direction was disproven |
| 5 | Moves | Comment: "This seems constant, might actually be flag for movement" — uncertain |
| 6–7 | Unknown1 | u16 LE |
| 8–11 | MemAddress1 | u32 LE pointer, purpose undocumented |
| 12–15 | MemAddress2 | u32 LE pointer; dereferencing it (sanitized, then read u8) gives the slot's `Direction` (0–3, matching `lib/Enums/Directions.lua`) — mirrors exactly how the hero's own direction is resolved, implying a shared "character struct" format where the true facing byte lives in a separate, non-contiguous per-character state block |
| 16–19 | MemAddress3 | u32 LE pointer, purpose undocumented |
| 20–21 | Unknown2 | u16 LE |
| 22–23 | Unknown3 | u16 LE |

`MemAddress1`/`MemAddress3` have no documented purpose at all; a
commented-out `MemoryViewer.memoryToStrTbl` call on `MemAddress1` in
`modules/RoomInfo/menu.lua` suggests an abandoned attempt to dig into it.

### Slot count — unverified heuristic

The number of actor slots (`NUM_SLOTS`) is **not** read from a clean,
documented header field. `monitors/Room_Monitor.lua` uses two undocumented,
hardcoded pointer addresses not present in `lib/Address.lua`:
`CANDIDATE_POINTER_1 = 0x199f68`, `CANDIDATE_POINTER_2 = 0x199f94`. Current
formula:

```
NUM_SLOTS = (ROOM_ADDRESS - CANDIDATE_POINTER_2 - 8) // 8
```

(discarded/set to `nil` if negative or non-integer). A commented-out prior
formula used `CANDIDATE_POINTER_1` instead:
`(CANDIDATE_POINTER_1 - 0x8 - ROOM_ADDRESS) / 0x18`, with a comment
*"Didn't work in Grady's Mansion, trying calculation with
CANDIDATE_POINTER_2."* A second, independent value, `NUM_SLOTS_OLD`, is read
as a plain byte at `ROOM_ADDRESS - 0x10` and displayed side-by-side (`N:` vs
`O:` in the RoomInfo worker) — kept for cross-checking, since the two
methods can disagree. **Treat this entire mechanism as an unverified
heuristic, not confirmed memory layout.**

## Hero position/direction

| Address | Name | Meaning |
|---|---|---|
| `0x17BD74` | `HERO_X` | u8, local X coordinate in the current room/screen |
| `0x17BD75` | `HERO_Y` | u8, local Y coordinate |
| `0x17BD7C` | `HERO_DIRECTION_PTR` | u32 pointer (not the direction value itself) — sanitize, then read a single byte at the resolved address for `Direction` (0=DOWN, 1=UP, 2=LEFT, 3=RIGHT, `lib/Enums/Directions.lua`) |

`HERO_X`/`HERO_Y` sit 8 bytes before `HERO_DIRECTION_PTR`, consistent with
all being fields of one hero-state struct starting at `0x17BD74`. The same
pointer-indirection pattern is used for NPC direction via room-slot
`MemAddress2` above, suggesting hero and NPCs share a character-struct format.

The RoomInfo menu's "move NPC in front of hero" feature
(`modules/RoomInfo/menu.lua:moveNPCInFrontOfHero`) uses asymmetric offsets
depending on facing direction (`y+2` for DOWN, `y-1` for UP, `x-2` for LEFT,
`x+2` for RIGHT) rather than a uniform ±1 — possibly reflecting anisotropic
tile/sprite-anchor geometry, but unexplained in any comment.

## RoomInfo module

`modules/RoomInfo/worker.lua` polls `Room_Monitor` and re-derives the full
room actor array each tick, always drawing the hero's X/Y/Direction, the raw
`ROOM_ADDRESS`, and both `NUM_SLOTS`/`NUM_SLOTS_OLD` candidate values
(diagnostic view for the slot-count heuristic above), plus a list of every
slot's index/X/Y/address.

`modules/RoomInfo/menu.lua` is the interactive layer: shows the currently
selected slot with detailed fields (X/Y/Moves, SubpixelX/Y/Direction, all
three raw `MemAddress` pointers, and the "Unknown" fields, all in hex).
Square repositions the selected actor to right in front of the hero; Up/Down
step one slot; Left/Right jump ±10; Circle exits.

In short: RoomInfo is a live memory-inspection/debug tool for the current
room's actor table, useful for identifying which pointer/byte governs what
for a given NPC, and doubles as a manipulation tool (repositioning an actor)
likely intended for TAS/glitch-testing purposes.
