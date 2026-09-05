# Characters, Stats, and Growth

Covers the character memory layout, the level-up stat growth algorithm, name
tables, and party tracking. See [RNG.md](./RNG.md) for the RNG primitives
this reuses.

## Memory layout

`lib/Characters/Addresses.lua` maps each character's string name to up to
three fields:

- `RecruitmentState` — a single-byte flag address (108 of 110 named characters have one)
- `Stats` — base address of that character's 0x50-byte stats struct (78 of 110 have one — the "combat capable" roster)
- `Id` — a small integer 0–109, a global character identifier (same 78 that have `Stats`)

Cross-referencing every address reveals two contiguous, packed arrays (not
stated anywhere in comments — this is derived from the data, not asserted by
the code):

- **Character Stats array**: exactly 78 slots × 0x50 (80) bytes, running from
  `0x1B8294` (Hero) to `0x1B9AF3` (Warren's slot end), with no gaps that
  aren't a multiple of 0x50. **Slot order is not the same as the `Id` field
  and has no simple arithmetic relationship to it** — e.g. Hero is `Id=8` but
  sits at the start of the array; Gremio is `Id=2` but is the second slot.
  Treat `Id` and "position in the stats array" as independent indices.
- **RecruitmentState array**: exactly 108 consecutive bytes,
  `0x1B9AF4`–`0x1B9B5F`, one byte per recruitable character, starting
  immediately where the Stats array ends. This matches
  `Address.RECRUIT_FIRST_SLOT = 0x1B9AF4` (Gremio's slot). See
  [Saves_and_Toolbox.md](./Saves_and_Toolbox.md) for the Recruitment Editor
  that operates on this array — **no value legend for what a given byte
  value means (unrecruited/available/recruited/etc.) exists anywhere in the
  codebase**, and the 108-byte ordering does not follow alphabetical or enum
  order (it appears to loosely follow early-game recruitment order:
  GREMIO, EILEEN, CLEO, CAMILLE, KIRKIS, ... at the low offsets) — unverified
  against disassembly.

Not every named character has a `Stats` address — 32 of 110 never take a
party/battle slot (`Apple, Chandler, Chapman, Esmeralda, Gaspar, Georges,
Giovanni, Hugo, Ivanov, Jabba, Jeane, Joshua, Kun_To, Ledon, Leon, Marco,
Marie, Mathiu, Max, Melodye, Onil, Qlon, Rock, Sancho, Kasios, Taggart,
Templeton, Tesla, Viki, Vincent, Window, Zen`). `Odessa` and `Ted` are the
inverse oddity — they have `Stats`/`Id` but no `RecruitmentState`.

**`Taggart` is listed in `CombatCharacters.lua`'s roster** (as combat
capable) but has **no `Stats` address in `Addresses.lua` and no entry in
`Growths.lua`**. Selecting him in the Stats submodule would build a
character object with no `Growths` table, and `calculateStatLevelUp` would
then index a nil table — this looks like an unfinished/erroneous roster
entry.

## Character struct (0x50 = 80 bytes, relative to `Stats` address)

| Offset | Field |
|---|---|
| 0x00 | Id (matches `Addresses.lua`'s `Id`) |
| 0x01–0x03 | Unknown |
| 0x04–0x05 | HP_Max (u16 LE) |
| 0x06–0x07 | HP_Current (u16 LE) |
| 0x08 | Unknown |
| 0x09–0x0C | MP (4 bytes, likely one per rune slot) |
| 0x0D | LVL (u8) |
| 0x0E–0x0F | EXP (u16 LE) |
| 0x10 | PWR |
| 0x11 | SKL |
| 0x12 | DEF |
| 0x13 | SPD |
| 0x14 | MGC |
| 0x15 | LUK |
| 0x16 | Status |
| 0x17 | Unknown |
| 0x18–0x1E | Growths: PWR, SKL, DEF, SPD, MGC, LUK, HP (u8 each — static per-character growth-rate tier indices, see below) |
| 0x1F | Items.Count |
| 0x20–0x43 | 9 inventory item slots × 4 bytes: `{Id, Unknown, Equipped, Quantity}` |
| 0x44 | Weapon.Type |
| 0x45 | Weapon.Level |
| 0x46 | Weapon.Rune_Piece_Type |
| 0x47–0x4B | Weapon Piece Counts: Fire, Water, Wind, Thunder, Earth |
| 0x4C | Rune.Id |
| 0x4D | Rune.Locked |
| 0x4E–0x4F | Unknown |

Fields marked "Unknown" are explicitly unresolved in the source, not
speculation added here.

**EXP write endianness inconsistency**: `Characters.lua`'s
`character:write()` writes EXP with `memory.write_u16_le(address + 0xe, ...)`,
but the near-duplicate `writeCharacterData` in `lib/Characters/Utils.lua`
writes it with plain `memory.write_u16` (no `_le`) — everything else in both
files matches byte-for-byte; only this line differs. Given the PS1 is
little-endian, this is a likely latent bug in the `Utils.lua` copy. The
`Utils.lua` `readCharacterData`/`writeCharacterData` functions appear to be
dead/duplicate code not called by any Toolbox menu (which uses
`character:read()`/`:write()` from `Characters.lua` directly) — this
duplication is presumably how the two copies drifted.

## Stat growth algorithm

`Growths.lua` is a static, per-character lookup of 7 small integers (`PWR,
SKL, DEF, SPD, MGC, LUK, HP`, roughly 0–13 across the cast) — these are
**growth-rate tier indices**, not raw stat deltas.

**HP growth never actually uses the HP growth index** — `StatCalculations.lua`
computes the HP level-up amount using the character's **PWR** growth index
instead. This is a genuine quirk in the algorithm, not a documentation
simplification.

`StatCalculations.lua` holds two 16-entry (0x0–0xF) lookup tables,
`StatGrowths` and `HPGrowths`, each row a 3-tuple `{early, mid, late}` value
for a growth tier at a level bracket.

```
getGrowthValue(growth, stat, level):
  cutoffs = (growth == 9) and {15, 60} or {20, 60}
  tier = 1 + (number of cutoffs the level has passed)   -- 1, 2, or 3
  return (stat == HP) and HPGrowths[growth][tier] or StatGrowths[growth][tier]
```

```
calculateStatLevelUp:
  growth_value = getGrowthValue(...)
  small_RNG = (rng >> 16) & 0x7fff
  max_RNG = is_HP and (small_RNG & 0x1ff) or (small_RNG & 0xff)   -- 0-511 for HP, 0-255 otherwise
  stat_gain = floor((growth_value + max_RNG) / 256)
```

Each level-up consumes one RNG advance per stat, in a fixed order (PWR, SKL,
DEF, SPD, MGC, LUK, HP — `LevelupStatOrder`). Randomness only affects
rounding around the tier's base value, not the overall growth trend.

**Fragile growth-tier-9 special case**: `getGrowthValue` shifts the first
level cutoff from 20→15 when a stat's own growth index equals `9`.
Separately, the Stats submodule's `LevelCache:init` decides its cache-bucket
boundaries by checking only `character.Growths.PWR == 9` (not each stat
individually). In the current roster data, growth value `9` occurs exactly
once across the whole cast — Viktor's PWR — so the two pieces of logic only
agree today by coincidence of the dataset, not by design; if any other
character's non-PWR stat were ever given growth `9`, cache bucketing would
silently produce wrong cutoffs for it.

**Suspicious placeholder data**: `StatGrowths[0xF]` and `StatGrowths[0xB]`
are byte-for-byte identical (`{714, 608, 492}`), and `HPGrowths[0xF]` is also
`{714, 608, 492}` (identical to `StatGrowths[0xB]`, unlike every other
`HPGrowths` row, which is scaled up relative to its `StatGrowths` counterpart).
No character in `Growths.lua` uses growth tier `0xF` (observed range is
0–13) — this entry was likely never empirically observed and looks like an
unverified copy-paste placeholder rather than confirmed reverse-engineered data.

## Character names

`Names.lua` and `NamesList.lua` are both plain constant tables mapping
symbolic keys (`Names.ALEN`) to display strings (`"Alen"`) — **there is no
custom text encoding/character-map decoding involved here**; the string is
used directly as a Lua table key elsewhere (`Addresses`, `Growths`,
`Characters`). `Names.lua` returns two values (`Names, NamesList`), but no
call site anywhere captures the second return value — every consumer that
needs a name list instead uses the separately hand-maintained
`NamesList.lua`, making the `NamesList` built inside `Names.lua` dead,
redundant boilerplate.

## Party tracking (`lib/Party.lua`)

- `getPartySize()` reads `Address.PARTY_SIZE` (`0x1B8003`).
- `getCharacterDataAddress(formationSlot)` walks a pointer chain to find
  "whoever is in formation slot N" dynamically (without knowing identity
  ahead of time): read a byte from `FORMATION_POSITIONS + formationSlot` →
  index into an array at `GAMESTATE_BASE + offset*4` → read a u32 pointer at
  `+0x1b9c` (sanitized) → read a final u32 pointer at `that+0x1c` (sanitized)
  → this resolves to the character's `Stats` address, matching
  `Addresses.lua` exactly for in-party characters.
- `getCharacterRune`/`getCharacterLVL` read offsets `0x4c`/`0xd` off a given
  stats address (consistent with the struct layout above).
- `isChampionsRuneEquipped()` scans the party for Rune Id `24` (see
  [Battles_and_Encounters.md](./Battles_and_Encounters.md) for how this
  gates encounter groups).
- `getPartyLVL(partySize)` sums LVL across the party — **note the
  `partySize` parameter is ignored**: it's assigned
  `partySize = partySize or getPartySize()`, but the loop still calls
  `getPartySize()` directly instead of using that local, so passing an
  explicit value to override live memory has no effect.

## Stats RNG submodule (`modules/RNG/submodules/Stats/*`)

A level-up RNG-manipulation ("frame-lookahead") tool for speedrunning. Given
a selected character, starting level, and number of levels to gain,
`StatTable.lua` computes — across a whole table of candidate future RNG
states supplied by `RNGMonitor` — what the total stat gains would be if the
level-up(s) were triggered at each candidate state. It threads the RNG
forward per level (7 advances/level, one per stat), caches full-level
results keyed by `(rng, tier-cutoff-bucket)` since results only change at
growth-tier boundaries, and throttles generation to
`Config.StatsGenerator.LEVELUPS_PER_FRAME` (default 2000) per frame to avoid
lag. The menu lets the player pick the character, toggle which stats are
shown, and adjust starting level / levels gained (clamped to the level-99
cap). The worker draws a scrolling table of stat totals around the live RNG
index, so a runner can see "leveling up N frames from now yields these stat
gains" and pick the best window.
