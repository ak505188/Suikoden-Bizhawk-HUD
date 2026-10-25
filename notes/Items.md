# Items — notes

This is the history/uncertainty behind
[docs/game_mechanics/Items.md](../docs/game_mechanics/Items.md).

## 2026-09-28: static table dump

- Dumped `LAB_80167658` from `main.exe` with `scripts/python/DumpItemTable.py`.
  It's all static; no emulator was needed.
- The old question was whether def `+0x20` is an effect handler or a
  stat-bonus array. It's both, depending on the record size.
  Equipment (`flags & 0x80`) uses `0x28`-byte records with bonuses there.
  Everything else uses `0x24`-byte records with a handler there. Medicine's
  `+0x20` is `0x800f0708`, the handler `Turn_Order.md` already recorded.
- Checked against `Suikoden-RNG-lib`'s `Armor.js`: 55 of 58 armor pieces
  match on price, stat bonuses and wear classes. The three that differ
  are probably errors in `Armor.js`:
  - Silver hat: the game has wear `0x03` (Cap + Helmet); `Armor.js` has
    Cap only.
  - Wooden shoes: the game's restriction byte is 0 (anyone, Kobold
    included); `Armor.js` has M/F/N.
  - Feather: the game's price is 4000; `Armor.js` has 2000.
  - 2026-09-28: prices moved out of `Armor.js` onto every entry in
    `Suikoden-RNG-lib`'s `Items.js` (`price`, from this dump), so Feather
    is now 4000 there.
  - 2026-09-28: Silver hat (+Helmet) and Wooden shoes (+Kobold) fixed in
    `Armor.js`. All 58 armor pieces now match the game data.
- `battle_try_special_attack`'s Ghidra plate comment gets the target
  type wrong. It says "2 = all-enemies validation loop". In the code,
  `1` loops over enemies, `0` loops over the party, and `2`/`3` are a
  single target.

## 2026-09-28: `+0x1e` and fixed equipment

- The user confirmed inventory bit `0x80` means fixed, can't unequip.
  Before that, an offline RAM scan of 329 existing savestates found 13
  slots with the bit, the same in every state: Crowley (Emblem, Master
  robe), Eileen (Star earrings), Luc (Guard robe, Speed ring), Meg
  (Guard robe), Milich (Rose brooch), Mina (Magic robe, Toe shoes),
  Odessa (Head gear), Pesmerga (Dragon Armor), Sonya (Crimson Cape),
  Stallion (Wing boots). The same scan showed appraised antiques hold
  `0xff` in this byte.
- The user said `+0x1e` is the quantity for Medicine, Antitoxin, Needle
  and Mega medicine. `FUN_800d5548` (sell price) confirms it's the full
  quantity of a new item for every non-equipment record: it compares the
  slot's quantity against `+0x1e` and pays 0 if they differ. The Rune
  pieces don't stack, and their 1 is the single use, not a stack size.
- The user also said:
  - Dragon seal incense is unique, never consumed, and battle-only. Its
    field handler (index 11) just prints the "only during battles"
    message, so flag `0x08` means "has a field Use entry", not "works in
    the field".
  - Blinking Mirror is the same, but works only outside battle.
  - Sacrificial Buddha is used automatically when a character dies, with
    no other way to use it (flags 0, no handler).

## 2026-10-01: inventory slot `+0x1` is the id's high byte

- `Characters.lua` called slot byte `+0x1` `Unknown`. It's the high
  byte of the u16 item id at `+0x0`. It was briefly named `Id_High`,
  then folded into a u16 `Id`.
- An offline scan of 2,426 Suikoden savestates (378,698 used slots)
  found it 0 in every slot. Item ids top out at 179, so it can't be
  anything else.

## Open questions

- Where Sacrificial Buddha's automatic use on death is implemented.
- Where the equipment special effects (Pointed hat's Balloon immunity,
  Silver hat's Auto-heal, Mangosh's counter rate) are applied. They
  aren't stored in the definition record.
- Target type `1` (every enemy) is handled by the code, but no item
  uses it.
