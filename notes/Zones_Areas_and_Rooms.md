# Zones, Areas, and Rooms — notes

This is the history/uncertainty behind
[docs/game_mechanics/Zones_Areas_and_Rooms.md](../docs/game_mechanics/Zones_Areas_and_Rooms.md).

## Area / Zone / Screen / Room — distinct concepts

`lib/ZoneInfoComplete.lua` vs `lib/ZoneInfo.lua`: worth reconciling the two
files rather than treating `ZoneInfoComplete.lua` as current.

## Room data structure

### Slot count — unverified heuristic

A good target for further RE: the `NUM_SLOTS` formula is an unverified
heuristic, not confirmed memory layout.
