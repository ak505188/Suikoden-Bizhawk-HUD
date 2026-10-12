# Invisible Actor Glitch (Hidden Room Slot)

On some screens you can talk to something that is not drawn. This is not a
decompression bug: it is an **uninitialised-memory** bug. A room's actor
table is built in heap memory that still holds the **last party member's
sprite sheet**, and the one code path that reads a *hidden* slot's X/Y
trusts them.

Verified against `InvisViki{OutsideRoom,McDohl,Cleo,Eileen}.State`, a sweep
of all 75 swept characters, a live interaction test, and disc data (see
[Tools](#tools)). Reverse-engineering history:
`notes/Invisible_Actor_Glitch.md`. Slot layout: see
[Zones_Areas_and_Rooms.md](./Zones_Areas_and_Rooms.md#room-data-structure).

## The chain, step by step

1. **Screen load queues textures.** The field scene runs three load states
   (`field_load_state_A/B/C`, `0x80132044` / `0x801322d8` / `0x8013240c`;
   they are entries of the scene-handler pointer `0x8017DA90`). State C
   queues *every party member's sprite texture in formation order*
   (`queue_texture_clut_upload`, `0x800c3500`).
2. **One 16 KB buffer.** `init_cd_batch_read` (`0x800c3344`, called as
   `FUN_800c36d4`) does `heap_alloc(0x4000)` for the batch.
   `vfx_texture_queue_decompress_step` (`0x800c3438`) then LZ-decompresses
   one queued texture per tick (`lz_decompress`, `0x800c3144`) into that
   same buffer and uploads it to VRAM. Each sprite sheet is exactly
   `0x4000` bytes: 128 rows of `0x80` bytes. Nothing clears the buffer
   between textures, and the last one decompressed is the **last formation
   member**.
3. **Buffer is freed.** `heap_free` returns the block; its bytes are left
   untouched.
4. **Room table is carved from it.** `room_build_actor_table`
   (`0x8012ed84`) calls `heap_alloc(count * 0x18)`. `heap_alloc`
   (`0x800c2d30`) is a K&R free list that hands out the **tail** of a free
   block and **never zeroes memory**. If the table lands inside the old
   buffer it contains sprite-sheet bytes.
5. **Hidden slots are not initialised.** For each room descriptor the
   builder evaluates an appearance condition (`FUN_8013d8e0`):

   `0`
   : present. The slot is fully written.

   `1`
   : alias. No new slot; the descriptor points at the previous slot.

   `2`
   : **hidden** (condition fails, e.g. a story flag). A slot is still
     allocated, but only `+0x14 = 0xFF` and the three pointers at
     `+8/+0xC/+0x10` (= 0) are written. X, Y, `+2..+7` and
     `+0x15..+0x17` keep the stale bytes.

6. **Interaction trusts them.** `FUN_8013d3cc` (confirm button) finds an
   actor's slot by matching `+0x14` against the trigger's id byte. A hidden
   NPC's trigger has id `0xFF`, which matches the first hidden slot, and the
   code then compares that slot's X/Y with the tile in front of the hero.
   It never checks the sprite pointer. The event of that hidden NPC runs.

Why it is invisible and does not block you: every other consumer skips a
slot whose `+8` pointer is null (collision `FUN_8012e5a0`, per-frame update
`FUN_80130514`, hit-test `FUN_80137f94`, draw/update `FUN_80133d08`, "turn
to face" `FUN_8013ccf0`). Only the interaction lookup lacks that test.

## Timeline (InvisViki room, hold Up 16 frames)

: f003-f006
  : older scratch buffers rewritten
: f007-f008
  : previous room's small allocations freed; free block is now exactly
    `0x4008` bytes at `0x80187af0`
: f009-f044
  : the 16 KB block is allocated; textures decompress one per tick
    (room textures first, then the 5 party sheets, formation order)
: f045
  : block freed
: f047
  : `room_build_actor_table` runs; the table lands at `0x8018B400`, which
    is offset `0x3908` (row 114, column 8) into the buffer

## Which bytes land where

A slot's byte at memory address `A` equals the last member's decompressed
sheet at offset `A - bufferStart`. Slot `k` starts `(k-1) * 0x18` after the
table. In the InvisViki room `bufferStart = 0x80187AF8`, table offset
`0x3908`, so slot 1 reads bytes `0x3908..0x3910` of the sheet:

```
X = sheet[0x3908]   Y = sheet[0x3909]   +2..+7 = sheet[0x390A..0x390F]
+0x15..+0x17 = sheet[0x391D..0x391F]
```

Bytes are 8-bpp palette indices, so flat areas give runs such as
`0b 0b 0b 0b` and X == Y is common. This predicts your three saves exactly
(McDohl `(0,0)`, Cleo `(11,11)`, Eileen `(20,20)`).

### What each character writes there (offset 0x3908)

Characters that share a sprite sheet give identical bytes. `+15..17` are the
stale `+0x15..+0x17` bytes (zeros unless listed). X,Y are bytes 0 and 1.

```
 X  Y  bytes 0-7                  last member
 0  0  00 00 00 00 00 00 00 00    (see zero list below)
 0  0  00 00 00 00 06 06 06 13    Camille
 0  0  00 00 00 00 1b 1b 1b 18    Milia
 0  0  00 00 00 00 1f 1f 1f 1f    Kasumi
 0 27  00 1b 1b 1b 18 18 18 08    Sonya, Valeria
 0 29  00 1d 1d 1d 1d 00 00 00    Alen, Grenseal
 3  3  03 03 0f 0f 0f 0e 0e 0e    Meg
 5  5  05 05 05 0b 0b 0b 0b 0a    Futch
 5 20  05 14 14 14 14 13 13 13    Kimberly
 6  6  06 06 06 18 18 18 00 00    Odessa
 7  7  07 07 07 1f 1f 1f 1f 05    Hellion
 8  8  08 08 08 08 02 02 02 02    Lepant
11 11  0b 0b 0b 0b 06 06 06 06    Cleo
14 14  0e 0e 0e 0e 15 15 15 15    Antonio, Lester
15 15  0f 0f 0f 15 15 15 15 0e    Liukan
17 14  11 0e 0e 0e 0e 15 15 15    Gen, Kage, Juppo, Kanak, Fuma,
                                  Fu Su Lu, Sansuke
20 20  14 14 14 13 13 13 13 18    Eileen, Sarah, Mina
23 25  17 19 19 19 0b 0b 0b 00    Kirke
24  5  18 05 05 05 05 0b 0b 0b    Kamandol, Sergei
29  5  1d 05 05 05 05 0b 0b 0b    Ted
```

All-zero (X=Y=0): Gremio, Kirkis, Pahn, the hero (McDohl), Anji, Varkas,
Ronnie, Krin, Kasim, Flik, Fukien, Humphrey, Kwanda, Luc, Milich, Sydonia,
Tai Ho, Tengaar, Viktor, Warren, Yam Koo, Kessler, Leonardo, Lorelai, Rubi,
Morgan, Clive, Lotte, Sheena, Hix, Crowley, Eikei, Quincy, Kreutz,
Stallion, Kai, Pesmerga.

Also stale in `+0x15..+0x17` (rest of the slot zero): Mose, Meese, Maas,
Mace, Moose `00 00 07`; Sylvina `05 05 05`; Kuromimi, Gon `06 06 06`;
Blackman `0a 0a 0a`; Griffith `1b 18 18`.

A different table offset gives a different table: run
`scripts/InvisActorPredict.py offset <hex>`.

## Every slot, not just one

The whole actor table lies in the sprite buffer, so the last member's sheet
sets bytes in **every** slot: slot `k` reads the sheet at `tableOffset +
(k-1) * 0x18`. What survives depends on the slot's type: a hidden slot
keeps X, Y, `+2..+7` and `+0x15..+0x17`; a present slot is fully written by
the builder except `+0x17` (never written), so only that byte is stale. In
the Invis room (3 slots, table offset `0x3908`) the 78 characters give 33
distinct outcomes; slot 1 (hidden) gets the X/Y listed above, and slots 2
and 3 only get `+0x17` (non-zero for a handful: e.g. Hero gives slot 3
`03`, Camille slot 2 `18`, Blackman slot 2 `09`). No code path checked reads
`+0x17`, so only a hidden slot's X/Y matters in practice.
`InvisActorPredict.py room --table-off 0x3908 --slots 3 --hidden 1` prints
all of it; use `outputs/ScreenSweep.csv` (`table_off`) for other screens.

For routing, the useful view is one (X, Y) per slot, *assuming only that slot
is hidden* (which slot is hidden does not move the table, since hidden and
present NPCs both take a slot). `InvisActorPredict.py table --wm W --area A
--screen S` prints it: one row per last member, one column per slot, cell =
`X,Y` (`*` marks slots that can be hidden per the static scan, `-` = outside
the buffer). `table-all --csv FILE` writes the long format for the first 110 swept screens.

**All screens:** `outputs/StaleSlotTables/` has one CSV per screen in the game
(`wm_NN/area_NN_Name/screen_NN.csv`, characters down, slots across, `*` on
slots whose NPC can be hidden) plus `index.csv` and a README. 950 screen
records: 428 CSVs (every record that has an actor table and could be
loaded), 519 with no actor slots at all, and 3 that could not be entered
(Great Forest screen 1). Built by `scripts/BuildStaleSlotTables.py` from a
live sweep of all 303 distinct (overlay, screen) pairs that have slots; the
table offset depends only on the screen: 25 of 25 screens loaded from a second,
unrelated start save gave the same offset.

## Can you actually talk to it?

The check is `FUN_8013d3cc`. For a slot at `(X, Y)`, the hero must face the
slot from these tiles (verified live; real NPCs use the same test):

```
DOWN   heroY = Y - 2, |X - heroX| <= 1
UP     heroY = Y + 1, |X - heroX| <= 1
LEFT   heroX = X + 2, heroY in [Y-1, Y]
RIGHT  heroX = X - 2, heroY in [Y-1, Y]
```

(The offsets are `DAT_801716F4/FC`: DOWN (0,+2), UP (0,-1), LEFT (-2,0),
RIGHT (+2,0) - the same offsets RoomInfo's "move NPC in front of hero"
uses.) A slot at (0,0) can only be hit from the extreme top-left corner
(hero tile (0,1) or (1,1) facing UP, or (2,0)/(2,-1) facing LEFT), which most
rooms do not have as walkable floor, so an all-zero sheet (McDohl last, for
example) is harmless in practice. A hit needs the stale (X, Y) to be a tile
the hero can actually stand next to.

## When is a room prone? Never?

All of these must hold:

1. **A hidden slot exists.** The room has a conditional NPC whose
   appearance condition currently returns 2 *and* whose descriptor is
   actor-linked (flag `0x1` or `0x100`). No such descriptor: no glitch.
   Hidden slots seen in other saves: slot 5 of the Counter room.
2. **Only the lowest-index hidden slot matters.** The interaction lookup
   returns the first slot with `+0x14 == 0xFF`; later hidden slots are
   allocated but never consulted. Slot 1 in this room only because its
   descriptor comes first.
3. **The slot lies inside the sprite buffer.** Measured on 110 screens
   across 65 areas (see [Live sweep](#live-sweep-across-areas)): the room
   table landed inside the 16 KB buffer on **every** screen, and so did every
   forced-hidden slot (104 of 104). Table offsets ran from `0x520` to
   `0x3F58` (median `0x3964`). The buffer start varies by room (`0x80187AF8`
   in the Invis room, `0x80188308` in the Counter room, `0x801886F8` in the
   Teo room), and the offset moves with how much the screen allocates
   before the table (event-zone arrays, per-actor sprite objects of `0x28`
   bytes, ...). So this condition rarely rules a screen out; it decides
   *which rows of the sheet* the hidden slot reads. (An earlier version of
   this doc said the Counter and Kwanda rooms were outside the buffer: that
   came from matching a stale older copy of the sheet, not the real buffer.)

4. **The sheet bytes at that offset are non-zero and form a reachable
   (X, Y).** Transparent areas are `0`, giving (0,0).
5. **Only the last formation member matters.** Every sheet decompresses to
   exactly `0x4000` bytes, so each one fully overwrites the previous; the
   last queued texture is what remains. Re-ordering the party changes the
   result (swept: 75 characters as last member). Adding a 6th member did not
   move the table address in the InvisViki room.

Unaffected fields: slots that are *present* are fully written except
`+0x17`, which no code ever writes (it is stale in every slot; it was
non-zero in a Counter-room slot). Nothing reads it in the paths checked.

## Live sweep across areas

`SweepScreens.lua` teleports to a screen by the game's own path (below), then
records the buffer start (`0x80178F78`, the texture-queue destination), the
room table and every slot. 128 screens were chosen from the static scan (up
to 2 per area, preferring a hideable NPC in slot 1) and loaded from the
Invis start state, whose last party member is the hero. For each, one clause
of the first hideable NPC's condition was violated so it became hidden.

110 loaded cleanly (65 areas, WM 0-11); 18 could not be entered this way
(16 never started the exit - the overlay header and table stayed the start
room's, so probably event or special screens - and 2 loaded but never
settled into the idle state). Results (`outputs/ScreenSweep.csv`):

- Table inside the buffer: 110 of 110. Forced-hidden slot inside it: 104 of
  104 (the other 6 stayed visible; the forced clause did not hide them).
- **Model check: 104 of 104.** The hidden slot's actual bytes equal the last
  member's (hero) decompressed sheet at that offset.
- Using every character as the last member, 88 of the 104 hidden slots would
  get a non-zero X or Y from at least one character (median 5 of 78
  characters; 16 slots are zero for everyone; one near the buffer start
  gives all 78 characters a non-zero value).

Examples (X,Y by last member, from `AnalyzeScreenSweep.py`):

```
wm area scr  file     slot offset  last member -> (X,Y)
 3   4   0   VD6.BIN    1  0x0520  all 78 non-zero, e.g. Eileen (6,31)
 1  24   0   VB5BG.BIN  1  0x3690  Eileen (8,8), Cleo (1,1), Camille (24,24)
 1  28   3   VB5B4.BIN  1  0x3790  Eileen (31,31), Cleo (1,1)
 3   3   0   VD5.BIN    1  0x3988  Eileen (20,20), Cleo (11,11)
```

Whether that coordinate is a tile the hero can stand next to is a property of
the screen's collision map and is not checked here.

### How the teleport works (reusable)

The field runs three cooperating state machines in the handler array at
`0x8017DA90` (index 1 = main, 2 = loader, 3 = per-frame), under the dispatcher
`scene_dispatcher` (`0x800C98F0`, index 0). With `ctx = *(0x8017BE20)`:

```
same overlay:   write AREA/SCREEN/WM bytes (0x1B8000..2), ctx+0x34 = 1
other overlay:  ctx+0x35 = 2 (bit 0 clear), ctx+0x37 = 0, ctx+0x34 = 1;
                run ONE frame; THEN write the zone bytes
```

The sweep did not set the hero's arrival tile (`gamestate+4/+6`, u16 X/Y), so
it arrived on the previous screen's tile. The Toolbox Screen Teleport tool
does set it, from the game's own door scripts (see
[Zones, Areas and Rooms](./Zones_Areas_and_Rooms.md), "Event scripts and
screen changes", and [Saves and Toolbox](./Saves_and_Toolbox.md)).

The two-phase form matters: writing the zones first made the idle handler
hang on about 17% of screens (it indexes per-screen tables with the new zone
against the old screen's data, and never returns), so the request flag was
never consumed. Triggering the exit first and writing the zones a frame later
loaded all of them, and gave the same table address as the one-phase method
on screens that worked both ways. The game's own door path goes through
`field_loader_idle` (`0x80132790`): idx-3's return code sets `ctx+0x35`/`+0x38`,
`gamestate+4/+6` (spawn X/Y) is copied to `ctx+0x28/+0x2c`, and
`field_screen_change_begin` sets `ctx+0x34`.

`field_main_running` (`0x801319C4`) sees `ctx+0x34`, tears the screen down
and queues `field_load_state_A`; with `ctx+0x35` non-zero it takes
`field_main_exit_field` (`0x80131E0C`) instead, which frees the field
context, sets the next scene to "field" and lets the dispatcher re-run
`FUN_80130EC4`, which reloads the overlay for the new zones. This reproduced
three natural saves exactly (Invis `0x8018B400`, Counter `0x8018B0D0`, Teo
`0x8018C590`, same buffers), so the heap state is the game's own.

## Tools

`scripts/InvisActorPredict.py`
: `offset`, `where X Y`, `room` (every slot of a room at once: per last
  member, a hidden slot's X/Y/`+2..+7`/`+0x15..+0x17`, a present slot's
  `+0x17`) and `state FILE.State` modes; decompresses every
  character's sheet from `data/04_play/*.bin` (byte 0 = character id). It
  reproduced all 75 sweep results and your three saves.

`scripts/ScanRoomDescriptors.py`
: the static scan above.

`scripts/SweepScreens.lua` + `scripts/AnalyzeScreenSweep.py`
: the live sweep and its analysis (headless only).

`scripts/SweepInvisViki.lua`, `TraceInvisViki.lua`, `SnapInvisViki.lua`,
`TestInvisInteract.lua`
: headless captures (they load `InvisViki*.State`; never run them in your
  live session).

RoomInfo module
: shows `HIDDEN` slots and the decoded fields; `NUM_SLOTS` is now the exact
  count at `Address.ROOM_SLOT_COUNT` (`0x17DBFC`).

## Static scan of every screen

`scripts/ScanRoomDescriptors.py` reads the room data straight from the disc
(no emulator): `main.exe`'s `PTR_PTR_8016F67C[WM][area]` gives a
`{size, LBA}` record for the area overlay; the overlay's header (u32 at file
offset 0 -> header, header `+8` -> screen-record array, one `0x10` record per
SCREEN_ZONE) points at each screen's descriptor array. It decodes the
appearance-condition bytecode with the same rules as `FUN_8013D8E0`:

```
07/08/09/0A id mask   event-flag byte & mask set / clear / set / clear
0E id / 0F id         character in / NOT in the party
10 id                 recruit state: bit0 set, bit1 clear
11 id                 recruit state: bit0 clear, bit1 clear
19 id                 recruit state: bit0 or bit1 set
13 id lvl             character level >= lvl
14 x lvl              castle level >= lvl
15 n                  random, shown about 1 time in n+1
16 n                  unidentified counter >= n
01-05 0B 0C 0D 12 17 18   alias (no slot of its own)
any other op          always hidden
```

(`evflag` arrays are `gs+0x190` for 07/08 and `gs+0x280` for 09/0A, where
`gs = 0x1B8000`. `recruit` is the byte array at `0x1B9AF4`.)

Validation: all structure matches live RAM for the Invis room (slot 1 =
Viki, sprite 97, shown only if Viki is recruited, not gone, and not in the
party) and the Counter room (slots d8-d15 -> 1-6, hidden NPC in slot 5 on
`evflagA[10]&0x20 clear`). Screen counts match the zone spreadsheet for 27
of 31 areas; the rest are the sheet missing screens that exist in the data
(Great Forest has 0-19, Tigerwolf has 11) or a duplicated entry.

Results (`outputs/RoomDescriptors.json`, `outputs/RoomHiddenCandidates.md`):
950 screen records, 663 distinct (overlay, screen) pairs, **190 screens with
at least one NPC whose condition can fail**, 902 such NPC descriptors. Most
conditions are event flags (615) or recruitment state (311), plus party
membership (217), character level (9) and castle level (9). No descriptor
is unconditionally hidden. 161 of the 190 screens have a hideable NPC in
slot 1.

What the scan **cannot** say: whether the condition currently fails (it
depends on the save), and where the buffer and table sit in the heap.

## Open questions

- Only 110 of the 190 candidate screens (and 65 areas) were swept, from one
  start state; the table offset could differ with a different prior heap, which
  was not varied. The 18 screens that could not be entered are untested.
- Six forced clauses did not hide their NPC; those were not investigated.
- Collision maps were not consulted, so "reachable" is not established for any
  stale coordinate.
- Whether non-party textures can be the last entry on some screens (the
  party phase was always last here).
