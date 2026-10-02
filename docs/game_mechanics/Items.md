# Items

Every item in the game (armor, consumables, rune pieces, crystals,
antiques, key items) has one static definition record in `main.exe`.
`scripts/DumpItemTable.py` reads them straight from the file (no
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
