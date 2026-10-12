# Saves, Character Editor, and Recruitment Editor

Covers savestate/autosave handling and the two Toolbox editors (Character
Editor, Recruitment Editor). See
[Characters_and_Stats.md](./Characters_and_Stats.md) for the character
struct these editors write to, and [Chinchironin.md](./Chinchironin.md) for
the other consumer of `SAVE_FRAMECOUNT`.

## Save system

Uses BizHawk's native `savestate.save(path)`/`savestate.load(path)` — full
emulator savestates, not in-game save files. There is no in-game save format
being parsed here; the whole machine state is snapshotted.

**Directory structure** (`Config.lua`, `Config.Saves`):

- `SAVE_DIRECTORY` / `AUTOSAVE_DIRECTORY` — configurable base folders.
- `CATEGORY_DIRECTORY` — subfolder name; if blank, falls back to the in-game
  hero name read from memory (`Address.HERO_NAME`, `0x1B9B74`: 8 charmap
  bytes plus a terminator; the castle name follows at `Address.CASTLE_NAME`,
  `0x1B9B84`). An empty name gives the folder `Unknown`.
- Final path shape: `SAVE_DIRECTORY/<category>/<save_name>.State`.
- `setupSaveDirectories()` lazily creates these directories if missing.

**Save file naming**: `"%02d:%02d:%02d-%s.State"`, formatted from IGT
hours:minutes:seconds and the current area/zone name (spaces → `_`), e.g.
`01:23:45-Gregminster.State`. A `-- TODO: Add events using event index and
state check` comment flags that special "event" locations aren't
distinguished yet — only world-map zone / area zone naming is implemented.

### IGT (in-game time) address uncertainty

Four candidate frame-counter addresses appear in `lib/Address.lua` with
explicit uncertainty comments — none is confirmed to exactly match what the
game itself would compute as true IGT:

- `0x1783f8` (`SESSION_FRAMECOUNT`) — **Active**, drives the HUD clock
  and autosave timing: "Kinda loadless, not completely accurate to save
  IGT"
- `0x18B0A8` — Abandoned, commented out: "Not sure how to calculate real
  IGT, missing some value"
- `0x17DBE8` — Never wired up, noted only in a comment: "(stops on
  loads?)"
- `0x1B9B8C` (`SAVE_FRAMECOUNT`) — **Active**, but repurposed: "(Updated
  on save)" — used for [Chinchironin](./Chinchironin.md) RNG, not for
  timing

`SAVE_FRAMECOUNT`'s IGT-sounding name is a documentation trap: despite the
name, it is not used for time display at all — its only current consumer
treats it purely as an RNG seed modifier. Anyone assuming it holds "the IGT
value used by savefiles" would be wrong.

The active `SESSION_FRAMECOUNT` derives H/M/S via `// 216000`, `// 3600 %
60`, `// 60 % 60`, `% 60` (assuming 60fps, 216000 frames/hour). Its own
comment admits it isn't exactly accurate to true IGT — meaning both the HUD
clock and autosave interval timing are approximate.

### Autosave logic

Every frame while the Saves module is active (`RunInBackground = true`):

1. Bail if `Config.Saves.AUTOSAVE_ENABLED` is false.
2. Bail unless IGT (derived from `SESSION_FRAMECOUNT`) just changed this
   frame (`.changed` flag) — only fires on the tick the derived value ticks over.
3. Bail if total IGT seconds `<= 0` (avoids autosaving before the clock starts).
4. Bail unless `igtInSeconds % Config.Saves.AUTOSAVE_INTERVAL == 0` (default
   interval: 300s / 5 minutes) — only autosave on exact multiples.
5. On a qualifying frame: `savestate.save(getAutoSavePath(getSaveName()))`.

Because this is gated on an imprecise IGT counter hitting an exact modulo
boundary "on change," any frame where the counter skips a value (e.g. a
large frame jump) could cause an autosave interval to be missed entirely —
there's no debounce/backfill.

The manual save menu is separate: Cross calls `savestate.save(...)` into the
normal `SAVE_DIRECTORY`/category folder (distinct from autosaves). The Load
State menu toggles between normal saves and autosaves, scrolls a directory
listing, loads (Cross), or deletes (Select) the selected file.

## Character Editor

Entry: Toolbox → Character Editor → character selection (only characters
with a `Stats` address — see
[Characters_and_Stats.md](./Characters_and_Stats.md) — appear here, i.e.
non-combat/support-only recruits are excluded) → three sub-tools: **Stats**,
**Inventory**, **Weapon & Rune** (a fourth, "Unknowns," exists in code but is
disabled).

All three sub-menus read the full 0x50-byte character struct at the top of
every `:run()` (live re-sync each frame) and write back immediately after
any edit (immediate write-through, not batched). See
[Characters_and_Stats.md](./Characters_and_Stats.md#character-struct-0x50--80-bytes-relative-to-stats-address)
for the byte layout.

- **Stats menu**: Max HP (cap 65535), Current HP (cap 65535), MP 1–4, LVL,
  EXP (cap 65535), PWR, SKL, DEF, SPD, MGC, LUK. Default cap otherwise 255.
  Up/Down move cursor; Left/Right adjust ±1 (×10 with R1, ×100 with R2).
- **Inventory menu**: `Items.Count` plus 9 item slots, each with `Id`
  (u16), `Equipped`, `Quantity` (capped at 255 by default). Item names
  resolved via `Battle.getItemName(id)`.
- **Weapon & Rune menu**: Weapon Class, Weapon Level, Equipped Rune Piece
  Type, 5 elemental Piece Counts (Fire/Water/Wind/Thunder/Earth), Rune ID,
  Rune Lock (all capped at 255). Its internal function is still named
  `local function StatsMenu(character)` — a copy-paste leftover from
  `StatsMenu.lua`, cosmetic only.

## Recruitment Editor

`modules/Toolbox/Tools/RecruitmentEditor.lua` filters the full character
name list down to anyone with a `RecruitmentState` address — this includes
many non-combat/story characters alongside playable ones.

`Address.RECRUIT_FIRST_SLOT = 0x1B9AF4` is the base of a contiguous,
108-byte, one-byte-per-character array (`0x1B9AF4`–`0x1B9B5F`, matching
every `RecruitmentState` address found across the roster — see
[Characters_and_Stats.md](./Characters_and_Stats.md#memory-layout)). Slot
position = `character.Address.Recruited - RECRUIT_FIRST_SLOT + 1`
(1-indexed for Lua).

**Value semantics are not a simple boolean.** The editor treats each byte as
a numeric "Recruitment State" (Left/Right ±1, ×16 with R1, displayed in
hex), but **no enum or lookup table exists anywhere in the codebase for what
specific values mean** (e.g. "not met" vs. "met" vs. "recruited" vs. "in
castle"). This is left entirely to the operator's own game knowledge.

The 108-byte ordering is **not** alphabetical or in `Names`-enum order — it
appears to loosely follow in-game recruitment order at the low offsets
(GREMIO, EILEEN, CLEO, CAMILLE, KIRKIS, ...), but this is unverified against
disassembly.

## Party Members

`modules/Toolbox/Tools/PartyMembers.lua` adds and removes party members
without the in-game Admit/Eject menu. It lists every combat character that
is in the party or has a non-zero recruitment state (`[P]` marks the current
party). X queues an add or remove (X again cancels it); the hero (id 8) can't
be removed, the party can't exceed 6 or drop below 1.

Menus run while the emulator is paused, and the game only runs the change
from inside its own frame, so changes are *queued* and applied by the
Toolbox worker (`RunInBackground = true`, one step per emulated frame) once
you unpause. Progress and results show at the bottom left.

The mechanism (a stub in free RAM wrapping the main-loop scene handler, so
Lua can call `main.exe`'s party add/remove functions) is `lib/PartyChange.lua`;
`scripts/PartyChange.lua` is a standalone runner with an `ADD`/`REMOVE`
list. See `notes/Party_Change.md` for the reverse-engineering.

## Screen Teleport

`modules/Toolbox/Tools/ScreenTeleport.lua` loads any field screen by
WM / Area / Screen (Up/Down picks the field, Left/Right step through the
screens that exist, L1/R1 jump 10, X teleports). Each field shows its name
(WM, area and screen info from the zone spreadsheet, WM 0-3 only; other areas
are unlabeled). Only real screens are offered: `lib/ScreenList.lua`, generated
by `scripts/BuildScreenList.py` from the static overlay scan, with the zone
sheet (`outputs/ZoneSheet.tsv`) for labels. Screens with no actors are included (their scan record has an empty actor list).
Screens that failed the teleport test are still listed, labeled
`BROKEN (reason)`. A fourth field, Entry, picks
where the hero arrives (the destination tile of one of the game's own doors,
with the screen it comes from). The first entry is the most-used door from
another screen. Screens with no known entry (105, mostly area entrances from the
world map and cutscene screens) can't be teleported to. It only works while a
field screen is idle. The request is queued and run by the Toolbox worker
once you unpause; the result shows at the bottom left.

The mechanism is `lib/ScreenTeleport.lua`: it sets the field context's
"change screen" request (`+0x34`, with `+0x35 = 2`, `+0x37 = 0` so the area
overlay is reloaded), waits one frame, then writes the zone bytes and the
arrival tile (`gs+4`/`gs+6`, u16 X/Y, copied to the hero by the loader). Writing
the zones in the same frame as the request hung the game on about 17% of
screens. Not every listed screen was test-loaded (the sweep covered the 303 with actor slots). See
`docs/game_mechanics/Invisible_Actor_Glitch.md`.

Entry tiles come from the area overlays' event scripts: opcode `03` is
"change screen" (`03 S X Y fd` same area, `03 fc A S X Y fd` other area,
`03 fa W A S X Y fd` other WM). `scripts/BuildScreenList.py` searches each
descriptor's script (`+0x14`) for these. Checked against the Outside Room door
(`03 02 25 0a` = screen 2, tile 37,10, which is what the in-room save shows).
Opcode lengths are not tabulated, so scripts are searched rather than parsed;
a coincidental match also needs a real destination screen.

Headless test (`scripts/TestScreenTeleport.lua`, every screen with an entry,
first entry, from the Outside Room save): 832 of 845 put the hero on the
requested tile with the right zones. The 13 that don't are labeled BROKEN:
never loads (1/4/1, 9/4/1, 1/6/0, 9/6/0); arrival event moves the hero
(0/0/0, 11/0/0, 0/3/0, 1/41/0, 9/41/0, the last three off-screen); hero walks
in 3 tiles (1/5/6, 2/6/6); redirect to screen 0 (1/33/2, 9/33/2).
