# War battles: notes

Investigation history behind `docs/game_mechanics/War_Battles.md` (not yet
written; this file is the running log until the findings settle).

## 2026-10-11: first pass (Kuwa / Kwanda, Panna Yakuta Castle)

Start states: `KwandaWBStart.State`, `KwandaWBT1.State`.

- `data/16_war/` has 9 scenario overlays (`war_kuwa`, `war_gara`, `war_sca1`,
  `war_sca2`, `war_teo1`, `war_teo2`, `war_kita`, `war_shas`, `war_last`)
  and `war1.bin`, which is a text event-script file ("STEP WAR_MAIN"...),
  not an engine. Each scenario overlay is a flat image loaded at
  `0x80010000` (byte-identical to RAM, checked against the T1 state), and
  contains both code and data. Imported into Ghidra as `war_kuwa.bin`
  (PSX:LE:32, base `0x80010000`).
- The overlay never `jal`s `rand`. It stores the target in the global
  function pointer `0x800a7798` and does `jalr` (rand = main.exe
  `0x80147e38`, the BIOS A0:2F stub). Byte-searching for `jal` to rand finds
  nothing; search for `lui 0x8014; ori 0x7e38` instead (34 sites in kuwa).
- Unit counts: `0x800a7350`/`0x800a7680` = player u16, `+2` = enemy u16.
- Damage resolution is `FUN_8001b610` (round resolver). Pending losses are
  u32 at `0x800a7488` (player) and `0x800a7490` (enemy). They are set on the
  first frame after confirming (f=355 in the T1 replay) and then drained at 5
  units/frame per side (`FUN_8001839c`), starting ~14 frames after the roll.
- Charge vs Charge verified on 6 seeds (exact): 
  enemyLoss = 100*(pPow + pCount/3000) + r1/537 - 30,
  playerLoss = 100*(ePow + eCount/3000) + r2/537 - 30, where r1, r2 are the
  first two `rand()` results (15-bit) after confirming, in that order.

### Static RE results (war_kuwa.bin, Ghidra)

- Overlay header (`0x80010000`): word table of entry points. `[0]` init
  (`0x80010340`), `[1]` per-frame `war_main_phase_dispatch` (`0x80010368`),
  switch on `a7760` ("phase"): 0->1, 1 = pick enemy action (`FUN_8001afdc`)
  + build command menu, 2 = command menu (`FUN_80014a48`, sub-state
  `a76a8`), 3 = round state machine (`FUN_8001d488`, state `a77a8`), 4 =
  "Others" command (`FUN_80020154`, state `a7700`), 5-7 = intro/outro, 8 = end.
- Round state machine: 0 init, 1 player shout, 2/3 enemy announce, 4 =
  resolver `FUN_8001b610`, 5 = soldier animation (`FUN_8001c228`), 6/7 =
  other animation variants (magic), 8 = results panel (applies losses to the
  real counts at `a7680`), 9..0x10 = post-round banter (random character),
  0x13 = wait-for-sprites (jumps to `a77d0`), 0x14 = round end (win/lose
  check, buff countdown, turn counter).
- Resolver constants (identical in kuwa/gara/sca2/kita/shas/last):
  Charge-Charge 100/100, Bow-Bow 90/90, Charge beats Bow 130 (enemy) / 80
  (player), Bow beats Magic 120, Magic 200; see the docs file for the table.
- Per-scenario differences across the six same-layout overlays are tiny:
  soldiers-per-sprite divisor (`0x800183a4/f8`, `0x80018ad0`: 300 kuwa/gara,
  400 sca2, 450 kita, 500 shas, 600 last), starting enemy count (`0x800105e8/fc`:
  9000 except kita 3700), and last has a 6-entry enemy turn script (cycle
  constants `0x8001afb0`/`0x8001b100`) and its own char/group tables.
  sca1, teo1, teo2 have a different layout (special rules).

### 2026-10-11: dynamic findings (kuwa)

- Live checks: all 9 matchup cells, Magic tie roll boundary (r=19436/19437),
  Thief buckets (8 seeds), Merchant gain (3 deficits x 5 seeds), Strategist
  (buff = unit power), Ninja, Dragon Knights (1/4 of enemy, Bow counter).
- The war starts with `rand` seed `0x43` (RNG.md reset table). The T1 state
  is exactly 251 `rand()` calls later: 100 for the sprite entrance
  positions (2 per sprite, 50 sprites), 150 for the formation (3 per
  sprite) and 1 for the first enemy action pick. `scripts/python/WarSim.py`
  reproduces the T1 savestate's RNG and all 50 sprites from seed `0x43`.
- A round consumes ~8000-16500 `rand()` calls, almost all of it in the soldier
  sprite animation (about 1 call per running sprite per frame). So the
  seed at the next menu depends on the animation, which is pure code with
  no input dependence. The animation was ported (`scripts/python/WarSim.py`) and
  verified frame by frame (sprites, kill counters, RNG) against emulator
  dumps (`WarChainDump.lua`) for: Charge-Charge (2 seeds),
  Charge-Bow, Bow-Charge, Bow-Bow, Bow-Magic, Magic-Bow, Magic-Charge,
  Charge-Magic, Magic-Magic (win and lose). Then full 3-4 round chains
  (`WarSimCompare.py`): RNG at every command menu, soldier counts and enemy
  action all match.
- The 13-frame waits (state 0x13) and the magic effect tick are the only
  non-sprite timings that matter: the tick (FUN_8001e45c) is called once per
  frame in phases 0 and 2 but once per two frames in phase 1 (it calls a
  function that waits for vblank), 26 + 76 + 13 calls.
- GOTCHA: the user's own EmuHawk session wrote
  `BizHawk/PSX/Cheats/Suikoden (USA) (v1.1).cht` (a freeze on 0x0A7680 /
  0x0A7682) at 06:35. Every headless instance loads that file, which froze
  the soldier counts and made rounds look like they never applied losses.
  Workaround for the headless runs: copy config-headless.ini and point the
  PSX "Cheats" path at an empty directory (done in scratch, the file in the
  repo and the user's cheat file were left alone). If counts never change
  in a headless run, check that directory first.

### 2026-10-11: scripts and how to extend

- `scripts/python/WarDataDump.py`: per-scenario tables from the overlays (enemy
  counts, action tables, turn scripts, soldiers per sprite).
- `scripts/python/WarSim.py`: the reference implementation (see its docstring);
  `scripts/python/WarSimCompare.py` replays a `WarChainDump.lua` recording and checks
  it. `WarChainDump.lua` (also used for single forced rounds):
  a list of commands (`{category, unitIndex}`, or `{3, groupId}` for Others;
  `patch` lists war ids to make available so Merchants/Ninjas/Dragon Knights
  show up). Both write `Lua/Output/*.bin`, a frame stream with the RNG, the
  round globals, the sprite arrays, the fx pool, the arrows and the knight
  pool.
- Writing the RAM dumps offline needs the `.State` layout: zip, `Core.bin` is
  zstd, MainRAM at `+0x1cb18`. The RNG is NOT at `RAM[0x9010]` of that
  blob for these states (it read `0x35a4`; the live value is
  `0xe9acc066`), so read the seed with Lua.
- `scripts/disc_extract` style helpers: the `jal`-less rand access. The
  overlay stores `0x80147e38` in the global `0x800a7798` and `jalr`s it;
  find rand call sites by the `lui 0x8014; ori 0x7e38` pair. A Ghidra
  `decompile` shows them as `(*(code *)&SUB_80147e38)()`.
- Ghidra: each war overlay is imported as `war_<name>.bin` (PSX:LE:32:default,
  base `0x80010000`). `switch_program` before decompiling: the BSS
  addresses of the scripted overlays differ by thousands, a wrong program
  decompiles plausible-looking nonsense.
- sca1/teo1: the command menu (`FUN_80013478`) ends the battle when the
  turn counter equals 1 / 3 (outcome 8). teo2 has no such check.

### 2026-10-11: Teo 2 (user states + brute-force sheet)

- Teo2WBStart.State seed 0x42; T1 = 256 calls later (sim `start_battle('teo2')`
  reproduces seed `0x35af7b42`). Overlay differs from kuwa only in the resolver,
  the state-5 handler (2 extra rands per player sprite when a run ends) and the
  3-entry turn script. Found with a token-level difflib over the code range.
- All globals of this overlay are kuwa's + 0x1350 (e.g. soldiers `0x800a89d0`).
- The victory screen consumes 3*(cap0+1) rand calls (found from the sheet's
  Index being 3k above the sim); added to WarSim for every scenario.
- The sheet row `19 24 25 15 17` differed by 10 calls: the player confirmed
  turn 5 while sprites were still walking (user's hint). Reproduced with
  gap=276 frames. `scripts/python/WarTeo2Check.py` + a 22 row sample in
  `scripts/data/`. The user has ~900 rows; ask for the file to check them all.

- Full sheet: 635/720 exact; 62 more exact with a constant gap (mostly 276, 320-324
  for rows starting with 36); 23 left (per-round gaps?). Gap = frames after the round's
  wait2 until the next resolver.

### 2026-10-11: static pass over all overlays

- Token-level (opcode+registers) diff of every overlay against kuwa, then immediates: gara/sca2/
  kita/shas/last differ only in the documented constants (kita also a graphics pointer at
  0x80010a7c). teo1, sca1, teo2 differ in the resolver (+ teo2's state 5 handler).
- teo1/sca1 extra: the menu turn limit (turn == 3 / 1 -> outcome 8) and no write of
  0x8017c0f8 for outcomes 5/8. main.exe 0x80125fcc reads that flag and sets gamestate 99
  (GAME_OVER). So those two are the scripted losses; everywhere else outcome 5/8 = game over.
- Both added to WarSim (static only): teo1 loses 130*P+roll per round, sca1 loses (p*8)/10.

## Command menu unit order (solved)

- List built by `FUN_80014f24` (group order), sorted by the BIOS `qsort` (`0x80147d48` =
  A(0x31)), comparator `0x80014eb4` on `FUN_8001aa30` (unit power), highest first.
- The BIOS (`~/Local/BizHawk-2.10-linux-x64/Firmware/PSP660.BIN`, the one BizHawk uses) has
  its A table at file offset `0x4300` (181 entries); entry 0x31 is the qsort wrapper
  `0xbfc03098` (mallocs a width-sized temp, calls the quicksort `0xbfc02f20`, frees it);
  swap is `0xbfc03104`. The earlier scan of
  `~/.mednafen` was out of scope (user correction); only the BizHawk firmware is relevant.
- Live test: `scripts/WarMenuOrder.lua`, 60 trials from `TeoWB2T1.State`; the K&R-style
  quicksort in `WarSim.bios_qsort` reproduces all 60 (ties included). Doc section
  "Command menu order" in `War_Battles.md`.

## PSTV divergence (started 2026-10)

- Report: on PSTV (same disc and BIOS) Charge vs Charge diverges from BizHawk/WarSim in some wars (Kwanda,
  Scarletia 2); Magic never does; Bow unknown. No idle seed drift at the menu; first-menu seed matches.
- Data point (kuwa, recruited ids as in KwandaWBT1, seed 0x43): Magic(27), Magic(28), Charge(0). Sim ends at
  index 10867, seed 0x6620060e, 4452 left (matches the user's own tool). Console: index 7689, seed 0xb147d7d8.
  Both are on the same LCG stream from 0x43 (index 7689 -> 0xb147d7d8), so no foreign rand() source; the
  console made 3178 fewer calls in the Charge round (7394 vs 10572; sim round = 769 frames).
- Sim menu seeds to check on a console: after R1 index 272 seed 0x242e5f33
  (enemy 5200/player 5625), after R2 index 295 seed 0x035c23aa (2600/5625).
- Round totals are chaotic: shifting only the wait before the animation (UI_WAIT) gives 4.5k..9.3k calls for
  1-frame changes, so the size of a call-count difference says nothing about the size of the cause.
- Fault search against the console fingerprint (index 7689 + seed), none matched: rand offset -150..150 before
  the round, every sprite x/y low nibble 1..15, fx slot nibbles, one extra sprite update at frame 1..799,
  sprite timers +-1, UI_WAIT 0..199 (see scratchpad scripts, not kept). Early confirm is not involved here:
  no sprite is walking after a Magic round.
- Needed: more console data points (short chains, result soldiers), see the chat plan.

### PSTV: cause found (one data point, 2026-10)

- Console video timing for Magic, Magic, Charge (kuwa): first movement 267254, results 267820 (566 frames,
  BizHawk and sim 769). Losses 1173/2600 identical everywhere. Death frames from first movement (frame 1):
  console P 129 176 180 204, E 169 203 237 344 352 406 419 452 492; sim P 129 176 204 228,
  E 169 237 296 474 595 647 663 667 695. The first two deaths per side and P2 match; the first
  mismatch is P3 at 180 (sim 204). The round ends 74 frames after the last death on both.
- Fault search against (index 7689, seed 0xb147d7d8): the 6th set_course call of the round
  (player sprite 5, a fast runner) with timer one lower is an exact hit (13 of 13 deaths, 566
  frames, index, seed). Pixel-level scan: only player sprite 5 x lowered by 12..28 units (and sprite 12
  by 21..24) hits. Sprite 5 sits at x = 1556 in the sim after the second Magic round.
- Mechanism that fits: in the second cast the course of sprite 5 is |dy| < |dx| with dx = +1 so
  set_course takes the X branch with timer = (1552 - 1544) / 12 = 0 and sets state 0 (it does not compute
  vy). `FUN_80016bec` (cast) then stores state 2 (`sb` at 0x80016d54 / 0x80016f1c), so on
  BizHawk the sprite takes one extra step (x += vx = 12: 1544 -> 1556). Making that store not apply when
  set_course left state 0 with timer 0 (x stays 1544) reproduces the console exactly. Every other zero-length
  course in that cast is in the Y branch (state 2 from set_course), so only sprite 5 differs.
  The same `set_course` + `state = 2` pattern is in forming up (`FUN_800174a0`).
- Why Magic never diverges: the cast only changes positions (12 units); RNG use in Magic does not depend on
  them. The next Charge reads the positions. The first Charge round of a battle matches because the sprites
  come from the first formation.
- Unknown: why the console skips the step. Not a division, GTE (no COP2 in the overlay), or sound issue as far as seen.
  `SUB_800c3dac` (sprite animation call) runs inside set_course between the vx store and the timer division and
  is not decoded (outside the overlay image). Ask for a sprite array dump at menu 3 to see x of sprite 5
  (sim 1556, console expected 1544) and every other sprite.
- Code: `WarSim.start_battle(..., pstv=True)` / `Battle.pstv_walk` model it; default off. Nothing else changed
  (WarSimCompare chainA and rnd0 ALL OK, Teo 2 sample unchanged).

### PSTV: corrected (console read of sprite 5, 2026-10)

The "skipped extra step" model above is superseded; it matched the fingerprint only because it gave the same
timer. Console read at menu 3 (A0 = 0x80188a88, `[[0x800a76b0]]`): sprite 5 x 1530, y 1429, tx 96, ty 89,
state 0, timer -1; sim has x 1556, y 1428, tx 97. Only tx differs in the cause: a circle target one
pixel lower. The sim reproduces x, y, tx, ty and the whole fingerprint (index 7689, seed 0xb147d7d8) with
`start_battle(..., cast_angle_bias=1)` (every circle angle +1), or by any change that lowers sprite 5's rcos to
<= 719 (sim 725); the step-228 variant also gives sprite 5 right but not the fingerprint (other sprites move).
- Cast: `a = (0x1000 / (alive - 1)) * k` (4096/18 = 227; sprite 5 is k = 4, a = 908), then
  `rcos(a)` (`0x801508ec`) and `rsin(a)` (`0x80150810` -> `0x8015084c`) read static tables in main.exe:
  quarter table at 0x801765bc (index 0..0x400, halfwords), more at 0x80175dbc and 0x80174dbc. cos(908) reads
  index 0x400 - 908 = 116 = 0x801766a4 = 725. Index 115 (0x801766a2) = 719, 114 = 713, 117 = 731.
- Open: which of (a) the table entry in console RAM differs, (b) the angle is 909 (integer step/mult),
  (c) something else. Next console reads: s16 at 0x801766a2/a4 (expect 719/725), and tx/ty of sprites
  4, 6, 7, 13, 14, 16, 17, 18 (see chat). Sim tx/ty with +1 angle differ from the current sim only for sprite 5.
- Code: the `pstv_walk` flag was removed from WarSim; `cast_angle_bias` is the knob (default 0).

### PSN build identified (MEMDUMP0.dmp, 2026-10): cause confirmed

- User's console: PSN classic through Adrenaline. Full 2 MB RAM dump at menu 3 of the chain
  (dumps/MEMDUMP0.dmp; seed 0x035c23aa, p 5625, e 2600, A0 0x80188a88).
- Overlay: the dump's war overlay equals `war_kuwa.bin` except 727 relocated address immediates
  (one consistent old16 -> new16 mapping, no jal changes) and 6 padding words. `rand` is the same BIOS
  A(0x2f) trampoline (0x801477cc here, 0x80147e38 on the disc). So the game logic is the disc's.
- main.exe: relinked; the library's `rsin` (0x80154c20) / `rcos` (0x80154d28) differ: same table (Q[0..0x3ff] equals
  round(4096 sin) and the disc table), but cos in quadrant 1 reads Q[0x3ff - a] (disc: T[0x400 - a]) and
  sin mirrors at 0x7ff / 0xfff. See docs "PSN build". Implemented as `WarSim.rsin_psn` / `rcos_psn`,
  `start_battle(..., libgte='psn')`; the earlier `cast_angle_bias` knob and the "skipped step" idea are gone.
- Expected: a divergence needs a sprite whose circle target lands on a rounding boundary (here sprite 5, k = 4,
  a = 908: 725 vs 719 around the step 6/7 at 720), then a Charge round. Other wars (Scarletia 2) should fall
  out of the same switch; untested.
- Open: other main.exe library differences (qsort A(0x31) and A(0x30) trampolines match; the UI/GTE/sound
  routines were not compared, they do not touch the rand() stream).

### Default is now PSN; BizHawk patch (2026-10)

- `WarSim.start_battle` / `Battle.libgte` default to 'psn' (runs are on the PSTV). `WarSimCompare.py` and
  `WarAnimCompare.py` default to 'disc' because the stored recordings are plain BizHawk; pass `--psn` for a recording
  made with `PSN_PATCH = true` in `WarChainDump.lua`. All eight chain recordings and the Teo 2 sample still match.
- BizHawk patch: `scripts/WarPsnPatch.lua` (10 instruction immediates in the disc's rsin/rcos, checked before
  writing, applied after each `savestate.load`). Offline check (one-off unicorn script, since removed): unpatched
  disc routines match WarSim's disc rsin/rcos on all 8193 angles, patched match rsin_psn/rcos_psn on all.
  The disc's boundary cases (angles 0x400, 0x800, 0xc00) needed the `slti` bounds changed too: with only the
  mirror constants patched they would read the halfword before the table (4096).
- Not yet run in the emulator. Possible catch: the CPU instruction cache keeping old copies of those lines.
  First live test to do: WarChainDump with PSN_PATCH = true on Magic, Magic, Charge; expect index 7689, seed 0xb147d7d8.

### BizHawk PSN patch: live result (2026-10)

`scripts/WarPsnTest.lua` (headless, scratch config, no cheat file): from KwandaWBT1.State, Magic, Magic, Charge.
Plain: menu seeds e9acc066 / 242e5f33 / 035c23aa, ends 6620060e (= sim 'disc'). Patched (applied right after the
state load, before the first Magic): same menu seeds, ends b147d7d8 (= console, = sim 'psn'). Menu-3 sprite arrays of the
patched run equal the console dump (MEMDUMP0.dmp) for every living sprite; the plain run differs at sprite 5 only.
No instruction-cache problem. Remaining use: record frame-accurate PSN-behaviour data (WarChainDump `PSN_PATCH = true`,
compare with `--psn`).

### PSN files (SLUS00292/, 2026-10)

- `EBOOT.PBP`: PSP-format PS1 classic. PARAM.SFO: TITLE Suikoden, DISC_ID SLUS00292, DISC_VERSION 1.00, region US,
  PSP_SYSTEM_VER 3.71. `DATA.PSAR` (334 MB) starts `PSISOIMG0000`, but its disc data (offset 0x400) and `DOCUMENT.DAT` begin
  with the `\\0PGD` magic: PGD-protected (account-bound). `__sce_ebootpbp` = `NPPS1SIG` signature, `__sce_menuinfo` = POPS.CFG.
  Not readable without the protection being removed; not attempted. Only the user can produce a BIN/CUE from it.
- Dump vs disc, resident code (heuristic: first 24 instructions with immediates and jal targets masked, functions found by
  `addiu sp` prologues in 0x80100000..0x801a0000): disc 624 functions, PSN 644; 451 disc functions have a counterpart, 173 do not.
  Example: disc 0x80128e64 (112 instr) vs PSN 0x80128f68 (116): same body, an init sequence with its `jal`s reordered and
  extra calls (one with `a0 = 1`). So the PSN executable is more than a relink with a different libgte; other code differs.
  Not analysed further (needs more dumps from other states).

### The PSN build is the USA v1.0 disc (2026-10, `/mnt/Shared/ISOs/Suikoden/Suikoden (v1.0).bin`)

- One-off build-identification script (since removed) on the v1.0 image: rsin and rcos code found in its MAIN.EXE at file offsets 0x94c20 / 0x94d28
  (load 0x800c0800 -> 0x80154c20 / 0x80154d28); 99.9% of MAIN.EXE text words equal the console dump (203 of 192512
  differ, all in runtime-modified data). The v1.1 image: 1.7%, not found.
- War overlays, v1.0 vs v1.1 (all 9): ~720-734 differing words each, all relocated immediates except 6-7 padding words;
  WAR1.BIN, WAR.VA, WAR.VB, W_HEADER identical. v1.0 `war_kuwa.bin` vs the console RAM: 112 differing words, all runtime
  state (availability/flag bytes and bss). So every war table is identical across versions; only main.exe's library
  moved and rsin/rcos changed. v1.0 MAIN.EXE 772096 bytes (v1.1: 757760), SLUS_002.92 600064 (v1.1: 593920).
- The character availability table is at 0x8018ebb0 in the console dump too (same ids as the Kwanda save), so the
  save/data layout used by WarChainDump is unchanged in v1.0.
- Consequences: BizHawk can run the v1.0 cue for PSN-exact behaviour (savestates are per disc; the v1.1 .State files do
  not carry over; the HUD's lib/Address.lua is v1.1 and its main.exe addresses will not all apply to v1.0).
  The `rsin`/`rcos` patch remains a way to get PSN behaviour on the v1.1 states.

### lib/Address.lua is build-aware (2026-10)

`lib/Address.lua` keeps the v1.1 table (V11) and a V10 override table (12 entries that moved: item table, encounter rate,
session frame counter, hero x/y/direction, room pointer/slot count, battle state pointer, the two VFX context pointers).
`Address.build()` reads the word at 0x1508ec (v1.1: 0x04810002, v1.0/PSN: 0xafbf0018, both checked against real RAM),
caches the chosen table as plain fields, falls back to v1.1 (not cached) while memory is unreadable;
`Address.setBuild("v1.0"|"v1.1")` forces one. Mock-memory test in the session scratchpad (5 cases) passes; not run on a live v1.0
BizHawk. Hard-coded addresses elsewhere in the HUD (function hooks, spell/item tables, e.g. Magic.lua) are NOT remapped.
(`tests/test_Magic.lua` fails under the system `lua`, which is 5.5 here: lib/Utils.lua:71 assigns a `for` variable. Use `lua5.4`; all nine test files pass.)

### Hard-coded addresses moved into Address files (2026-10)

- `lib/AddressBuild.lua`: shared build detection (probe word at 0x1508ec), `wrap(V11, V10)`, `setBuild`; one detection fills every wrapped
  table. Nothing is cached until the build is known, so do not copy addresses into module-level locals at require time.
- `lib/Address.lua` (globals/state; added MENU_STATE_PTR, SCENE_HANDLER_MAIN_LOOP/FIELD_MAIN/FIELD_LOADER/MENU, FIELD_CTX_PTR),
  `lib/AddressTables.lua` (RUNE_ABILITY_SET, SPELL_DEFINITION, ALT_ABILITY, UNITE_ATTACK, WEAPON_CLASS, WEAPON_POWER; v1.0 = +0x45a4),
  `lib/AddressFunctions.lua` (SoulEater handlers, FIGHT_MENU_HANDLER, PARTY_* functions, FIELD_MAIN_RUNNING, FIELD_LOADER_IDLE).
- Call sites changed: ActionEnumerator, BattleLogger, BattleSnapshot, BattleRoundInput, PartyChange (FN is now a lazy proxy),
  ScreenTeleport, SoulEaterCapture (`recipe.handler` resolves lazily from `handlerKey`).
- Checks: every v1.0 function address has the same 40 instructions (masked) in the PSN dump; every table has 64 words equal or
  pointer-shifted by 0x45a4; scene-handler slots/ctx pointers hold the expected function/heap values in the dump; v1.1 live
  (`scripts/CheckAddressBuild.lua`) and mock-memory tests pass; all tests pass under lua5.4.
- Left alone: comments (they cite v1.1 addresses), `scripts/` (one-off), overlay addresses (EnemyAIPredictor AI entry points, Duel
  structPtr: overlay files are the same in both builds), PartyChange.CANDIDATES (same zero/non-zero status in the PSN dump).

### Hero name address (2026-10)

`modules/Saves/lib.lua` used `Address.Names.HERO_2`, which never existed (added that way in commit 56ea502), so a blank
`CATEGORY_DIRECTORY` crashed. Found: game state + 0x1b74 = 0x1B9B74 (8 charmap bytes + 0 at +8); FUN_800c4ecc sets
DAT_8017c1d8 = gs+0x1b74 and DAT_8017c1dc = gs+0x1b84 (castle name), the text engine's name control code indexes that table
(FUN_80146bb4 around 0x80146c58). All BizHawk states read "Any" there, castle empty; the PSN dump reads "0" and castle "A".
Added `Address.HERO_NAME` / `CASTLE_NAME` (same in both builds: game state region); Saves/lib.lua falls back to "Unknown" if empty.
