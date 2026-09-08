# RNG System — notes

This is the history/uncertainty behind
[docs/game_mechanics/RNG.md](../docs/game_mechanics/RNG.md).

## Addresses

`0x1b9af6` (the Dragon Ride selector byte, read directly in `lib/RNG.lua`) is
not defined in `lib/Address.lua`, breaking the project's own convention of
centralizing addresses there. Worth fixing if this file is touched again.

## RNG event resets

Events 11–15 are named after NPCs rather than battles — plausibly related to
the Chinchironin dice-gambling minigame or other scripted NPC sequences, but
this is not confirmed anywhere in the code.

## Open questions

- **`isRun` semantics** are undocumented — the R/F label's actual in-game
  meaning is unconfirmed. It's consumed two RNG advances ahead of the "does
  an encounter happen" roll, but nothing confirms what it actually
  represents in-game (ambush type, formation, something else).
- **Event ID 10 ("0x0A Unknown") has an empty reset table** — unresolved RE
  work; its actual reset values were never recorded.
- **`Address.ENCOUNTER_RATE` (`0x17159D`) is tracked by `StateMonitor` but
  never consulted by `Encounter.lua`'s `isPossibleBattle`**, which instead
  uses hardcoded thresholds. If the in-game encounter rate is dynamic (e.g.
  repel effects), prediction could silently diverge from the live game in
  some states — see
  [Battles_and_Encounters.md](../docs/game_mechanics/Battles_and_Encounters.md).
- Several explicit `TODO`s exist around whether manual RNG index adjustments
  should fire events (`monitors/RNG_Monitor.lua`), and whether confirming a
  reset value always needlessly creates a new table
  (`menus/RNG_Reset_Menu.lua`).
- `issues.md` documents a known display glitch: after setting a new RNG via
  the battle selection menu, the RNG monitor visibly blinks to a different
  value for one frame before settling.
