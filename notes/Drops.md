# Item Drops — notes

This is the history/uncertainty behind
[docs/game_mechanics/Drops.md](../docs/game_mechanics/Drops.md).

## Addresses

`BATTLE_ITEM_DROP` (`0x18FAF0`) is plausibly the address the game itself
writes the actually-rolled drop item to post-battle, which would make it a
great live-verification address for the prediction algorithm, but this is
speculation.

## Open questions

- `BATTLE_ITEM_DROP` (`0x18FAF0`) is unused dead data — worth investigating
  live to see if it holds the actual post-battle drop, which would let the
  prediction algorithm be verified directly.
- `enemy.Bits` (enemy struct offset 52–53) is parsed but never consumed
  anywhere — meaning unknown (candidate guesses: elemental
  affinity/resistance, steal-eligibility, or an AI flag — unconfirmed).
- Item name string length differs between the live path (24 bytes) and the
  dead legacy `helpers/BattleDetector.lua` path (16 bytes).
- `issues.md` notes "Drops has crashed before" as an open, unresolved issue,
  consistent with the battle-detection timing concerns noted in
  [Battles_and_Encounters.md](../docs/game_mechanics/Battles_and_Encounters.md).
