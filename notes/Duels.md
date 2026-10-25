# Duels: notes

This is the investigation history behind
[docs/game_mechanics/Duels.md](../docs/game_mechanics/Duels.md).

## 2026-10-01: static RE

- Found the overlay by charmap-encoding "Taste the sharpness" and grepping
  the disc. Only `12_ikki/shu_kwa.bin` matched. The header pointers
  (`0x8008102c`...) give the `0x80080000` base.
- There are no direct `jal rand` calls in the overlay. Every engine call
  goes through `*(*(0x800a1d64)+0x1bc4) + slot`. A byte search for
  `lw v0,0x90(v0)` found exactly two sites, and they are the same in all
  three duel files.
- I identified the table as main.exe `0x80165608`. It's the only place that
  matches all of these: slot 0 is `printf` (used with
  "IKKI_SHOW_COMMAND CASE %d"), `+0x90` is `rand`, and `+0x160` is
  `battle_compute_ally_derived_stats` (called with an 8-short output).
  I haven't read the runtime pointer live.
- The dialogue row table is at `0x8008a0bc` in shu_kwa. It is 10 rows of
  3 pointers. `duel_round_start` indexes it with `[+0x7dc][+0x7d0]`.
  `+0x7dc` is copied from `+0x7d8` (the outcome) in the branch delay slot
  of the call to `duel_pick_enemy_move`, so the row is the previous round's
  outcome.
- The outcome animation scripts are interpreted by `duel_run_actor_script`
  (opcode table `0x8008a3f8`, 15 ops). Hits are set by op 14 on the
  script's own side. The scripts sync through op 6 (signal) and op 9
  (waitsig), which is how I derived the hit order.
- Script opcode lengths, in shorts: 0:1, 1:1, 2:9, 3:2, 4:2, 5:1, 6:2, 7:1,
  8:1, 9:2, 10:4, 11:1, 12:4, 13:2, 14:2.

## 2026-10-01: live capture (one-off script, since removed)

Start conditions: `KwandaDuelPreStart.State`, seed `7bf604db`. McDohl was
at HP 220/301 with STR 125 and DEF 84. I played Desp, Def, Atk, Def, Desp,
and McDohl lost in round 5.

- Every RNG change was exactly 1 LCG step, and each one fell on a round
  start or a hit frame. Nothing else (VFX, idle animation) touched the RNG.
  The 8 advances matched the model's count. Def vs Def was 1 call.
- The enemy moves were 0, 1, 2, 2, 1, giving outcomes 7, 5, 3, 6, 8. The
  dialogue rows were 0, 7, 5, 3, 6, and the HP after each round matched
  `Duel.playRound` exactly. The final RNG was `03531a8e` in both the
  capture and the simulator.
- The hit order was confirmed live. In outcome 7, the player takes 66
  before the enemy takes 100. In outcome 3, the enemy takes 50 before the
  player takes 132. Side 0 is the player.
- The live struct matched the static reading: `+0x7d0` enemy move, `+0x7d4`
  player move, `+0x7d8` outcome, `+0x7dc` row, and side records at
  `+0x6a4`. The STR/DEF of 125/84 were read from the duel struct. I didn't
  cross-check them against `computeAllyATKDEF`.

- The capture script's KO stop didn't fire: it checks the last logged line,
  and that line had already moved past `0x80087bd8`. The run sat at Game
  Over until the timeout. I fixed it with a sticky flag.

## 2026-10-01: variance capture (one-off script, since removed)

Start conditions: `TeoMcDohlDuel.State`. The duel struct is live from
frame 1. McDohl was at 324/324 HP with DEF 88, and Teo at 180/360 with
STR 240 and DEF 105.

Edits, all in-spec and all in the duel struct only:
- McDohl's duel STR set to 330, which gives base 225 against Teo.
- Both sides' HP refilled to their own max at every command menu.

- My first attempt read `0x800a1d6c` and never saw the duel. The pointer
  to the duel struct is an overlay global, and it moves between files:
  shu_kwa `0x800a1d6c`, shu_teo `0x800a1dd0`, pan_teo `0x800a2340`. The
  code is the same at the same addresses, but data grows and bss shifts.
  Check the `lui/lw` in each file before reusing an address.
- 6 seeds (the savestate's own plus 5 written at frame 1) gave 24 rounds
  and 34 hits, covering all 9 outcomes. (One-off script since removed.)
  re-simulates each round from the live round-start RNG and the live
  pre-resolution HP/STR/DEF. Every enemy move, dialogue row, outcome, hit
  damage and post-round RNG matched.
- Variance was observed in both directions. For base 152 the bonus is
  `rand()%10` (154, 155, 158...). For base 225 it is `(2*rand())%10`,
  so even offsets only (225, 229, 231, 233).

## Still open

- McDohl's STR/DEF before the edit (from `battle_compute_ally_derived_stats`)
  haven't been cross-checked against `computeAllyATKDEF`.
- `pan_teo.bin` (Pahn vs Teo) hasn't been captured. Its code matches the
  others, and its data was read statically.
