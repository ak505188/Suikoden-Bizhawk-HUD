# Item Drops

Covers how post-battle item drops are predicted from the RNG stream. See
[Battles_and_Encounters.md](./Battles_and_Encounters.md) for the enemy
struct this builds on, and [RNG.md](./RNG.md) for the RNG primitives.

## Addresses

| Address | Name | Meaning |
|---|---|---|
| `0x9010` | `RNG` | Live 32-bit RNG seed |
| `0x197F10` | `ENEMY_GROUP_PTR` | Pointer to the current battle's enemy-group struct |
| `0x197F14` | `ENCOUNTER_TABLE_PTR` | Pointer to the current encounter/enemy table |
| `0x16765C` | `ITEM_NAME_PTR_1` | Base of the item-name pointer array: `item_name_addr = u32[ITEM_NAME_PTR_1 + (id-1)*4] & 0x7fffffff` |
| `0x18FAF0` | `BATTLE_ITEM_DROP` | Declared in `Address.lua` but **never read anywhere in the codebase** — dead/unused. |

The enemy struct's drop fields (bytes 54–59, three `{id, chance}` pairs) are
documented in [Battles_and_Encounters.md](./Battles_and_Encounters.md#enemy-struct-60-bytes-per-enemy-libbattleluareadenemytable).

## Drop determination algorithm (`Battle.calculateDrop`)

Drops are **not** read live from game memory at the moment of the drop —
they are predicted deterministically from the RNG stream, the same way
encounter prediction works. Given an RNG index and the current battle
struct:

```
rng = RNGMonitor:getRNG(rng_index)
for i = 1, battle.GroupSize do
  enemy = battle.Enemies[i]
  if enemy == nil then return nil end          -- empty slot ends the loop early

  rng_index += 1
  rng = RNGMonitor:getRNG(rng_index) or nextRNG(rng)     -- roll #1: which drop slot
  drop_index = (getRNG2(rng) % 3) + 1                     -- picks slot 1, 2, or 3

  if drop_index <= #enemy.Drops then
    drop_data = enemy.Drops[drop_index]
    rng_index += 1
    rng = RNGMonitor:getRNG(rng_index) or nextRNG(rng)    -- roll #2: does it actually drop
    if getRNG2(rng) % 100 < drop_data.chance then
      return drop_data                                    -- drop confirmed; stop entirely
    end
  end
  -- otherwise continue to the next enemy with the advanced rng
end
return nil
```

Key mechanics:

- **Two RNG rolls per enemy**: one `% 3` roll picks which of the enemy's (up
  to) 3 drop slots is "in play," and one `% 100` roll is compared against
  that slot's stored `chance` byte (a percent-out-of-100 threshold).
- If an enemy has fewer than 3 drop entries but `drop_index` picks an empty
  slot, no chance roll happens for that enemy that pass — the loop moves to
  the next enemy. Enemies with fewer drop entries thus have their effective
  odds diluted by empty slots (1-in-3 or 2-in-3 chance the "eligible" slot is
  even rolled).
- **Only one item drops per whole battle group** — the function returns as
  soon as any enemy's chance roll succeeds; enemies later in the loop are
  never rolled for that RNG index.
- The RNG lookahead table doesn't always cover the needed index (up to 12
  positions past the cached bounds — 2 rolls × up to 6 enemies), so
  `nextRNG` is used as a manual fallback; a code comment explains the table
  can't be updated with these calculated values without risking an infinite loop.
- `Battle.calculateDrops(battle, rng_index, iterations, drops)` is a bulk
  version that repeatedly calls `calculateDrop` to build a lookahead list
  (default 10000 iterations, capped at `RNGMonitor:getTableSize()`).

## `DropTable.lua`

A per-battle, stateful lookahead list of drops — not a static
enemy→item mapping (that mapping lives per-enemy inside the enemy struct
itself, as `enemy.Drops[1..3] = {id, chance, name}`).

- `DropTable:new(battle)` wraps a battle struct and calls
  `generateDrops(0)`, iterating every RNG index up to
  `RNGMonitor:getTableSize()`, appending `{rng_index, name, id}` to
  `self.drops` whenever `Battle.calculateDrop` predicts a non-nil drop. The
  result is a sparse timeline: for each future RNG index, what item (if any)
  would drop right now.
- `generateDropsListForFilters()` builds a dedup map keyed by item id across
  every enemy in the battle (`{[id] = {chance, id, name, show}}`), used for
  the filter UI. **If two enemies in the same group drop the same item id at
  different chance percentages, only the first-seen chance value is kept**
  — a minor data-fidelity gap if used to reason about actual odds.
- `self.locked_pos`: `-1` means "unlocked" (auto-follows current RNG
  position); any other value pins the display to a fixed position regardless
  of live RNG movement (toggled via Lock/Unlock in the menu).
- `DropTable:run()` extends `self.drops` as the RNG table grows, and
  refreshes the current-position pointer as the live RNG index changes.

## Drops module/worker

- `modules/Drops/module.lua` has `Settings.RunInBackground = false` — drop
  tracking/prediction only runs while the Drops menu is active.
- `modules/Drops/worker.lua:run()` no-ops unless gamestate is `BATTLE` and
  both `ENEMY_GROUP_PTR`/`ENCOUNTER_TABLE_PTR` are valid pointers (see
  [Battles_and_Encounters.md](./Battles_and_Encounters.md#in-battle-detection)
  for the same guard and its known reliability issue). It rebuilds the
  battle/drop state only when `isUpdateRequired()` (new battle detected via a
  changed enemy-group or encounter-table pointer) — a `-- TODO: Handle start
  RNG change` comment flags that a change in the RNG's starting seed is
  **not** currently treated as a reason to rebuild, a real gap.
- `updateBattle()` reads group size and up to 6 enemy slot indices, builds
  and caches enemy struct tables per encounter-table address (so repeat
  battles against the same table aren't re-parsed), and assembles a compact
  `battleStruct = {Enemies, GroupSize}` skipping empty slots.

## Drops menu / filter

- **Menu** (`modules/Drops/menu.lua`): Circle backs out; Square opens the
  Filter Drops submenu; Triangle toggles Lock/Unlock of the scroll position;
  Up/Down scroll by 1, Left/Right by 10; Select dumps the live
  `Worker.State.Battle` struct to console for debugging.
- **Filter menu** (`modules/Drops/menus/drop_filter.lua`): lists every
  unique droppable item in the current battle (`Y/N <name> <chance>`), Cross
  toggles show/hide, letting a user hide "junk" items from the scrolling
  timeline without altering the underlying prediction data.
