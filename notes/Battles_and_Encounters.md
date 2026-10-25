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
