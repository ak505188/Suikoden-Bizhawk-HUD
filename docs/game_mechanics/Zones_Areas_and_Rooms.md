# Zones, Areas, and Rooms

Covers how location is represented in memory at three different
granularities (world-map region, sub-area, and live room/actor data), and
how areas are categorized for encounter purposes. See
[Battles_and_Encounters.md](./Battles_and_Encounters.md) for how this feeds
into encounter-table lookups.

## Area / Zone / Screen / Room — distinct concepts

Three single bytes live contiguously at `GAMESTATE_BASE = 0x1B8000`, read as
one 16-byte buffer each frame by `monitors/State_Monitor.lua`:

- `0x1B8000` `AREA_ZONE`: Sub-area index inside whatever world-map region
  the party is in
- `0x1B8001` `SCREEN_ZONE`: Finer screen/room-transition tracking within
  an area
- `0x1B8002` `WM_ZONE`: World-map region index (0–11), top-level key
  into `ZoneInfo`

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

The builder is `room_build_actor_table` (`0x8012ed84`); `modules/RoomInfo/
worker.lua` reads the result. Memory offsets (Lua buffer index = offset + 1):

`+0` X, `+1` Y
: u8 tile position.

`+2`, `+3`
: SubpixelX/Y. Zero at build, updated while the actor walks.

`+4` FacingRow
: sprite row for the facing (direction 0->0, 1->1, 2->0, 3->2). Not the
  direction itself (the old "isn't actually direction" comment).

`+5` Moves
: copy of descriptor flag bit 2. Exact use unverified.

`+6` ZoneLayer, `+7` ZoneIndex
: layer byte and index-1 of the walk-zone rectangle the actor stands in
  (`FUN_8012e308` over the zone table `DAT_8017C038`, 12-byte entries); 0
  when none. (RoomInfo's old `Unknown1`.)

`+8`, `+0xC`, `+0x10` MemAddress1/2/3
: three 2D-sprite objects (`FUN_801346a8`). The first byte of each is the
  facing direction (0 DOWN, 1 UP, 2 LEFT, 3 RIGHT). All three are null for a
  hidden slot.

`+0x14` ActorId
: slot index; **`0xFF` = hidden placeholder**.

`+0x15`
: copy of ZoneLayer.

`+0x16` SortPriority
: draw order; `-Y` for free-roaming actors, else the zone's value.

`+0x17`
: never written by the builder (stale heap data in every slot).

(RoomInfo's old `Unknown2` = `+0x14/+0x15`, `Unknown3` = `+0x16/+0x17`.)

A second table, `heap_alloc(count * 8)`, sits just below the actor table
(`Room_Monitor`'s `CANDIDATE_POINTER_2`, = `*(DAT_8017BE20 + 0x484)`): one
record per slot: `{u8 slotIndex (0xFF hidden), u8 flags, u16, u32 slotPtr}`.

### Hidden slots

Each room descriptor (`DAT_8017BF98`, `0x18` bytes, count at
`*(DAT_8017BFC0)+4`) has an appearance condition (bytecode at descriptor
`+0xC`, run by `FUN_8013D8E0`). A condition result of `2` allocates a slot but
only writes `+0x14 = 0xFF` and nulls the three pointers, leaving X, Y and the
other fields as stale heap bytes. That is the root of the invisible-actor
glitch: see [Invisible_Actor_Glitch.md](./Invisible_Actor_Glitch.md).

### Slot count

`NUM_SLOTS` is the u8 at `Address.ROOM_SLOT_COUNT` (`0x17DBFC`,
`DAT_8017DBFC`), written by the builder. It matched in all seven saved rooms
tested. The old formula `(ROOM_ADDRESS - CANDIDATE_POINTER_2 - 8) // 8` gives
the same value (it is the size of the `count * 8` table); the byte at
`ROOM_ADDRESS - 0x10` (`NUM_SLOTS_OLD`) is `count - 1`. Both are kept only as
cross-checks.

## Event scripts and screen changes

Each room descriptor's `+0x14` is a pointer to an event script (bytecode in the
area overlay). `FUN_8013E17C` points the interpreter at it and `FUN_8013E028`
runs it (handler table at `PTR_LAB_80171718`; opcode lengths are not tabulated,
the handlers consume their own arguments). Opcode `03` is "change screen"
(`FUN_8013BF94`), usually followed by `fd` (end):

```
03 S X Y              same area, screen S      (returns 2)
03 fc A S X Y         area A of this WM        (returns 3)
03 fa W A S X Y       WM W, area A             (returns 3)
03 fd B S X Y         WM 1, area = table 0x801716D8 + B
03 fe/ff/fb ...       exits to the world map
```

X/Y are the hero's arrival tile; they are stored at `gamestate+4/+6` (u16,
`0x1B8004/6`), which `field_loader_idle` copies to the hero. These door
destinations are the only per-screen "entry points" in the data. A screen
record whose descriptor list is empty (count 0) is still a real screen (the
spreadsheet lists them, for example 0/0/12 and 11/0/12). Screens that no door
leads to, mainly area entrances from the world map, have no door-script entry
tile. `scripts/BuildScreenList.py` extracts all of this into
`lib/ScreenList.lua`.

## Hero position/direction

- `0x17BD74` `HERO_X`: u8, local X coordinate in the current room/screen
- `0x17BD75` `HERO_Y`: u8, local Y coordinate
- `0x17BD7C` `HERO_DIRECTION_PTR`: u32 pointer (not the direction value
  itself) — sanitize, then read a single byte at the resolved address
  for `Direction` (0=DOWN, 1=UP, 2=LEFT, 3=RIGHT,
  `lib/Enums/Directions.lua`)

`HERO_X`/`HERO_Y` sit 8 bytes before `HERO_DIRECTION_PTR`, consistent with
all being fields of one hero-state struct starting at `0x17BD74`. The same
pointer-indirection pattern is used for NPC direction via room-slot
`MemAddress2` above, suggesting hero and NPCs share a character-struct format.

The RoomInfo menu's "move NPC in front of hero" feature
(`modules/RoomInfo/menu.lua:moveNPCInFrontOfHero`) uses asymmetric offsets
depending on facing direction (`y+2` for DOWN, `y-1` for UP, `x-2` for LEFT,
`x+2` for RIGHT). These are exactly the actor-interaction offsets in the
game's own talk check (`FUN_8013D3CC`, tables `DAT_801716F4/FC`), so the
moved actor lands on the tile the game tests. The check also tolerates the
perpendicular axis (UP/DOWN: |dx| <= 1; LEFT/RIGHT: slotY in [heroY,
heroY+1]), which is why the asymmetry exists. Verified live; see
[Invisible_Actor_Glitch.md](./Invisible_Actor_Glitch.md).

## RoomInfo module

`modules/RoomInfo/worker.lua` polls `Room_Monitor` and re-derives the full
room actor array each tick, always drawing the hero's X/Y/Direction, the raw
`ROOM_ADDRESS`, `NUM_SLOTS` (exact, from `0x17DBFC`) and `NUM_SLOTS_OLD`
(`count - 1`, kept as a cross-check), plus a list of every slot's
index/X/Y/address. Hidden placeholder slots are tagged `HIDDEN`.

`modules/RoomInfo/menu.lua` is the interactive layer: shows the currently
selected slot with detailed fields (X/Y/Moves, SubpixelX/Y/Direction, all
three raw `MemAddress` pointers, the actor id with a `HIDDEN(X/Y stale)`
flag, FacingRow, the zone bytes, sort priority and the unused byte, all in
hex). Square repositions the selected actor to right in front of the hero;
Up/Down step one slot; Left/Right jump ±10; Circle exits.

In short: RoomInfo is a live memory-inspection/debug tool for the current
room's actor table, useful for identifying which pointer/byte governs what
for a given NPC, and doubles as a manipulation tool (repositioning an actor)
likely intended for TAS/glitch-testing purposes.
