# Character JSON format

The exchange format for character state between this HUD
(`lib/CharacterJSON.lua`) and `Suikoden-RNG-lib`. It holds only the
state that can change in game. It leaves out growths, weapon type, rune
lock and unidentified bytes, and import doesn't touch them.

Ids are the game's own and are what import goes by. `key` fields are
there to make the file readable. When a character's `key` is given, it's
checked against its `id`. Item and rune `key`s are optional and ignored
on import.

## Shape

A file is an array of characters:

```json
[
  {
    "key": "CLEO",
    "id": 1,
    "LVL": 22,
    "EXP": 340,
    "stats": { "HP": 210, "PWR": 60, "SKL": 55, "DEF": 50,
               "SPD": 48, "MGC": 70, "LUK": 40 },
    "HP": 180,
    "MP": [4, 3, 2, 0],
    "rune": { "id": 6 },
    "weapon": { "lvl": 5,
                "runePiece": { "element": "EARTH", "amount": 3 } },
    "status": { "poison": true, "balloon": 2 },
    "inventory": [
      { "id": 12, "quantity": 2 },
      { "id": 140, "slot": "ACCESSORY_1", "locked": true },
      { "id": 170, "appraised": true }
    ]
  }
]
```

## Fields

Offsets are into the character's persistent Stats struct (see
[Characters_and_Stats.md](game_mechanics/Characters_and_Stats.md)).

`key`
: RNG-lib `CHARACTER_KEYS` name. The HUD's `HERO` is `MCDOHL`.

`id`
: Roster id, `+0x00`. Same as RNG-lib `CHARACTERS[key].id`.

`LVL`, `EXP`
: `+0x0d` (1–99), `+0x0e` (u16).

`stats`
: Base stats, not derived ATK/ARM. `HP` is max HP (`+0x04`, u16).
  `PWR`–`LUK` are `+0x10`–`+0x15`.

`HP`
: Current HP, `+0x06` (u16).

`MP`
: Current MP per spell level 1–4, `+0x09`–`+0x0c`.

`rune`
: `{ id }`, the rune id at `+0x4c`. Same as RNG-lib `RUNES[key].id`.

`weapon.lvl`
: `+0x45`.

`weapon.runePiece`
: `{ element, amount }`. `element` is an RNG-lib `WEAPON_ELEMENTS` key:
  the element the piece attacks as, not its in-game name. Memory holds
  a type byte at `+0x46` and five counts at `+0x47`–`+0x4b`; type `N`'s
  count is at `+0x46 + N`.
  - 1 `FIRE`, 2 `WATER`, 3 `EARTH` (shown as Wind in game),
    4 `LIGHTNING` (shown as Thunder), 5 `WIND` (shown as Earth).
  - `NONE` (type 0) has amount 0.
  - Only the active type's count is exchanged. Import zeroes the other
    four, the same as equipping a different piece in game.

`status`
: Only the statuses that persist outside battle, from `+0x16`.
  `poison` is bit `0x01`. `balloon` is stage 0–3, from the cumulative
  bits `0x02`/`0x04`/`0x08`. Import keeps every other bit. These match
  RNG-lib `STATUS.POISON` (bool) and `STATUS.BALLOON` (number).

`inventory`
: Up to 9 entries, in slot order. The slot count at `+0x1f` is the
  array length.
  - `id`: item id, the u16 at slot `+0x0`. Same as RNG-lib
    `ITEMS[key].id`.
  - `slot`: worn equipment only. It's an RNG-lib `ARMOR_SLOT` name:
    `HEAD`, `BODY`, `SHIELD`, `ACCESSORY_1` or `ACCESSORY_2`. It comes
    from the equip byte's low 7 bits (1–5) at slot `+0x2`.
  - `locked`: bit `0x80` of the equip byte, for fixed gear. It's only
    given with `slot`.
  - `appraised`: antiques only. The equip byte is `0xff` when true and
    `0` when false. If it's left out, import treats it as true.
  - `quantity`: slot `+0x3`. Export leaves it out when it's 0
    (equipment and never-consumed items). If it's left out, import uses
    0 for equipment and the item's full quantity (def `+0x1e`)
    otherwise.

## HUD usage

```lua
local CharacterJSON = require "lib.CharacterJSON"
CharacterJSON.exportFile("outputs/party.json", { "Cleo", "FLIK", 8 })
CharacterJSON.importFile("outputs/party.json")
```

`readCharacter`/`writeCharacter` work on a single table instead.
Characters are named by HUD name, key or roster id. Import checks every
character before writing any of them.

Import edits the persistent struct, not the battle copy. Battle load
copies the struct in, so import outside battle. An import made during a
battle takes effect at the next one.
