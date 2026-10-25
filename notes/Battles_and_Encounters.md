# Battles and Random Encounters — notes

This is the history/uncertainty behind
[docs/game_mechanics/Battles_and_Encounters.md](../docs/game_mechanics/Battles_and_Encounters.md).

## Encounter roll

The division by `0x7f` (127) for overworld, instead of a power-of-two mask
like the world-map path, is unexplained in any comment and looks like it
mirrors the original PS1 assembly rather than being an arbitrary tool design
choice — worth verifying against a disassembly if one becomes available.

**2026-10-14 update:** verified against `main.exe`. `field_rand_div_127`
(`0x8013879c`) really is `rand() / 0x7f` (quotient), compared against the
room's rate byte, so the Lua overworld branch is right. See the new
"Field encounter check, step counter and grace period" section in the docs.

## Which enemy group spawns — the Champion Rune / "Champ Val" mechanic

This implies the base game normally downgrades/rescales which encounter
groups can appear as the party's total level rises past each `champVal`
threshold, and equipping the Champion Rune prevents that automatic
downgrade, letting tougher/rarer groups keep appearing regardless of level.
This inference is not stated in any comment — it is inferred purely from the
check's structure and should be verified against real game behavior.

## Data structures

The `encounters` digit → enemy mapping should be verified against real
battles before being treated as fact.

## 2026-10-14 grace period / step counter static pass

- Method: found `0x8017159d` (RAM `0x17159D`, the rate byte) xrefs, which led
  to `field_check_random_encounter` (`0x8012cc38`). Grace is
  `0x8017159c`, loaded with rate from the room's `+0x38` block in
  `field_load_state_A`. Step counter is field struct `+0x30`, incremented
  at `0x80132ae0` (Ghidra has no function there, only a label region).
  Area files are overlays at `0x80010000`; parsed straight from the ISO
  with `scripts/python/dump_encounter_blocks.py`.
- Checks that held up: group counts match `EncounterTable.lua` for every
  area; grace 60/50/30 matches the user's observed values (Kalekka 30).
- NOT yet verified live: the "one roll per finished tile move" timing and
  the "wall-bump rolls every frame past grace" prediction; whether the
  `+0x36` re-arm flag behaves as read; what `0x8017bd7a` and save flag
  `0x19` (save+0x1bb bit 0x40) mean; the per-3-steps routine `0x80126408`.
- Not covered: the world-map encounter routine (separate overlay code).
- Corrects the old assumption that rate/grace are per area: they are per
  room block (Mt. Tigerwolf rooms 2/4/7 rate 3, others rate 2).

## 2026-10-24 forcing a random-encounter group from Lua (Mt. Seifu, headless)

- Method: `ScreenTeleport` to the area (0/6/2), then write, in one frame:
  `save+0x1bb4 = *(room+0x38)+4` (encounter table ptr, room = u32 at `0x17aae4`),
  `save+0x1bc0 = group index (1-based)`, `ctx+0x37 |= 4`, `0x17159a = 1`,
  `ctx+0x36 = 1` (save = u32 at `0x17db24`, ctx = u32 at `0x17be20`).
  Battle starts 3 frames later; no rolls, no RNG consumed by the check.
- Result: all 5 Mt. Seifu groups loaded; group structs at `ENEMY_GROUP_PTR`
  matched `EncounterTable.lua` digits exactly, screenshots show the real
  battle menu (6x Soldier Ant for group 1, 3 Bandits for group 3).
- Failed first attempt: without `save+0x1bb4` the game froze: battle loader
  (scene handler slot 1 = `0x800de61c`, entered from `0x800ddf98`) never
  finishes, gamestate stuck at 3, `ENEMY_GROUP_PTR` 0, table ptr garbage.
  `0x800ddf98` reads 1bb4 (table) and 1bc0 (index, falls back to 1 if > count).
- Pitfall: area overlay data (room records, encounter blocks, tables) sits at
  `0x80010000+`, so a "valid pointer" check of `>= 0x80100000` rejects them.
- Not yet tried: scripted/forced fights (script opcode at `0x801394d0`; 0xFF form
  sets group index directly, other form looks up the table via room+0x1c/+0x20).

### 2026-10-24 scripted fights (Queen Ant room 0/6/9, headless)

- Same recipe as above, but `save+0x1bb4` takes an entry from the room's own scripted-table
  list: `list = u32 at room+0x20`, entry = `list[B + u32(room+0x1c)]` (B = script byte; read
  from the raw MIPS of the opcode at `0x801394d0`, not decompiled). In 0/6/9 `room+0x1c = 3`,
  so `list[0..2]` are not tables and the scripted ones are `list[3]` (B=0) and `list[4]` (B=1).
- `list[3]` (`0x8006bdf8`), group 1: slots `2 2 2 1` -> screenshot shows a real battle menu with
  3 Soldier Ant + Queen Ant. Forced OK.
- `list[4]` (`0x8006be14`), group 1: size 1, record 1 in slot 7 -> gs=3 but the screen at
  +603 frames is the Queen Ant emerging on the field. RESOLVED (user, watched live in a
  visible emulator): it is a forced story battle that plays itself, no player input. Forced OK.
  So the table's group size / slot layout alone doesn't distinguish it from a normal fight.
- Not played through; other scripted fights untested. The 0xFF opcode form (group index
  only, keeps the current 1bb4 table) is unexercised.

### 2026-10-24 forcing a battle WITHOUT loading the area (headless, base save area 11/0/0)

- Idea: copy Seifu's table + groups + enemy records into free RAM (`0x181400`, verified zero),
  relocate the table's `+8` (group list) and `+0xc` (record ptr array) pointers, point
  `save+0x1bb4` at the copy and force group 1 with no teleport.
- Copy sizes that matter: table `0x40` (it holds a second sub-struct at `+0x20`), each group
  `0x18` stride in the overlay (copied `0x20`), each enemy record `0x80`. First attempt copied
  only `0x10`/group, `0x40`/record, `0x20` table: froze even WITH Seifu loaded.
- CONTROL (Seifu loaded + relocated copy): works, battle menu up, 6 Soldier Ants.
- No area loaded: still freezes at the battle loader (slot 1 = `0x800de61c`, gamestate 3,
  groupPtr/tablePtr point at the copy, field still on screen after 600 frames).
- So the area overlay is needed by something other than the table. Every enemy record carries
  three overlay pointers at `+0x28`, `+0x2c`, `+0x30` (e.g. Soldier Ant: `8006504c`,
  `8006547c`, `800106b0`; shared-looking `800103b0`/`800108f0` for others). They dangle when
  the overlay isn't loaded. Likely AI code/data (matches `Monster_AI_Static_Catalog.md` AI
  function pointers) and animation/sprite data. Not yet determined which one the loader
  stalls on.
- Not tried: copying the overlay regions those pointers reference into RAM (effectively a
  manual area load), or patching the pointers to targets present in the current overlay.

### 2026-10-24 ForceBattle on v1.0, and why it fails on the world map

- v1.0 "doesn't work on any field screen" (user report): `ROOM_RECORD_PTR` had no V10 entry, so v1.0 read
  the v1.1 address, `list()` returned nil and the tool showed "Not in a field screen". Derived by extracting
  v1.0 `MAIN.EXE` from `Suikoden (v1.0).bin` and pattern-matching `field_check_random_encounter`
  (v1.1 `0x8012cc38` -> v1.0 `0x8012c6d8`, delta -0x560, immediates masked): `ROOM_RECORD_PTR` 0x17aae4 ->
  0x180248, `ENCOUNTER_ARMED` 0x17159a -> 0x175b0e (field ctx came out 0x180d60, matching the existing V10).
  The loader (`0x800ddf98` -> `0x800de160`) and the script opcode (`0x801394d0` -> `0x80138f24`) use the
  same save offsets `0x1bb4`/`0x1bc0` in both builds. Not derived: `ENEMY_GROUP_PTR`/`ENCOUNTER_TABLE_PTR`
  (0x197F10/14, heap, assumed unmoved like the other heap pointers). Confirmed working on v1.0 by the user (field), so those heap pointers did not move.
- World map (v1.1, user report: doesn't work). `request()` also refuses unless a field screen is idle, but
  the real gap is that the WM is a different scene:
  - `scene_dispatcher` (`0x800c9ad0`) picks the next scene when a handler finishes, from GAMESTATE
    (`save+0x1bbc`): 1 -> `0x801279e8` (WM), 2 -> `FUN_80130ec4` (field), 3 -> `0x800ddf98` (battle),
    4/5 -> `0x80125dc0`. So any scene that sets GAMESTATE=3 and returns reaches the same battle loader.
  - WM battle start is `0x801285a4` (undefined function in Ghidra): sets save `+0x1d5e=1`, `+0x1d5f=0x80`,
    PREV_GAMESTATE(`+0x1bb8`)=1, GAMESTATE=3, `save+0x1bb4 = *(*(s1+0xc))` with `s1 = *(DAT_8017a0b8+0x2c)`,
    then installs `0x80128644` as the handler. Nothing calls it with a jal, and no main.exe code in that
    range writes the group index `+0x1bc0`: the WM roll / group pick is probably in the WM overlay
    (per-region `*_data.bin` in the Ghidra project), not yet located.

### 2026-10-24 world-map forcing: traced and working (v1.1 headless, `ForceBattleWorldMap.State`, WM 11/0/0)

- Walked into a real WM encounter (alternating d-pad, deterministic: gamestate 3 at frame 1442). Per-frame change log
  (the `event.onmemorywrite` hooks in this build logged nothing for these addresses, so polling was used):
  fr 1441 slot1 `0x801280c4` -> `0x801285a4`, `0x1B9BC0` 8 -> 6; fr 1442 slot1 -> `0x80128644`, `0x1B9BB4`
  -> `0x80095d4c`, PREV_GAMESTATE 2 -> 1, GAMESTATE 1 -> 3, `save+0x1d5e` -> `0x8001` (set by wm_battle_start).
  The WM roll itself is in the WM overlay (not located; not needed).
- Forcing = write group to `0x1B9BC0` and slot 1 := `0x801285a4` while slot 1 == `0x801280c4` and GAMESTATE == 1.
  All 13 groups of the table start (4 frames), group 6 matched the real encounter's slots (2,2,0,0,0,0).
- v1.0 derived the same way (pattern match, immediates masked): WM_MAIN_RUNNING `0x80128274`, WM_BATTLE_START
  `0x80128754` (both +0x1b0), WM_CTX_PTR 0x17a0b8 -> 0x17d604 (`lw ...,-0x29fc` under lui 0x8018). Confirmed working live on v1.0 by the user (world map and the Toolbox tool).
  The game has no scripted world-map fights, so the world map needs no scripted path.
- The earlier ForceBattle v1.0 fix was confirmed by the user ("1.0 worked this time").
