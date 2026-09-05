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
  rather than from this tool's own source — see that page's note on
  methodology before treating it the same as the pages below.
- [Turn Order](./game_mechanics/Turn_Order.md) — who acts next: confirmed
  RNG2 usage, live-verified combatant indexing and "current actor" field,
  still in progress (the exact speed-comparison loop isn't found yet).
- [Spell RNG Tracing Methodology](./game_mechanics/Spell_RNG_Tracing_Methodology.md)
  — the repeatable process for tracing a new spell's RNG consumption and
  animation duration, written as a checklist since this keeps coming up.

## Notes on accuracy

Several addresses and data structures in this codebase were arrived at by
observation/trial rather than disassembly, and the code itself flags a
number of open questions (unlabeled struct fields, unverified heuristics,
dead/renamed code paths). Each page calls these out explicitly where found
— treat anything phrased as "inferred," "unconfirmed," or "not stated in a
comment" as a lead for further reverse engineering, not settled fact.
