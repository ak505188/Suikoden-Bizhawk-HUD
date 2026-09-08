# Battles and Random Encounters — notes

This is the history/uncertainty behind
[docs/game_mechanics/Battles_and_Encounters.md](../docs/game_mechanics/Battles_and_Encounters.md).

## Encounter roll

The division by `0x7f` (127) for overworld, instead of a power-of-two mask
like the world-map path, is unexplained in any comment and looks like it
mirrors the original PS1 assembly rather than being an arbitrary tool design
choice — worth verifying against a disassembly if one becomes available.

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
