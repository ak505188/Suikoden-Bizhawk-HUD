# Chinchironin (Dice Minigame)

Chinchironin ("Chinchirorin", ちんちろりん) is the dice-gambling minigame in
Suikoden 1, played against named NPC opponents. This system predicts future
dice outcomes from the RNG stream so a runner can route toward a favorable
roll. See [RNG.md](./RNG.md) for the underlying RNG algorithm.

## Addresses

| Address | Name | Meaning |
|---|---|---|
| `0x9010` | `RNG` | Live 32-bit RNG seed, feeds `rng_short = (rng >> 16) & 0x7fff` used throughout |
| `0x1B9B8C` | `SAVE_FRAMECOUNT` | Read every frame and used as an additive **RNG modifier** in every roll calculation; also directly writable via the menu |

`SAVE_FRAMECOUNT`'s history is worth calling out: `lib/Address.lua`'s
comments show it was originally evaluated purely as an in-game-time (IGT)
candidate, alongside two other rejected/uncertain candidates:

```lua
SESSION_FRAMECOUNT = 0x1783f8, -- Kinda loadless, not completely accurate to save IGT
-- SAVE_FRAMECOUNT = 0x18B0A8, -- Not sure how to calculate real IGT, missing some value
-- Other IGT options are 17DBE8 (stops on loads?), 1B9B8C (Updated on save)
SAVE_FRAMECOUNT = 0x1B9B8C, -- Used for Chinchironin randomization
```

It was separately discovered to feed Chinchironin's dice math and repurposed
for that instead of IGT display. Its comment "(Updated on save)" implies the
value changes at save points — **confirmed by decompiling `main.exe`**: the
memory-card save routine (a large function inside the ~0x8012a000-0x8012c000
save/load module) is the only place in the executable that writes
`SAVE_FRAMECOUNT`, incrementing it by a delta read from a timer function each
time a save completes. There is no other write site anywhere in `main.exe`,
so it does **not** tick continuously during normal play — it only changes
when the player actually saves. See
[Saves_and_Toolbox.md](./Saves_and_Toolbox.md) for the other IGT candidates.

## Opponents

Two named opponents are modeled (`lib/Chinchironin.lua`): **Tai Ho** and
**Gaspar**. A third, `Player` (the human's own roll), exists in the data but
is commented out — self-roll prediction is currently disabled/unsupported.

Each opponent has a documented pre-roll frame delay (`FramesToAdvance`,
set in `modules/RNG/submodules/Chinchironin/menu.lua`):

| Opponent | Frames |
|---|---|
| Tai Ho | 203 |
| Gaspar | 441 |
| Gaspar at Castle | 421 |

The menu only auto-selects 441 when picking "Gaspar" — **the 421 Castle
variant must be set manually** via "Frames To Wait," an easy source of
misprediction if forgotten.

## Roll algorithm (`simulateRoll`)

The RNG is advanced one frame at a time, checking for special outcomes in a
fixed order; each check consumes exactly one RNG frame:

1. **Triple Win** — if true, consumes one more frame and rolls a single die
   value (excluding face "1"), e.g. `"444"`.
2. **Triple Lose** — if true, returns the literal fixed string `"111"` (no
   die is actually rolled for value).
3. **Double Win** — if true, returns the literal fixed string `"456"`.
4. **Double Lose** — if true, returns the literal fixed string `"123"`.
5. **Piss / bust** — if true, consumes a frame doing a full (discarded)
   3-die roll (to keep the RNG stream advancing in lockstep with the real
   game), and returns `"OUT"`.
6. Otherwise, a **normal roll**: three sorted die faces concatenated into a
   string, e.g. `"146"`.

**Notable quirk**: triple-1s (`"111"`) is hardcoded as a **loss**, and the
Triple-Win die roll actively excludes face "1" — the opposite of real-world
Chinchirorin rules, where 1-1-1 ("Pinzoro") is the best roll. This is a
deliberate, consistent finding in the code, not an assumed transcription error.

### Die generation primitive

Not a simple `% 6` — an accumulator scheme:

```
r2 = (rng_short + rng_modifier) % 100
counter = (counter + r2) & 0xff
if counter < 6 then return counter (0-5, becomes a die face 1-6) else return nil, counter end
```

The counter carries forward across frames (mod 256) until it lands under 6;
a full 3-die roll repeats this per die, resetting the counter after each
success, then sorts the three faces ascending.

**Tai Ho reroll filter**: when simulating Tai Ho, the outer loop rerolls
until it gets a result that is *not* a triple, not `"123"`, not `"456"`, and
not `"OUT"` — Tai Ho is coded to only ever get "plain" numeric rolls, never a
named special combo. Gaspar has no such filter.

### Win/Lose thresholds

All follow the pattern `r2 <= 0 → false, else r2 >= threshold`, where the
threshold is itself another `(rng_short + rng_modifier) % 100` roll:

- **Triple Win**: `r2 = (speed // 8) - trunc(cursorValue / 2) + 5`
- **Triple Lose**: `r2 = 5 - (speed // 8) + trunc(cursorValue / 2)`
- **Double Win**: `r2 = 5 + (speed // 4) - cursor:getValue()`
- **Double Lose**: `r2 = 5 - (speed // 4) + cursor:getValue()`
- **Piss/bust**: only possible when the cursor is outside a "safe" center
  zone; then `r2 = 5 + speed + cursor:getValue()`

The Triple Win/Lose formulas use a MIPS-style `abs(x // 2^31)` idiom to
emulate sign-aware truncating division and 16-bit sign extension — this is a
decompilation artifact from the original PS1 assembly, not a meaningful
large-number operation, and shouldn't be mistaken for one.

**"Speed"** (0–64, adjustable in the menu in steps of 4) is a free-floating,
user-supplied parameter with **no known *fixed* memory address backing
it** — how it maps to actual game state (a character stat? animation
timing? a per-encounter constant?) is not evident from the code. It must be
empirically matched by the operator; `scripts/generateChinchironinData.lua`
(treat as a hint of intent only, per project convention) iterates speed
values 4–64 for Gaspar, consistent with speed being empirically tuned rather
than read.

In the decompiled executable (see below), the roll-determination code does
read a "speed" value from `*(gameStatePtr + 0x15c) - 0x20` rather than from a
literal constant — so it isn't a hardcoded number in the real game either.
But `gameStatePtr` is a heap-allocated per-room struct whose address varies
run to run, which is consistent with there being no single fixed address to
watch — the operator-supplied "Speed" menu value remains the right approach
for this tool.

### The Cursor

A 42-entry lookup table modeling an in-game moving gauge/meter (likely a
visual "power"/luck indicator during the dice-throw animation), ramping from
117/118 up to a peak of 203 and back down. `calculateOpponentRoll` always
syncs a fresh cursor to its peak (exactly 20 steps from start) before
walking through the configured wait delay (each wait tick also advances the
cursor); after that, the cursor's value is held fixed for the rest of that
roll's evaluation.

`calculateWait(rng_short)`: `wait = rng_short % 100`, returning `255` if
`wait == 0`, else `wait - 1` — the pre-roll delay shown in the Worker's
"Wait" column.

## Confirmed in the executable

The dice logic is **not** part of `main.exe` — it lives in the same
per-room/per-area overlay files (`data/0N_area.X/*.bin`) that hold each
town's script and room code, loaded at a fixed base of `0x80010000`
(mirroring the convention used by minigame overlays like the castle's coin
cup-game and karuta). `main.exe` itself only contains a *generic*
event-script condition interpreter (with an opcode for a `rand()`-based
probability gate) used by every scripted NPC interaction across the game —
Chinchironin's specific formulas are not there.

Confirmed via a live memory read while standing in the Kaku tavern basement
mid-game (`WM_ZONE=1`, `AREA_ZONE=1`), then byte-matching the loaded overlay
buffer against disc files: the active file was **`data/02_area.b/vb2.bin`**
(zero byte differences across a 64KB dump). Since this subsystem is compiled
into every area's overlay (the same debug strings appear in dozens of other
`v*.bin` files across every area folder), the Castle's Gaspar instance almost
certainly runs the identical code out of whichever overlay is active for the
Castle instead — same functions, different file/base-relocation.

Loaded at base `0x80010000` in Ghidra (`PSX:LE:32:default`), the three
functions below were identified and annotated (exact formula match against
this doc, confirmed byte-for-byte):

| Function | Address | Role |
|---|---|---|
| `ChinRollDie` | `0x80017394` | Die-face accumulator: `counter = (counter + (rand() + SAVE_FRAMECOUNT) % 100) & 0xff`, retries while `counter >= 6`, returns the die face (0-5). Matches the "Die generation primitive" above exactly. |
| `ChinDetermineRollType` | `0x80016c58` | Evaluates Triple Win → Triple Lose → Double Win → Double Lose → Piss/bust in order (falling through to a normal roll via `ChinRollDie` if none hit) — each threshold checked against `(rand() + SAVE_FRAMECOUNT) % 100`. All five formulas match "Win/Lose thresholds" above exactly. |
| `ChinUpdateCursor` | `0x80015d08` | Animates the cursor gauge: initializes to `0x75` (117) and ramps up, reversing at `0xcb`/`0xca` (203/202). Matches "The Cursor" above exactly. |

Two globals were also identified and named in the Ghidra project:
- `g_pChinGameState` (was `DAT_80064a98`) — base pointer to the room's
  runtime state struct (speed at `+0x15c`, cursor value at `+0x462`,
  per-die results at `+0x164`/`+0x2cc`/`+0x434`, win/lose flags at `+0x43a`).
- `g_dwSaveFrameCount` (was `DAT_801b9b8c`) — this program's view of
  `Address.SAVE_FRAMECOUNT`, read directly inside both `ChinRollDie` and
  `ChinDetermineRollType` as the additive RNG modifier.

## `ChinchironinTable.lua`

Builds an incrementally-generated lookup table of predicted rolls, one entry
per RNG-table index, throttled by
`Config.ChinchironinGenerator.GENERATIONS_PER_FRAME` (default 50) to avoid
lag spikes — the same throttling pattern used elsewhere (see
`Config.StatsGenerator.LEVELUPS_PER_FRAME` in
[Characters_and_Stats.md](./Characters_and_Stats.md)). Each call advances
toward the full buffered RNG table size, computing
`{initial_rng, roll_rng, roll_rng_index, roll, wait}` for each index. A
`slice(index, size)` method returns a contiguous window used by the worker
to display upcoming rolls near the current RNG position.

## Menu / worker

- **Worker**: refreshes `RNG_Modifier` from live memory every frame
  (`memory.read_u32_le(Address.SAVE_FRAMECOUNT)`), builds/retrieves a cached
  table keyed by `Player_StartingRNG_Speed_RNGModifier_FramesToAdvance`
  (changing any of these forces a full recompute), and draws a scrolling
  `Index / Roll / Wait` list (15 entries) centered on the current RNG index.
- **Menu**: Dice Speed (0–64, step 4), Select Player (Tai Ho / Gaspar, which
  auto-sets `FramesToAdvance`), Frames To Wait (manual override), and RNG
  Modifier (view/edit the live `SAVE_FRAMECOUNT` value directly — writes
  `memory.write_u32_le(Address.SAVE_FRAMECOUNT, ...)`, directly manipulating
  live game memory, not just the tool's internal state). Note any manual
  edit only "sticks" until the next frame, since the worker unconditionally
  re-reads memory into `RNG_Modifier` every frame.

Overall workflow: pick the opponent, tune Speed/FramesToAdvance/RNG-Modifier
to match the actual encounter, and the HUD shows a scrolling forward-looking
table of what dice roll will occur at each future RNG index — letting a
runner route toward a favorable upcoming roll (triple win, `456`) or avoid a
bad one (`123`, `111`, `OUT`).
