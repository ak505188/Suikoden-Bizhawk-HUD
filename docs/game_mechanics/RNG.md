# RNG System

Suikoden's random number generator is a classic 32-bit linear congruential
generator (LCG). It is fully deterministic and its constants are known, so
the entire future RNG stream can be pre-computed from the live seed without
advancing the emulator. This is the foundation almost every other system in
this tool builds on (encounters, drops, stat growth, Chinchironin).

## Addresses

| Constant | Address | Meaning |
|---|---|---|
| `Address.RNG` | `0x9010` | Live 32-bit RNG seed/state (`memory.read_u32_le`/`write_u32_le`) |
| `Address.EVENT_ID` | `0x1B9BC0` | Byte identifying which scripted story event/battle is occurring; used to index the reset-value tables below |
| `Address.GAMESTATE` | `0x1B9BBC` | Current gamestate byte (see `lib/Enums/Gamestate.lua`) |
| `Address.PREV_GAMESTATE` | `0x1B9BB8` | Previous gamestate byte |
| `Address.SAVE_FRAMECOUNT` | `0x1B9B8C` | Used as the RNG modifier for Chinchironin — see [Chinchironin.md](./Chinchironin.md) |

`0x1b9af6` (the Dragon Ride selector byte, read directly in `lib/RNG.lua`) is
**not** defined in `lib/Address.lua`, breaking the project's own convention of
centralizing addresses there.

## Core algorithm

```
rng' = (rng * 0x41c64e6d + 0x3039) mod 2^32
```

This is a standard Knuth/MMIX-style LCG. `lib/RNG.lua`'s `nextRNG` implements
it by manually splitting the multiplication into 16-bit high/low halves and
recombining, rather than a native 64-bit multiply — likely legacy code
ported from an environment without 64-bit integers; BizHawk's Lua could do
this with a plain multiply instead.

Nearly every gameplay roll is derived from a 15-bit "short" value taken from
the upper bits of the 32-bit state:

```lua
local function getRNG2(rng)
  return (rng >> 16) & 0x7fff
end
```

An `isRun` helper also exists:

```lua
local function isRun(rng2)
  return rng2 % 100 > 50
end
```

This is displayed in the Battles module as `R` (Run) vs `F` (Fail) next to
each predicted encounter, consumed two RNG advances ahead of the "does an
encounter happen" roll.

## RNG event resets

Certain scripted events (story battles, dragon rides, NPC encounters) cause
the game's RNG to land on one of a small, enumerable set of values rather
than a single deterministic one — implying the game advances the RNG a
variable, small number of times around the transition (likely frame-timing
variance), not that it resets to a fixed constant. `GetResetData(eventID)` in
`lib/RNG.lua` looks up the byte at `EVENT_ID` (`0x1B9BC0`) and returns the
candidate set for that event (1-indexed: `eventRNGValues[eventID + 1]`):

| eventID | Name | Reset value(s) |
|---|---|---|
| 0 | Pannu Yakuta Battle | `0x43` |
| 1 | Fortress of Garan Battle | `0x43` |
| 2 | Scarletia Battle #1 | `0x43` |
| 3 | Scarletia Battle #2 | `0x43` |
| 4 | Battle with Teo #1 | `0x42` |
| 5 | Battle with Teo #2 | `0x42` |
| 6 | Battle at Northern Checkpoint | `0x43` |
| 7 | Battle at Floating Fortress Shazarazade | 35 values: `0x43,0x43,0x43,0x44,0x45,0x46,0x46,0x47,0x47,0x47,0x48,0x49,0x4A,0x4B,0x4C,0x4D,0x4E,0x4F,0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x5B,0x5C,0x5D,0x5E,0x5F` (one per stage of that multi-battle sequence) |
| 8 | The Last Battle | `0x42` |
| 9 | Dragon Flight | special-cased, see below |
| 10 | "0x0A Unknown" | *(empty — unresolved)* |
| 11 | Marco | `0x12` |
| 12 | Window | `0xB0,0xB1,0xB2,0xB3,0xB4,0xB5,0xBD` |
| 13 | Melodye | `0x168,0x169,0x16A,0x16B,0x16C,0x16D,0x16E,0x16F,0x170` |
| 14 | Kasios | `0x1E6,0x1E7,0x1E8,0x1ED` |
| 15 | Georges | `0x4E` |

Events 11–15 are named after NPCs rather than battles.

**Dragon Ride** (eventID 9) is special-cased: it reads a *different* byte at
`0x1b9af6` to disambiguate which of three flights is happening:

| Value | Name | Reset value(s) |
|---|---|---|
| 0 | Dragon Ride to Magician's Island | `0x17, 0x18` |
| 1 | Dragon Ride from Magician's Island | `0x19` |
| 2 | Dragon Ride to Flying Garden | `0xAD, 0xAE` |
| other | "Unknown Dragon Ride?" | *(indexes past array end — errors)* |

A commented-out line in `GetResetData` hints at an earlier design that picked
a random reset value programmatically; the current design instead exposes
`ResetData:getRandomRNG()` so the user can pick one via the reset menu.

### Reset workflow

`Main.lua` calls `RNGMonitor:run()` every frame, watching for the gamestate
to transition into `EVENT` (`Gamestate.EVENT = 4`) as a signal that a
scripted RNG-reset moment is imminent. When the RNG memory value then
actually changes, `Events.START_RNG_CHANGED` fires and `Main.lua` opens
`RNG_Reset_Menu` (pausing the emulator). That menu reads `EVENT_ID`, looks up
candidates via `GetResetData`, and lets the runner:

- **Cross** — accept the observed value, start a fresh lookahead table anchored there.
- **Circle** — snap directly to a random candidate from the known list (`getRandomRNG`).
- **Up/Down** — manually nudge the value by ±1 (for dialing in a value close to, but not exactly, a listed candidate).
- **Square** — abort/revert (treat it as a load-state, not a real reset).

Because certain events land on one of only a handful of known values, a
speedrunner wanting a specific favorable outcome right after that event has a
small, tractable search space to aim for rather than the full 2^32 RNG space.
The tool can also directly **write** `Address.RNG`, so this isn't just
observation/prediction — it's active manipulation.

## Lookahead buffer system

Computing the LCG sequence plus all derived rolls is expensive, so the tool
amortizes the cost via `Config.RNG_MONITOR` (`Config.lua`):

```lua
INITITAL_BUFFER_SIZE  = 5000   -- initial look-ahead (note: typo, "INITITAL", used everywhere consistently)
BUFFER_INCREMENT_SIZE = 500    -- growth per frame once the margin is crossed
BUFFER_MARGIN_SIZE     = 50000 -- once remaining look-ahead drops below this, extend the table
```

- `RNGTable(start_rng)` (`lib/RNGTable.lua`) precomputes a table of future RNG
  values, indexed both ways (`byIndex[i] = rng`, `byRNG[rng] = i`) for O(1)
  lookup in either direction. For every position it also precomputes
  speculative encounter rolls (world-map/overworld `isPossibleBattle`, the
  resulting encounter-table index for every known table size, and the
  `isRun` roll) — computed for every index whether or not the real game ever
  checks there, and without moving the table's own position pointer.
- A local, non-configurable `SECRET_BUFFER_SIZE = 3000` (in
  `modules/RNG/worker.lua`, not `Config.lua`) is added on top of the margin
  and then **subtracted back out** of every size the user sees
  (`rngTable:getSize()`) — so the on-screen `I:x/y` label always undercounts
  the real internal buffer depth by 3000, as a hidden safety cushion against
  ever showing a number that's about to shrink.
- `rngTable:increaseBuffer` runs every frame, extending the buffer by 500
  whenever the visible remaining look-ahead drops below the margin, rather
  than doing one large blocking computation.
- `RNG_Monitor` keeps multiple independent `RNGTable`s keyed by their
  starting RNG value — effectively one lookahead cache per detected "epoch"
  of the RNG stream (one per reset event). `findTableContainingRNG` searches
  all cached tables for a given raw value; `switchTable` reuses a matching
  table or spins up a new one, which is exactly what happens after a reset
  lands on an unseen value.

### Practical implications

- Every future RNG/RNG2 value is knowable in advance from the live seed —
  this underlies encounter prediction (Battles module), drop prediction
  (`Battle.calculateDrops`), and stat-growth prediction (`StatCalculations.lua`).
- `RNGMonitor:goToIndex`/`adjustIndex` (bound to the RNG menu's D-pad, ±1/±25)
  let a user scrub the "cursor" position in the precomputed table and write
  the corresponding value back into live memory — a manipulation primitive
  used by ad hoc route-optimization scripts (e.g. `scripts/HolyBirds.lua`,
  which repeatedly calls `RNGMonitor:setRNG(rng)` in a search loop; treat
  content from `scripts/` as a hint of intent only, per project convention).
