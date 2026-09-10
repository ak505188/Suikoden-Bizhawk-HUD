# Suikoden Reverse Engineering Documentation

This documents the game logic, memory addresses, and algorithms
reverse-engineered as part of building this Bizhawk Lua HUD/tool for
Suikoden (PS1). It's derived from reading the `lib/`, `modules/`, `menus/`,
`monitors/`, and `controllers/` source, which is the tool's active,
maintained codebase.

`scripts/` is intentionally excluded as a source — those are one-off
simulation scripts used to generate specific datasets and may not reflect
verified or current understanding.

## Game Mechanics

- [RNG System](./game_mechanics/RNG.md) — the core LCG algorithm, event
  reset values, and the lookahead buffer everything else builds on.
- [Battles and Random Encounters](./game_mechanics/Battles_and_Encounters.md)
  — encounter rolls, the Champion Rune/"Champ Val" mechanic, enemy-group and
  encounter-table memory layout.
- [Characters, Stats, and Growth](./game_mechanics/Characters_and_Stats.md)
  — the character struct layout, stat level-up algorithm, party tracking.
- [Zones, Areas, and Rooms](./game_mechanics/Zones_Areas_and_Rooms.md) — the
  area/zone/screen/room memory model and area categorization (Forced/Random/All).
- [Item Drops](./game_mechanics/Drops.md) — the post-battle drop-roll algorithm.
- [Chinchironin](./game_mechanics/Chinchironin.md) — the dice minigame's
  roll algorithm and RNG modifier.
- [Saves and Toolbox](./game_mechanics/Saves_and_Toolbox.md) — savestate/
  autosave handling, the Character Editor, and the Recruitment Editor.
- [Gregminster Birds](./game_mechanics/Gregminster_Birds.md) — a standalone
  NPC-like structure outside the normal room data.
- [Battle Damage Formula](./game_mechanics/Battle_Damage_Formula.md) — the
  actual combat-resolution code (damage formula, crit chance, elemental
  affinity), reverse-engineered from `main.exe` disassembly in Ghidra
  rather than from this tool's own source.
- [Turn Order](./game_mechanics/Turn_Order.md) — who acts next: the
  weighted-RNG speed roll, the roll-gate countdown, and how a turn actually
  starts.
- [Scripted Battle Actions](./game_mechanics/Scripted_Battle_Actions.md) — how
  to drive a full battle round (every party member's command) from a Lua
  script with no controller input, for simulation purposes.
- [Battle Algorithm](./game_mechanics/Battle_Algorithm.md) — the master
  per-round loop (turn selection → action resolution → round-end processing),
  assembling Turn Order/Battle Damage Formula/Scripted Battle Actions into one
  walkthrough for implementing a pure-code battle simulator against.
- [Monster/Boss AI Static Catalog](./game_mechanics/Monster_AI_Static_Catalog.md)
  — a disc-wide, no-emulator-needed index of every monster/boss record found
  (file, offset, stats, AI function pointer) via `scripts/ScanMonsterRecords.py`,
  cross-referenced against `EncounterTable.lua`'s area rosters to flag which
  extra records per file are scripted bosses.

## Notes

[`notes/`](../notes/) (a sibling of `docs/`, at the repo root) holds two
kinds of content deliberately kept out of the pages above: the
investigation history behind each Ghidra-derived doc (dated findings,
corrections, dead ends, open questions — one `notes/X.md` per
`docs/game_mechanics/X.md` it documents), and reusable process
checklists for repeatable RE tasks
([Enemy AI Tracing Methodology](../notes/Enemy_AI_Tracing_Methodology.md),
[Spell RNG Tracing Methodology](../notes/Spell_RNG_Tracing_Methodology.md),
[Soul Eater Spell Offline Simulation Workflow](../notes/Black_Shadow_Simulation_Workflow.md)).
Treat `docs/` as the settled reference and `notes/` as the lab notebook
behind it.

## Notes on accuracy

Several addresses and data structures in this codebase were arrived at by
observation/trial rather than disassembly. Anything genuinely open or
unconfirmed has been moved to the corresponding `notes/` file rather than
left in these pages — if a page doesn't say a fact is uncertain, treat it
as settled.
