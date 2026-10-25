# Party change (Admit / Eject) - 2026-10-10

Goal: add/remove party members from Lua. Deliverable:
`scripts/PartyChange.lua` (tests: `scripts/TestPartyChange.lua`,
`scripts/TestPartyChange2.lua`).

## Where the menu lives
- "Admit to party" / "Eject from party" / "No change" are charmap strings in
  ~30 per-room overlays (`vac`, `va3`, `vb2`, `vb5*`, ...), NOT main.exe.
  Found by byte-searching the encoded strings over the unpacked disc.
- Savestate RAM: `Core.bin` is zstd; MainRAM starts at offset 0x1cb18.
- In `vac.bin` (loaded at 0x80010000): init 0x8001007c, tick 0x800100e8
  (state byte at struct+0, cursor at +1; struct ptr in DAT_8007d074),
  dispatch 0x80010568 (0 -> Admit 0x80012180, 1 -> Eject 0x80012f38,
  else exit 0x800105c8). Callbacks live in the entity slot `obj+0x498`;
  `obj+0x494` is the entity's event-script pointer. The menu is opened by a
  room-script command, so it is room-specific.

## Engine primitives (main.exe, resident everywhere)
- `0x800c48d4(charId)` claim slot + start CD read -> slot (-1 = fail)
- `0x800c2fa4()` CD sync, 0 when done
- `0x800c49b8(slot)` append to FORMATION_POSITIONS, PARTY_SIZE++
- `0x800c4afc(slot)` remove; PARTY_IDS[slot] = 0xff, PARTY_SIZE--
The overlay reaches them through a vtable at 0x80165608 (+0x8, +0xc, +0xcc,
+0xd8). Adding needs the CD read, so poking PARTY_* bytes is not enough.

## Calling game functions without emu.setregister
BizHawk's PSX core has no setregister. `main()` (0x800c26d4) calls the
function pointer at DAT_8017da90 once per frame (`jalr` at 0x800c2868).
`PartyChange.install()` writes a 120-byte MIPS stub to free BSS at 0x80181000
and points DAT_8017da90 at it. The stub reads a mailbox at 0x80181100
(flag, fn, a0..a3, result, orig handler, heartbeat, done), calls fn from
inside the game's own frame, then tail-jumps to the original handler.
Data pointer, so no icache issue. Scene changes can rewrite the pointer;
`keepInstalled()` re-wraps it.

## Verified (PartyMenuGregminsterClosed.State, headless)
- Remove/re-add of the 3rd member restores PARTY_IDS/FORMATION and the
  stats-pointer chain exactly.
- Added ids 2, 6, 1 (never in the party): chain resolves to the matching
  records in the stats table (0x1b8294 + 0x50*n), levels match. Removed
  all three cleanly. Hook stayed installed for 180+ frames.

## Not done / caveats
- Scene-handler pointer survived in this room only; other scenes untested
  (battle swaps DAT_8017da90 heavily). Re-wrapping handles it in theory.
- No check that a character is actually recruited; the primitive doesn't.
- 0x80181000 is zero BSS in both states, not proven unused everywhere.
- An overlay-based `openMenu()` was not built (needs the room script).

## Toolbox integration (2026-10-10)
- Library moved to `lib/PartyChange.lua` (adds a queued API: `queueAdd`,
  `queueRemove`, `cancel`, `tick`, `projectedSize`); `scripts/PartyChange.lua`
  is the standalone wrapper. Menu: `modules/Toolbox/Tools/PartyMembers.lua`;
  Toolbox worker ticks the queue (`RunInBackground = true`).
- Menus run while the emulator is paused and MenuController calls
  `worker:run()` in a tight loop then, so `tick()` only acts when
  `emu.framecount()` changed - otherwise queued jobs time out while the
  player is still in the menu. Blocking `call()` can't be used from a menu.
- `install()` was hardened after the first user run: it only uses a RAM
  block that is all-zero or already holds our stub (mailbox patched into
  the stub's lui/ori so the block can move), and refuses an invalid handler.
- Recruitment byte: 0 = not recruited, non-zero otherwise (Cleo 2, Pahn 66
  seen). `Addresses[name].Id` equals the PARTY_IDS value.
- Verified headless with `scripts/TestPartyMembersMenu.lua`.
