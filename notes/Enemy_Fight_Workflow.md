# Enemy Fight Workflow (end to end)

The full process used for Ain Gide (2026-10-07), start to finish, for the next enemy. It sits on
top of [Enemy_AI_Tracing_Methodology.md](./Enemy_AI_Tracing_Methodology.md) (the AI-function
runbook; read its sections 0 to 6 for the gotchas) and
[Spell_RNG_Tracing_Methodology.md](./Spell_RNG_Tracing_Methodology.md) (cast state machines).
Reference implementation: `lib/Enemies/AinGide.lua`, `tests/test_AinGide.lua`, the "Ain Gide"
section of `docs/game_mechanics/Battle_Damage_Formula.md`.

**Goal:** for one enemy, an exact, live-validated model of (1) move and target choice, (2) the
RNG each move consumes and when, (3) frame timings of each move, (4) damage including the shared
formula's compiled bugs, packaged as a lib module, tests, docs and a hand-off brief.

Order matters: static first (cheap, tells you what to measure), live second (validates it),
write-up last. Total for Ain Gide: about one session, 3 headless runs.

## Rules for this repo (don't skip)

- Spawn captures only with `scripts/spawn-headless-emuhawk.sh <absolute lua path> "" <timeout>`,
  **one at a time**, never the user's own EmuHawk. The process may not exit after
  `client.exit()`; the output file is complete once the `Killed` message appears or the last
  record is written, so don't wait for the timeout blindly.
- Before a NEW live capture design, state the plan in chat and get a yes. A plan the user already
  approved can be rerun with a different seed count. Plain-text sign-off, not AskUserQuestion.
- Never `git checkout` / revert files you didn't change (this session wiped a pre-existing
  `config-headless.ini` modification). The user does all git.
- Test edits stay in spec (HP 999 is the real ceiling, Rune.Id real values).
- Doc table lines <= 80 chars. Add a dated line to `notes/` when a doc is corrected.

## 0. Inputs

A savestate at the start of a round with the enemy alive (round 1 is easiest), and the enemy's
name. If there are several enemies, you also need its actor index (party count + position).
Check `lib/EnemyAIPredictor.lua` `KNOWN_AI` and `Monster_AI_Static_Catalog.md` first. The AI
function address and "template" shape may already be there, but only as **structural** guesses
until step 5 validates them.

## 1. Find the AI function and its record (static)

1. `outputs/Bestiary.json` (`enemies[]`) gives name, stats, `aiFunctionAddress`,
   `actionScriptTableAddress`, `_sourceFile` and `_recordFileOffset`.
2. The catalog's address is the AI **function** pointer (record `+0x30`), not the record. Find the
   record in the overlay by signature (level byte, HP u16 at `+0x10`, `+0x12`) if you need it.
3. Import the overlay: `import_file(<data/.../xxx.bin>, language "PSX:LE:32:default",
   compiler_spec "default", auto_analyze false)`, `switch_program`, `set_image_base(0x80010000)`
   (wait for analysis: poll `analysis_status`). Overlays in `data/*` load at `0x80010000`
   unless the walker's `FILE_OVERRIDES` says otherwise.
4. `create_function` at the AI pointer, then at **every** continuation address the decompile
   stores into `param_1 + 0xc` (`LAB_...`) or `+0x54`/`+4` callback slots. Decompile each.
   Pass `program=<overlay>` to every Ghidra call.

## 2. Read the move selection

Decompile the AI function; match it to the template (see the "Target-selection template" in
`Battle_Damage_Formula.md`):

- target scan: alive `+0x45`, front row `+0x44 < 4`, busy `enemy_data+5`, one rand2 per
  candidate, `% 100 > 50`;
- move roll: `(rand*100)/0x7fff < N`. Return `-1` means plain Attack, anything else installs a
  continuation. **Check the polarity** by reading what each return value does.

Exact probability = count of rolls in `[0, 32767]` satisfying the test over 32768. For `< N`:
`ceil(N*32767/100)/32768`. (N=0x33 gives 16712/32768.)

## 3. Decode each move

- **Basic Attack:** run `python3 scripts/python/AttackTimingWalker.py "<Name>" 1 -v`. It gives impact,
  damage roll and done frames. Extra RNG on the commit frame is the executor's hit roll.
- **Special:** the continuation usually waits (no RNG) for an idle party, then plays a script
  (`play_attack_animation` via `*(base+0x1258)+4`). Decode it with the walker's own interpreter:
  `python3 -I` with `sys.path.insert(0,'scripts'); import AttackTimingWalker as W`,
  `W.load_monster(rec)` and `W.walk_self(loaded, slot, True, script_ptr=<addr>)`. It stops at
  the native handler (opcode 35, table slot 6) and names it.
- Decompile the handler and follow its callback chain (`+0x58 -> +4` pointers): setup, cue wait,
  particle create, **tick machine**. In the tick machine look for phase counters and tick
  constants: spawn ticks, reaction waves, the damage tick, the cleanup phase.
- Identify shared `RngCallbackTable` slots (table at `0x8016b680`, offset = slot*4; read it
  with `read_memory` and decode u32s). Known: `0x0` rand, `0x4` play_attack_animation, `0xc`
  calc_damage, `0x10` apply HP, `0xa4` particle create (no RNG), `0xcc`
  `vfx_activate_and_position_particle` (**2 rand()** per call), `0xe8` arc particle spawn (5),
  `0x158` `calc_rune_element_attack_damage`. Decompile any unknown slot in `main.exe` and look
  for `rand()`.
- Write down a predicted event table (frames from T0, S, P) and the RNG count formula **before**
  measuring. The point of the live run is to falsify it.

## 4. Static damage and bug check

- Find the damage call (`lw v0,0x158(v0)`, or slot `0xc`). Disassemble the loop and note: the
  `element` argument (`a2`), the **register holding the loop counter** (`a1`), and any extra
  halving after the call.
- `calc_rune_element_attack_damage` (`0x800f8174`) reads `$s1` for unlisted `Rune.Id`s. The bug
  fires only if the loop counter is `$s1` **and** `slot == element` is reachable (element 1 to 6).
  See "A compiled bug" in `Battle_Damage_Formula.md` and its table (rows still "untested" are
  leads, one rune sweep confirms each).
- Element ids: 1 Fire, 2 Water, 3 Earth, 4 Lightning, 5 Wind, 6 Resurrection; real resist when
  the target's rune category equals it, Soul Eater (7) resists everything; 8 = never resisted.

## 5. Live capture 1: trace the enemy's turn

Template: `scripts/TraceAinGide.lua` (copy it, change `SAVESTATE`, the enemy index and the
per-enemy fields). It loads the state, injects seed `0x1234567*s + 0x89abcdef` (s > 1),
sets the whole party to Defend via `BattleRoundInput:setAction(i, 1, 0, 0)`, restores HP, runs
`confirmRound()`, then logs per frame relative to T0: rand counts (exact, via LCG step counting
between frames), `ActionTag`, `+0x49` target, `battle+0x0c` continuation, enemy busy / fx /
`+0x42` / `+0x54`, party busy and HP, gate resets and actor changes.

- Pilot with 3 seeds x 2 rounds first, read the raw log by eye against your predicted table,
  fix the model, then run 40 seeds x 2 rounds (about a minute).
- Each log line is `T+n event`, so the checker can parse it. Keep that format.

## 6. Check offline

Template: `scripts/python/CheckAinGideTrace.py`. For each round it rebuilds the candidate list from the
logged roster, simulates the formula from the T0 seed, and compares move, target and **total
rand count up to the commit frame** (sum across frames: a rejected scan retries on the next
tick, and an Attack adds one hit roll). Then it prints min/max/histogram of every timing
offset. A constant offset (a single value over all runs) is a fixed timing; a spread is a variable
(for example a cue wait), so model it as a range.

Expect a 100% match. Anything less is a real bug in a rarely-taken branch (see the methodology
doc, section 4). Don't proceed on "mostly".

## 7. Live capture 2: damage and the compiled bug

Template: `scripts/TestAinGideRunes.lua` + `scripts/python/CheckAinGideRunes.py`:

- seeds that roll the special, x rune configs (base, all unlisted, all none, all the matching
  element, all a non-matching listed rune, slot-1 vs rest mixes);
- edit runes through persistent stats `*(b+0xf84+slot*0xc)->+0x1c->+0x4c` (`Address.sanitize`
  both pointers), set HP and HPMax to 999 so nothing clips, then `confirmRound()`;
- log per member: slot, Rune.Id, MGC (**last value before the HP drop**, derived stats are stale
  for ~5 frames after confirm), HP drop;
- the checker predicts every member from the logged T0 seed (target scan + move + the fixed RNG
  count + the member's own roll) and compares. All members of all configs must match.

Skip this step for a basic-Attack-only enemy. Use the physical `calc_damage` path instead
(see `lib/DamageVariance.lua`).

## 8. Package

1. `lib/Enemies/<Name>.lua`: `simulateMoveSelection(seed, numCandidates)` returning `move,
   target, seed, calls`; one simulate function per move's RNG; damage functions; a `TIMING`
   table (header comment says how/when it was measured). Follow `AinGide.lua`.
2. `tests/test_<Name>.lua` (`lua5.4 tests/test_<Name>.lua`): 6 to 8 captured seed vectors per
   move including retry cases (calls > 2), plus one test per rune/damage config. Generate vectors
   from the trace with a small Python snippet (final seed = the seed on the damage-frame
   `rand x N` line, **not** an earlier particle frame).
3. `docs/game_mechanics/Battle_Damage_Formula.md`: a section before Neclord's with the
   pseudocode, the RNG list, and timing tables. Flip the bug-table row. Add the validated entry
   comment in `lib/EnemyAIPredictor.lua`.
4. Rename the functions in the overlay's Ghidra program, add a plate comment to the tick
   machine, `save_program`.
5. `notes/`: a dated addendum with anything new learned.
6. Hand-off brief (chat only unless the user asks for a page): fight facts, exact AI, per-move
   RNG and timing tables, damage, validation sources, open points, repo rules. Ain Gide's is a
   good template.

## Pitfalls hit so far

- Catalog address = AI function, not the record (step 1).
- Per-frame rand counts must be LCG-step-counted, not "did it change".
- A fully rejected scan retries next tick, so count rolls across frames.
- The seed that matters is the one at T0; the first frame he is current actor.
- An Attack's gate reset (10) produces a turn-order roll P+10, not part of the AI.
- Finding a "final seed" for a test: take the damage-frame event, not any `rand` line.
- Output file can be complete while the process hangs; also `config-headless.ini` is rewritten
  by every headless run, that is expected.
- Verify polarity of the move roll and which return value is the plain attack.
- Sonya's old "live" bug row was wrong because the loop register was `$s0`; always read the
  actual register in the disassembly.
