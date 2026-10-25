# Invisible interactable actor glitch (2026-10-10)

Saves: `InvisViki{OutsideRoom,McDohl,Cleo,Eileen}.State` (area 0x20, screen 2,
wm 9). Trace (script since removed): headless, ~420 frames, walks Up
16 frames from OutsideRoom; Nymashock pad name is `P1 D-Pad Up`).

## Observations (savestate RAM, MainRAM = Core.bin(zstd) + 0x1cb18)
- Room table at 0x8018b400 in all three in-room saves, 3 slots (0x18 each).
  Slot 1 = hidden placeholder: `+0x14=ff`, `+8/+0xc/+0x10 = 0`, X/Y/+2..+7
  never initialised.
- Slot 1 bytes 0..7 by last formation member:
  McDohl `00*8` (and 12 12 12 12 / 1d 1d 1d 1d at +0x48/+0x50, past the table),
  Cleo `0b 0b 0b 0b 06 06 06 06` (X=Y=11), Eileen `14 14 14 13 13 13 13 18` (X=Y=20).
- The same bytes sit in a 0x80-stride image-row pattern 0x4048 below, at
  0x801873b8 etc. Rendered as an image the buffer is a character sprite sheet.
- Two adjacent 16 KB heap blocks (0x80183af8.., 0x80187af8.., headers at
  0x80183aa8 / 0x80187ab0) are streamed every frame f010-f044 after the
  step (A rewritten f003-f006). The new room table is allocated at f047.

## Mechanism (static, main.exe in Ghidra)
- `heap_alloc` 0x800c2d30 / `heap_free` 0x800c2dc0 / `heap_init` 0x800c2ea8:
  K&R free list in 8-byte units (header {next,size}), arena 0x80182000+0x18000,
  next-fit, carves the TAIL of a free block, NEVER zeroes memory.
- `room_build_actor_table` 0x8012ed84 (was FUN_8012ed84) builds the table:
  `DAT_8017daa0 = heap_alloc(count*0x18)` then a second `heap_alloc(count*8)`
  (= CANDIDATE_POINTER_2 block; NUM_SLOTS = (room - that - 8)/8).
  Per room descriptor (0x18 bytes at DAT_8017bf98, count at DAT_8017bfc0+4) it
  asks `FUN_8013d8e0(descr+0xc)` (appearance-condition bytecode):
    0 = present  -> slot fully initialised (X,Y,sub=0,+4 facing,+5 moves,
                    +6/+7 zone, +8/+0xc/+0x10 sprite objs, +0x14 id=slot idx,
                    +0x15 zone copy, +0x16 sort priority)
    1 = alias    -> descriptor id byte = previous slot index (no new slot)
    2 = HIDDEN   -> slot allocated but ONLY +0x14=0xff and the 3 pointers = 0
                    are written. X,Y,+2..+7,+0x15..+0x17 = stale heap bytes.
  Descriptors with (flags & 0x101)==0 get id byte 0xff and no slot.
- Interaction `FUN_8013d3cc` (confirm button): for actor-linked descriptors
  (flags & 1 or 0x100) it finds the slot whose `+0x14` equals the
  descriptor's id byte, then tests that slot's X/Y against the tile in front
  of the hero. A hidden NPC's descriptor id is 0xff and the hidden slot's
  +0x14 is 0xff, so the lookup lands on the hidden slot and trusts its
  uninitialised X/Y -> invisible but talk-able, firing the hidden NPC's event.
- Why the last party member: the room table is carved from the tail of a
  just-freed 16 KB staging block that still holds the last decompressed
  character sprite sheet (party sprites are streamed in formation order), so
  slot 1 inherits the pixel bytes at that offset.

## Slot field map (0x18 bytes) from room_build_actor_table / FUN_8012ea40
 +0 X, +1 Y, +2/+3 subpixel X/Y (0 at init), +4 facing sprite row
 (dir 0->0, 1->1, 2->0, 3->2), +5 moves flag (descr flags bit2), +6 zone layer
 byte (0 if none), +7 zone index-1, +8/+0xc/+0x10 three 2D-sprite object ptrs
 (first byte of each = facing dir), +0x14 slot id (0xff hidden), +0x15 copy of
 +6, +0x16 sort priority (-Y if free-roaming else zone value), +0x17 unused.

## Open / to verify live
- Sweep every character as last member to tabulate their 8 bytes.
- Whether the table address (hence which sprite offset) varies with room /
  party size / free-list state; which slot indices can be hidden.

## Resolved (same day)
- Source of the stale bytes = the LAST formation member's queued sprite
  texture. field_load_state_A/B/C (0x80132044/0x801322d8/0x8013240c) queue
  room textures then every party member's (`queue_texture_clut_upload`
  0x800c3500, formation order); `init_cd_batch_read` 0x800c3344 allocs the
  16 KB buffer; `vfx_texture_queue_decompress_step` 0x800c3438 decompresses
  one per tick; heap_free; room table carved from the same memory.
  (FUN_8013f4b8's 16 KB *stack* array is a different path; the residue is
  the heap buffer above.)
- Proven: lz_decompress of the last member's texture == the heap buffer
  rows 0-110 (the rest overwritten by room allocs); disc data
  (data/04_play/*.bin, byte0 = id, +0x28 hdr, +4 count, +8 ptr array,
  tex = {u32 size, lz}) reproduces all 75 sweep results offline.
- Buffer start varies by room (0x80187af8 here; 0x801824c0 Counter room;
  0x801838b0 Kwanda; 0x801886f8 Teo; 0x80187af0 Zombie Dragon), table is
  outside it in Counter/Kwanda -> not prone there.
- Live geometry test (TestInvisInteract.lua): predicted talk tiles trigger
  an event (RAM window diff ~918 vs 3-5), predicted misses do not; a real
  NPC (15,31) behaves identically.
- Other slot readers skip null +8, only FUN_8013d3cc does not.
- Room slot count = u8 0x17DBFC. RoomInfo module + docs updated.
- docs: docs/game_mechanics/Invisible_Actor_Glitch.md. Tool:
  scripts/python/InvisActorPredict.py.
- Not done: scan all rooms' descriptor tables for conditional NPCs;
  trace the free-list rover to predict buffer start.

## Static scan (2026-10-10)
- Zone->overlay: main.exe PTR_PTR_8016F67C[wm][area] -> {u32 size, u32 LBA}
  (record at 0x80163D8C..; verified WM9/area32 = LBA 59282 = VB5AG.BIN).
  PSX-EXE load 0x800c0800. Overlay at 0x80010000: u32@0 -> header; hdr+4
  resource array, hdr+8 screen records (0x10 each: +0 desc ptr, +4 count,
  +5 res idx, +7 flags, +8/+9 res idxs, +0xC ptr). All-zero record ends the
  array; records with dptr 0/count 0 are real holes (Kouan). Header word0 is
  NOT the screen count.
- Bytecode semantics from FUN_8013d8e0 + helpers 8013d6cc/d330/d788/d758.
  Flag array gs+0x1af4 == the 0x1B9AF4 recruit array.
- scripts/python/ScanRoomDescriptors.py; outputs/RoomDescriptors.json (all screens)
  and outputs/RoomHiddenCandidates.md (190 screens). 27/31 areas match the
  user's sheet; the sheet omits real screens (Great Forest 0-19, Tigerwolf 11).
- Counter room d12 (42,39) hidden via evflagA[10]&0x20 (live slotbyte ff).
  Alias descriptors (d13/d14) carry slot byte = count-1, NOT ff.
- Not done: heap geometry per screen (live), flag forcing, teleport test.

## Live sweep + teleport (2026-10-10)
- Teleport works by the game's own path: field state machines at 0x8017DA90
  idx1 (main: 0x801319c4 running / 0x8013161c leaving / 0x80131724 / 0x801318b8)
  idx2 (loader: 0x80132044 A, 0x80132280, 0x801322d8 B, 0x801323a4,
  0x8013240c C, 0x801324d8 texture wait, 0x80132524, 0x801325a4, idle
  0x80132790) idx3 (0x80132938 normal, 0x80132b6c door step detect). idx0 =
  scene_dispatcher 0x800c98f0. ctx = *(0x8017be20) (0x80199b10 here).
  In field_main_running decompile `DAT_8017be20 + 0xd` is a word-pointer
  offset = byte +0x34 (the change-screen request); +0x35/+0x37 are byte
  offsets. Same overlay: zones + ctx+0x34=1. Other overlay: also ctx+0x35=2,
  +0x37=0 -> field_main_exit_field 0x80131e0c frees ctx and bufs, gs+0x1bbc=2,
  dispatcher sets idx1=FUN_80130ec4 (overlay load via {size,LBA} record).
- Validated: Invis/Counter/Teo natural saves reproduced exactly (table + buffer).
- CORRECTION: Counter room buffer is 0x80188308 (table inside, offset 0x2dc8);
  the earlier 0x801824c0 was a stale older copy. InvisActorPredict.py `state`
  now prefers the copy containing the table.
- Sweep: 128 targets, 110 analysed (65 areas), 18 not enterable this way:
  16 never started (RAM overlay header and table unchanged: (0,0,10) (0,3,11)
  (0,6,9) (0,6,13) (0,7,10) (2,3,9) (2,3,11) (2,5,13) (4,2,23) (4,2,24)
  (4,4,20) (5,1,9) (7,0,13) (11,0,15) (11,0,17) (11,1,10); five of these show a
  coincidentally matching ns=1) and 2 loaded but never idled ((1,3,0), (2,4,0)).
  Table in buffer 110/110, forced-hidden slot in buffer 104/104, model
  (actual == last member's sheet at offset) 104/104. 88/104 hidden slots
  non-zero for >=1 character. outputs/ScreenSweep.csv.
- Heap start state was the Invis save for every target (hero last member).

## All-screens tables (2026-10-10)
- Swept all 303 distinct (overlay, screen) pairs with >=1 slot (431 wm/area/screen records incl. aliases).
  First pass (zones written with the request): 251 ok, 48 never started, 4 never idled. Cause of "never started":
  with some target zones the idx-3 handler called from field_loader_idle (0x80132790 -> 0x80132938) never
  returns, so field_main_running never consumes ctx+0x34. Fix = two-phase teleport (request first, zones one
  frame later). Retry loaded 48/48 of those; same table address as one-phase on screens that worked both ways.
- Final: 425 ok, 3 ok-but-event (1,3,0)(2,3,0)(2,4,0) [table read at timeout], 1 unenterable (1,4,1) = 3 records.
- Start-state robustness: 25/25 sampled screens gave identical table offset from CounterRemainingCharacters.State.
- Tree: outputs/StaleSlotTables (scripts/python/BuildStaleSlotTables.py). 519 records have no actor-linked descriptors.
- Door path facts: field_loader_idle 0x80132790 copies gs+4/+6 -> ctx+0x28/+0x2c (hero spawn), sets ctx+0x38,
  then field_screen_change_begin 0x80132898 sets ctx+0x34.

## Screen entry tiles (2026-10-11)
- Hero arrival tile = gs+4/+6 (u16, 0x1b8004/6); field_loader_idle copies them to ctx+0x28/+0x2c and
  field_main_state_3 turns them into the camera. The sweep never wrote them (it kept the old screen's tile).
- Source: door scripts. Descriptor +0x14 = event script pointer (FUN_8013e17c sets the script pointer, FUN_8013e028
  runs it; handler table PTR_LAB_80171718, many handlers undisassembled so lengths are unknown). Opcode 03 =
  FUN_8013bf94 = change screen: `03 S X Y` (ret 2) / `03 fc A S X Y` / `03 fa W A S X Y` (ret 3), then `fd`. Variants
  `03 fd b ...` (area = table 0x801716d8 + b, WM 1) are skipped; `03 fe/ff/fb` = world map. Verified on Outside Room.
- scripts/python/BuildScreenList.py finds them by searching 0x80 bytes of each script for `03 <args> fd`.
- CORRECTION: records with count 0 are REAL screens (no actor list), not holes: the 60 of them were wrongly
  dropped first (user noticed 11/0/12 missing). Final: 950 screens, 845 with an entry tile, 105 without (area
  entrances from the WM, cutscene screens, unused ones such as 0/0/12, 11/0/12).
- Live test (scripts/TestScreenTeleport.lua, all 845, first entry, from the Outside Room save): 832 land on the entry
  tile. 13 BROKEN (labeled in lib/ScreenList.lua via the BROKEN dict): never load 1/4/1 9/4/1 1/6/0 9/6/0; arrival
  event moves hero 0/0/0 11/0/0 0/3/0 1/41/0 9/41/0; hero walks in 1/5/6 2/6/6; redirect to 0 1/33/2 9/33/2.
- Not checked: that entry tiles are standable via collision data (collision decode is paused).
- Gotcha: `pkill -f <script name>` inside a Bash call matches the call's own shell and kills it (exit 144).

## v1.0 (PSN / PSTV) vs v1.1 (2026-10)

Question: do the build differences change the invisible-actor values? Checked statically, no emulator:
- Chain code identical (instruction by instruction, immediates and jump targets ignored): heap_alloc, lz_decompress, init_cd_batch_read,
  vfx_texture_queue_decompress_step, queue_texture_clut_upload, field_load_state_A/B/C, the appearance condition (FUN_8013d8e0), the
  interaction check (FUN_8013d3cc). room_build_actor_table: same 405 instructions, 57 relocated address immediates, nothing else.
- Data: all 516 files compared by md5; 82 differ (main.exe, SLUS, the 9 war overlays, 66 field/area overlays, a few castle/ikki files).
  The character sprite sheets are among the 434 identical files, so the stale bytes per character at a given buffer offset are the same.
- Room data: `scripts/python/ScanRoomDescriptors.py` logic run on both images (v1.0 with the zone table at +0x45a4): 950 screen entries each,
  507 of the area overlays differ in size, yet count, resource, X, Y, flags, sprite, condition text, alias and slot of every descriptor
  are identical in all 950 screens. So the hidden-NPC candidates (190 screens) do not change.
- Heap layout (decides the table offset into the stale 16 KB buffer, e.g. 0x3908 in the InvisViki room): not provable statically.
  Indirect evidence: the PSTV RAM dump (MEMDUMP0.dmp, v1.0) holds the same heap pointers as the v1.1 BizHawk state from the same save:
  room table 0x8018b608, hero direction 0x8018b980, battle struct 0x80196bd0, VFX ctxs 0x80190e80 / 0x80190c08, field ctx 0x80199b10.
  Open: a dump taken in an invisible-actor room on the PSTV (expect table 0x8018B400 in the InvisViki room) would confirm it.
- Address moves that matter for the tools: ROOM_POINTER 0x17daa0 -> 0x181a98, ROOM_SLOT_COUNT 0x17dbfc -> 0x181be4, scene handlers
  0x17da90.. -> 0x181a88.. (lib/Address.lua V10); the field_load_state functions are at -0x560 (0x80132044 -> 0x80131ae4, 0x801322d8 -> 0x80131d78,
  0x8013240c -> 0x80131eac), heap_alloc 0x800c2d30 -> 0x800c2f1c.
