# Items

Every item in the game (armor, consumables, rune pieces, crystals,
antiques, key items) has one static definition record in `main.exe`.
`scripts/python/DumpItemTable.py` reads them straight from the file (no
emulator) and writes all 179 to `outputs/Items.json`.

Weapons are not items. Each character's weapon is its own Stats field
(see [Battle Damage Formula](./Battle_Damage_Formula.md)).

## The definition table

`LAB_80167658` is an array of `u32` pointers indexed by item id:
`def = *(0x80167658 + id * 4)`. Id 0 means "empty slot" and its word
holds `8`, not a pointer. Ids run 1–179. The word after id 179
(`0x80167928`) starts a different table, the field-use handlers (below).

`Address.ITEM_NAME_PTR_1` (`0x16765c`, indexed by `id - 1`) is the same
table, which is why `Battle.lua:getItemName` reads the name straight
from the definition.

## Record layout

Records come in two sizes, and flag bit `0x80` says which one:

- **Equipment** (`flags & 0x80`): `0x28` bytes. `+0x20` holds stat
  bonuses.
- **Everything else**: `0x24` bytes. `+0x20` holds the battle effect
  handler.

The fields common to both:

`+0x00` (24 bytes)
: Name, in the game's charmap encoding, 0-terminated.

`+0x18` (u32)
: Price in bits. It's 0 for items that can't be sold.

`+0x1c` (u16)
: Flags. The game always reads this as a `u16`, so the byte at `+0x1d`
  is its high half (see the bit list below).

`+0x1e`, `+0x1f`
: These depend on the kind of item (see below).

### Flag bits (`+0x1c`)

`0x0003`: target type
: `battle_try_special_attack` reads this. `0` means the whole party,
  `1` means every enemy (no item uses this), and `2` or `3` means one
  living ally.

`0x0004`: usable in battle
: The battle Item menu (`FUN_800ef40c`) only lists items with this bit.

`0x0008`: has a field-menu Use entry
: The item still might not do anything there. Dragon seal incense has
  this bit, but its field handler only prints "can be used only during
  battles".

`0x0080`: equipment
: When this bit is set, the record is `0x28` bytes long.

`0x00e0`: equipment type
: `0x80` Head, `0xa0` Body, `0xc0` Shield, `0xe0` Accessory. The
  equip-slot table at `DAT_8016a8c4` maps these onto the five slots:
  Helmet, Armor, Shield, Other1, Other2 (both accessory slots take
  `0xe0`).

`0x0f00`: who can equip (equipment only)
: This is byte `+0x1d`. `0x1` Male, `0x2` Female, `0x4` Kobold, `0x8`
  Nobility. `0` means anyone. Only accessories set it.

`0x7000`: antique type
: `0x1000` pot, `0x2000` ornament, `0x4000` painting. An unappraised
  antique shows as "? pot" / "? ornament" / "? painting" in the
  inventory list (`FUN_800d44b4`).

### Equipment (`0x28` bytes)

`+0x1e` (byte)
: Wear-class mask. The character's armor classes must allow it.

| Bit | Class | Bit | Class |
|---|---|---|---|
| `0x01` | Helmet (E) | `0x10` | Vest (V) |
| `0x02` | Cap (C) | `0x20` | Robe (R) |
| `0x04` | Heavy armor (H) | `0x40` | Shield (S) |
| `0x08` | Light armor (L) | `0x80` | Accessory |

`+0x1f`
: Always 0.

`+0x20` (8 × s8)
: Stat bonuses. `battle_compute_ally_derived_stats` adds them into the
  eight derived-stat slots when the item is equipped.

| Index | Stat | Index | Stat |
|---|---|---|---|
| 0 | PWR | 4 | MGC |
| 1 | SKL | 5 | LUK |
| 2 | DEF (base stat) | 6 | ATK (final) |
| 3 | SPD | 7 | DEF (final) |

An armor piece's own DEF sits in index 7. The equip screen's DEF
preview (`FUN_800cf758`) adds `+0x27` onto the base DEF. Indices 2, 5
and 6 are 0 for every item in the table.

Special effects like "Prevents Balloon", Auto-heal and "Counter-rate up"
are not stored here. They must be keyed off the item id somewhere else.

### Everything else (`0x24` bytes)

`+0x1e` (byte)
: The quantity a full, unused item has: Medicine 6, Antitoxin 4,
  Needle 4, Mega medicine 3. It's 1 for single-use items (Escape
  talisman, the Rune pieces, Sacrificial Buddha) and 0 for items that
  are never consumed (Dragon seal incense, Blinking Mirror). The sell
  price (`FUN_800d5548`, half of `+0x18`) is 0 when the slot's quantity
  doesn't equal this, so a partly used item can't be sold.

`+0x1f` (byte)
: Field-use handler index. When the item is used from the field menu,
  the game calls through `0x80167928[index]`, a table of 14 handlers
  (`0x800cbbe8`). The Rune pieces use 5–10 in the order Power, Skill,
  Defense, Magic, Speed, Fortune.

`+0x20` (u32)
: Battle effect handler, or 0. `battle_try_special_attack` copies it to
  `BattleState+0x10`, and the Item wait state calls it every tick until
  it returns 0 (see [Turn Order](./Turn_Order.md#item-turns)).

Battle-usable items and their handlers:

| Id | Item | Handler |
|---|---|---|
| 25 | Medicine | `0x800f0708` |
| 26 | Antitoxin | `0x800f0850` |
| 71 | Needle | `0x800f0920` |
| 72 | Mega medicine | `0x800f07ac` |
| 80 | Dragon seal incense | `0x800f09f0` |

Id 80 is the only whole-party item.

Sacrificial Buddha (id 83) has no flags and no handler. It can't be used
from either menu. The game uses it automatically when a character dies,
and that code must look it up by id.

## Inventory slots

Each character's persistent Stats struct holds its inventory at `+0x20`.
There are 9 slots of 4 bytes each. `+0x1f` holds how many slots are in
use.

`+0x0` (u16)
: Item id.

`+0x2` (byte)
: For equipment, 0 means unequipped. Otherwise the low 7 bits are the
  equip slot (1–5, matching `DAT_8016a8c4`). Bit `0x80` means fixed
  equipment that can't be unequipped. `FUN_800d50a4` won't replace it.
  Characters who join with fixed gear include Luc, Crowley, Mina and
  Stallion. For antiques, `0xff` means it has been appraised and 0
  means it hasn't.

`+0x3` (byte)
: Quantity or uses left. Menus show it when it's above 1. Using the
  item in battle takes one off, and at 0 `FUN_800ca408` removes the
  slot.

## Battle use timing

Frames are counted from `done`, the frame the user's flag `0x8` is seen and the
effect scripts start (`itemDone` in `outputs/CharacterItemTimings.json`, the
user's anim 13 + anim 14). The turn side (R, the roll after `done`) is in
[Turn_Order.md](./Turn_Order.md#item-turns). Regenerate everything with
`scripts/python/ItemUseTimings.py`; constants with their source are in
`outputs/ItemEffectConstants.json`.

Item ids and battle handlers (`itemDef+0x20`):

```
id  item                 handler     target script  needs
25  Medicine             0x800f0708  0x8016c2f0     (any ally)
26  Antitoxin            0x800f0850  0x8016c390     Poison (status bit 0x1)
71  Needle               0x800f0920  0x8016c3b8     Balloon stage (bits 0xe)
72  Mega medicine        0x800f07ac  0x8016c314     (any ally)
80  Dragon seal incense  0x800f09f0  0x8016c3dc     (every living member)
```

The user runs `0x8016c194` first (all five). When the handler fires it plays
`0x8016c1c0` on the user (not Incense) and the target script on the target.

```
item         target free  user free (ally)    user free (self)
Medicine     done + 64    ally value           done + 64
Mega medic.  done + 64    ally value           done + 64
Antitoxin    done + 33    ally value           done + 33
Needle       done + 14    ally value           done + 14
Incense      fire + 65    fire + 65 (user is   -
                          a member too)
```

"Ally value" is `itemUserFreeAlly` (done + 61 + the user's anim 15 length).
With no matching status, Antitoxin and Needle play nothing: the handler
returns 0 at `done` with no busy and no cure, and the user's own script
`0x8016c194` runs to its end. That is the ally value for every one of the 78
characters (checked), also when the target is the user, so a healthy-target
use looks like an ally-targeted Medicine to the user. It is a different
script from Medicine's `0x8016c1c0` with the same length. `fire` is below.

What each effect does (read from code unless marked):

- **Antitoxin** (setup `0x800f2838`, tick `0x800f297c`, fade `0x800f2c54`).
  Gate: target `wStatusFlags & 0x1`. The setup hides the poison icon (slot
  `+0x30a4` = 0) and borrows its sprite. 30-frame countdown, then phase 0
  clears the Poison bit (done + 31, simulated), phase 99 calls
  `clear_status_effect(idx, 0)` (done + 32), which sets the slot's expired flag
  so the icon updater frees the sprite. The script then waits one more frame
  (`op 3, 1`) before clearing busy: target free done + 33. Nothing else
  changes: no HP, no ActionTag, no RNG, and Poison has no counter to reset (see
  [Battle_Damage_Formula.md](./Battle_Damage_Formula.md) "Duration: none").
  The 33 is independent of the user and of the target. Simulated, not live.
- **Needle** (setup `0x800f2d7c`, tick `0x800f2eb8`, finish `0x800f3084`).
  Gate: `wStatusFlags & 0xe`. The setup picks the highest Balloon stage whose
  slot is active (id3, else id2, else id1). The tick plays sprite sequence 5
  once and waits for it to stop; the finish clears one stage bit (`0x8`, else
  `0x4`, else `0x2`) and calls `clear_status_effect` at phase 99. One stage per
  use. Sequence 5 is 10 frames (inferred: the sheet is word 0 of `battle.bin`,
  which `apply_status_effect` builds the status sprites from, but the sprite
  actually played wasn't confirmed). Bit cleared done + 12, target free done +
  14, simulated.
- **Dragon Seal Incense** (handler `0x800f09f0`, effect as Medicine variant 2:
  -50 HP, 2 sparkles). The handler returns -1 while any party slot
  `1..dwPartyCount` has `combatant_rec+0x45 == 0` and a nonzero busy byte. The
  user is such a slot and is still busy in its own `0x8016c194` script, so the
  first fire is one tick after the user's busy clears: `fire` = ally value + 1.
  It then plays `0x8016c3dc` on each slot with `+0x45 == 0` and returns 0. That
  flag is the death-routine flag, not HP: dead members are skipped, but a
  member at 0 HP whose death routine hasn't run yet is healed too. Busy
  members aren't skipped, they are waited for. Each member's script is the
  Medicine one plus a 1-frame delay: HP change fire + 32, free fire + 65.
  Returning 0 is "done" like Medicine's: the roll is the next tick (fire + 1)
  and the new actor fire + 2. Every member is busy until fire + 65, so the
  roll skips them (an unacted party member becomes eligible then); enemies
  that haven't acted are eligible at once. Simulated only.

Per-character: none of this varies by user beyond `itemDone` and the anim 15
length already in `CharacterItemTimings.json`; the cure and Incense member
timings are constants. The four odd characters were re-read: Clive (done 3,
anim 13 is 2 frames), Eileen and Sarah (36 + 1), Kirke (105 + 1) all have
well-formed, non-looping sequences 13 to 15, so the numbers are real data.
None of it is live-checked; Clive is the only recruitable one of the four.

Read from code: the handlers, gates, scripts and effect constants (30, 0xff,
-4, 0x80, the slot flags, `+0x45`). Simulated from that code: every frame
count. Inferred: the Needle sequence length. Checked live: only the Medicine
numbers (McDohl, Pahn, Gremio, Ted, Cleo) and the Antitoxin target busy
clearing at done + 33 in the Cleo to Gremio log.

