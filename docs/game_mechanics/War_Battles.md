# War Battles

War battles (the army-vs-army fights: Kwanda's attack on Panna Yakuta,
Garan, Scarleticia, Teo, the Northern Checkpoint, Shasarazade, the last
battle) are separate overlays in `data/16_war/`, loaded at `0x80010000`.
Each one is a flat image, byte-identical to RAM once loaded.

Status: static RE in Ghidra plus live checks from savestates. For the
kuwa battle everything is reproduced exactly, including the `rand()` stream:
`scripts/WarSim.py` starts from the war's reset seed (`0x43`) and the
recruited characters, and its RNG, soldier counts, enemy actions and every
soldier sprite matched the game frame by frame for 16 recorded command
sequences (Charge, Bow, Magic, Strategists, Ninjas, Thieves, Merchants and
Dragon Knights, 3 to 9 commands each, 4 of them with random seeds and
random commands). The rules were also checked cell by cell (all 9
matchups, both roll boundaries, every Others outcome). Only
`kuwa` has savestates; the other five regular scenarios run the same code
and the sim takes their tables from their own overlays, but they were not
run live. The three scripted scenarios (sca1, teo1, teo2) are static
analysis only. History and raw findings are in
[notes/War_Battles.md](../../notes/War_Battles.md).

## Files

- `war_kuwa.bin`: Kwanda at Panna Yakuta Castle (the first war).
- `war_gara.bin`: Fortress of Garan.
- `war_sca1.bin`, `war_sca2.bin`: Scarleticia Castle, battles 1 and 2.
- `war_teo1.bin`, `war_teo2.bin`: the two battles with Teo.
- `war_kita.bin`: the Northern Checkpoint.
- `war_shas.bin`: the floating fortress Shasarazade.
- `war_last.bin`: the last battle.
- `war1.bin`, `w_header.bin`: an older build of the same engine, with
  debug strings ("STEP WAR_MAIN"). Not used by the scenarios above.

kuwa, gara, sca2, kita, shas and last contain the same engine code at the
same addresses (checked word by word, ignoring BSS address immediates). They
differ only in these values:

- the enemy's starting soldier count (`0x800105e8`/`0x800105fc`)
- soldiers per sprite (`0x800183a4`, `0x800183f8`, `0x80018ad0`)
- the enemy action table and turn script (data)
- `last` has a 6-entry turn script (`0x8001afb0`, `0x8001b100`) and its
  tables sit 4 bytes lower

sca1, teo1 and teo2 are rebuilt with a much shorter round resolver (the
outcome is scripted), see "Scripted scenarios".

## Memory map (kuwa)

The overlay's BSS starts around `0x800a7200`. Other overlays have these
globals at different addresses, so re-read the `lui`/`lw` pairs per file.

```
0x800a7680 u16  player soldiers (true count)
0x800a7682 u16  enemy soldiers (true count)
0x800a7350 u16  player count on the HUD (ticks down 5/frame, then settles)
0x800a7352 u16  enemy count on the HUD
0x800a77b8 u16  player soldiers at battle start (the cap for Merchants)
0x800a77ba u16  enemy soldiers at battle start
0x800a7488 u32  pending player loss for this round
0x800a7490 u32  pending enemy loss for this round
0x800a7498 u8   1 when the player lost the matchup (arms the banter roll)
0x800a7450 ptr  108-byte character availability array
0x800a7688 ptr  36 x u16 "unit used" array, -1 = unused
0x800a7690 u8   Strategist buff, turns remaining
0x800a7691 u8   Thief/Ninja already used this turn
0x800a7692 u8   turns completed
0x800a7694 s32  Dragon Knight damage for this round
0x800a76d0 u8   enemy action index chosen for this turn
0x800a7458 u8[] enemy action "already used" flags (index 0..4)
0x800a77c8 u8   position in the enemy turn script
0x800a76e8 u8   command category (0 Charge, 1 Bow, 2 Magic, 3 Others)
0x800a77a0 u8   chosen unit (group id)
0x800a7760 u8   main phase
0x800a77a8 u8   round state
0x800a77d0 u8   state to jump to when the current wait finishes
0x800a76d8 u8   outcome (0 victory, 5 defeat, 8 no units left)
0x800a7738 s16  player sprites alive, 0x800a773a for the enemy
0x800a73f0 s8   player sprites still to kill, 0x800a73f1 for the enemy
```

Character availability bytes: `0xff` available, `0xfd` not recruited,
`0xfc` used up by a Thief or Ninja command. The array is built once at the
start of the battle from the recruitment flags (`save + 0x1af4 + slot`,
bit 0, where `slot` comes from the table at `0x8002badc`). It is not
rebuilt per turn.

## Army setup

At the start of the battle (`0x8001053c`):

- Player soldiers = the sum of the soldier counts of every available
  character (table below). That value is also stored as the cap.
- Enemy soldiers = a constant per scenario (see "Scenario data").
- Each army is drawn as `soldiers / N + 1` sprites, where `N` is the
  scenario's soldiers-per-sprite value (300 for kuwa, see "Scenario data").

### Characters and units

Characters (war ids 0-107, the index into the overlay's tables) are grouped
into 36 units of 3 (`0x800271a0`). Each character has 6 bytes at
`0x80026f18 + id * 6`: type (0 Charge, 1 Bow, 2 Magic, 3 Other), base power,
extra power, a spare byte, and a u16 soldier count.

The power of a unit is computed by `0x8001aa30`:

```
available = members of the unit (in table order) with availability 0xff
if none: power = 0 (the unit is not offered)
first = available[0]
power = base[first] + sum(extra[m] for m in available[1:])
if type[first] == 0 and strategist_buff > 0:
    power = power + power / 2          (integer division)
power = power & 0xff
```

So the first available member decides the unit's category and base power,
and every later member adds its "extra". A unit is offered under category
`c` when its first available member has type `c` (`0x80014f24`), it has not
been used before in this battle, and its three members are not all missing.
Units 24 (Thieves) and 33 (Ninjas) are also hidden while `0x800a7691` is set.

The in-game text for the unit names is a run of strings starting at
`0x8002720c`. The soldier table and the unit table follow.

| id | name | type | base | extra | soldiers |
|---:|---|:-:|---:|---:|---:|
| 0 | Hero | C | 14 | 5 | 700 |
| 1 | Cleo | C | 10 | 7 | 80 |
| 2 | Pahn | C | 12 | 5 | 150 |
| 3 | Eileen | B | 14 | 3 | 170 |
| 4 | Viktor | C | 14 | 2 | 300 |
| 5 | Camille | B | 12 | 4 | 90 |
| 6 | Warren | C | 12 | 3 | 700 |
| 7 | Varkas | C | 13 | 3 | 600 |
| 8 | Sydonia | C | 12 | 4 | 120 |
| 9 | Humphrey | C | 17 | 3 | 450 |
| 10 | Joshua | O | 16 | 5 | 600 |
| 11 | Flik | C | 11 | 5 | 300 |
| 12 | Ledon | O | 3 | 3 | 20 |
| 13 | Kessler | C | 8 | 4 | 270 |
| 14 | Mathiu | O | 1 | 0 | 550 |
| 15 | Tai Ho | C | 13 | 3 | 120 |
| 16 | Yam Koo | C | 11 | 4 | 60 |
| 17 | Luc | M | 19 | 1 | 20 |
| 18 | Lepant | C | 17 | 3 | 900 |
| 19 | Gremio | M | 13 | 7 | 150 |
| 20 | Giovanni | O | 2 | 6 | 30 |
| 21 | Krin | O | 1 | 1 | 5 |
| 22 | Juppo | C | 3 | 3 | 70 |
| 23 | Kirkis | B | 13 | 3 | 380 |
| 24 | Liukan | C | 6 | 5 | 150 |
| 25 | Gen | C | 7 | 3 | 300 |
| 26 | Kamandol | C | 3 | 2 | 130 |
| 27 | Tesla | C | 1 | 5 | 70 |
| 28 | Kimberly | C | 5 | 2 | 280 |
| 29 | Kasumi | O | 10 | 6 | 90 |
| 30 | Mose | C | 8 | 5 | 350 |
| 31 | Kun To | O | 12 | 3 | 240 |
| 32 | Fukien | C | 6 | 6 | 110 |
| 33 | Taggart | C | 4 | 6 | 10 |
| 34 | Futch | O | 9 | 4 | 60 |
| 35 | Milia | C | 13 | 6 | 180 |
| 36 | Tengaar | M | 12 | 2 | 30 |
| 37 | Hix | B | 5 | 4 | 10 |
| 38 | Kwanda | C | 14 | 3 | 300 |
| 39 | Valeria | C | 13 | 4 | 250 |
| 40 | Milich | M | 14 | 3 | 270 |
| 41 | Griffith | C | 12 | 3 | 400 |
| 42 | Kasim | C | 15 | 2 | 200 |
| 43 | Sonya | M | 13 | 4 | 250 |
| 44 | Sylvina | B | 7 | 5 | 60 |
| 45 | Stallion | B | 5 | 3 | 20 |
| 46 | Ronnie | C | 6 | 2 | 110 |
| 47 | Vincent | C | 10 | 1 | 5 |
| 48 | Kuromimi | B | 9 | 4 | 60 |
| 49 | Alen | C | 13 | 3 | 150 |
| 50 | Grenseal | C | 13 | 4 | 150 |
| 51 | Anji | C | 11 | 2 | 300 |
| 52 | Leonardo | C | 9 | 5 | 90 |
| 53 | Kanak | C | 7 | 7 | 90 |
| 54 | Kage | O | 4 | 2 | 10 |
| 55 | Sheena | C | 8 | 2 | 60 |
| 56 | Apple | C | 1 | 1 | 280 |
| 57 | Esmeralda | C | 6 | 3 | 70 |
| 58 | Fu Su Lu | C | 2 | 1 | 20 |
| 59 | Gon | B | 5 | 7 | 50 |
| 60 | Rubi | B | 4 | 2 | 10 |
| 61 | Lotte | M | 15 | 4 | 220 |
| 62 | Fuma | O | 2 | 2 | 10 |
| 63 | Lorelai | B | 11 | 3 | 90 |
| 64 | Morgan | C | 5 | 4 | 80 |
| 65 | Quincy | B | 9 | 4 | 180 |
| 66 | Mina | B | 4 | 2 | 160 |
| 67 | Blackman | C | 15 | 4 | 110 |
| 68 | Kreutz | C | 17 | 3 | 300 |
| 69 | Kirke | C | 9 | 3 | 5 |
| 70 | Meg | M | 13 | 2 | 190 |
| 71 | Max | C | 19 | 3 | 1200 |
| 72 | Sancho | C | 12 | 7 | 200 |
| 73 | Georges | B | 6 | 2 | 20 |
| 74 | Rock | C | 7 | 4 | 70 |
| 75 | Melodye | M | 9 | 3 | 60 |
| 76 | Window | M | 11 | 3 | 60 |
| 77 | Gaspar | C | 14 | 4 | 10 |
| 78 | Onil | C | 9 | 2 | 20 |
| 79 | Zen | C | 6 | 4 | 300 |
| 80 | Sarah | C | 12 | 4 | 80 |
| 81 | Kai | C | 13 | 3 | 140 |
| 82 | Eikei | C | 7 | 3 | 180 |
| 83 | Sergei | B | 5 | 5 | 80 |
| 84 | Hugo | B | 4 | 4 | 110 |
| 85 | Templeton | B | 8 | 3 | 120 |
| 86 | Ivanov | C | 6 | 2 | 140 |
| 87 | Sansuke | C | 5 | 3 | 90 |
| 88 | Jabba | C | 9 | 1 | 30 |
| 89 | Marie | C | 11 | 5 | 250 |
| 90 | Viki | M | 13 | 2 | 220 |
| 91 | Qlon | C | 6 | 4 | 300 |
| 92 | Hellion | M | 17 | 3 | 70 |
| 93 | Jeane | M | 15 | 2 | 200 |
| 94 | Kasios | M | 8 | 3 | 30 |
| 95 | Antonio | B | 6 | 4 | 180 |
| 96 | Lester | B | 5 | 4 | 190 |
| 97 | Maas | C | 7 | 4 | 90 |
| 98 | Meese | C | 8 | 4 | 90 |
| 99 | Moose | C | 9 | 4 | 90 |
| 100 | Marco | B | 5 | 2 | 30 |
| 101 | Chapman | O | 6 | 3 | 80 |
| 102 | Chandler | O | 9 | 2 | 150 |
| 103 | Mace | B | 10 | 4 | 100 |
| 104 | Leon | C | 1 | 2 | 250 |
| 105 | Clive | B | 9 | 4 | 30 |
| 106 | Pesmerga | C | 8 | 6 | 5 |
| 107 | Crowley | M | 20 | 5 | 50 |

The character names come from mapping each war id through `0x8002badc` to
a recruitment slot and then through `lib/Characters/Addresses.lua`. The
soldier totals of the kuwa savestate (5625) match, but a name could still
be off by one slot, so treat the names as labels and the ids as truth.

| id | name | members (power order) |
|---:|---|---|
| 0 | Commander's Team | Hero, Pahn, Cleo |
| 1 | Humphrey's Team | Humphrey, Alen, Grenseal |
| 2 | Lepant Family | Lepant, Gremio, Sheena |
| 3 | Knights Party | Max, Sancho, Qlon |
| 4 | Former Imperial Team | Kasim, Griffith, Valeria |
| 5 | Viktor's Team | Viktor, Warren, Taggart |
| 6 | Warrior's Village Kids | Flik, Tengaar, Hix |
| 7 | Fishermens | Tai Ho, Yam Koo, Kimberly |
| 8 | Wild Geese | Kreutz, Morgan, Kirke |
| 9 | Bandits | Varkas, Sydonia, Kessler |
| 10 | Pirates | Anji, Leonardo, Kanak |
| 11 | Invulnerable Defense | Kwanda, Eikei, Gaspar |
| 12 | Carpenters | Gen, Kamandol, Tesla |
| 13 | Secret Factory Team | Mose, Ronnie, Sarah |
| 14 | Old Soldiers | Kai, Liukan, Fukien |
| 15 | Black Golds | Maas, Meese, Moose |
| 16 | Good Buddies | Marie, Onil, Sansuke |
| 17 | Fellows | Blackman, Zen, Ivanov |
| 18 | Tricksters | Juppo, Jabba, Meg |
| 19 | Forest Protectors | Kirkis, Sylvina, Stallion |
| 20 | Experts | Clive, Pesmerga, Mace |
| 21 | Adventurers | Lorelai, Quincy, Mina |
| 22 | Archers | Rubi, Georges, Marco |
| 23 | Kobolds | Fu Su Lu, Kuromimi, Gon |
| 24 | Thieves | Krin, Ledon, Giovanni |
| 25 | Engineers | Sergei, Hugo, Templeton |
| 26 | Cooks | Antonio, Lester, Rock |
| 27 | Children of the Runes | Crowley, Luc, Lotte |
| 28 | Magicians | Jeane, Hellion, Viki |
| 29 | Narcists | Milich, Vincent, Esmeralda |
| 30 | Soldier Beauties | Sonya, Eileen, Camille |
| 31 | Musicians | Kasios, Melodye, Window |
| 32 | Strategists | Mathiu, Leon, Apple |
| 33 | Ninjas | Kage, Kasumi, Fuma |
| 34 | Dragon Knights | Joshua, Milia, Futch |
| 35 | Merchants | Kun To, Chapman, Chandler |

Example (the kuwa savestate): recruited ids 0-5, 7-9, 14-23, 39, 48, 74, 83
and 90 give 5625 soldiers. Unit 0 has Hero (base 14), Pahn (+5) and Cleo
(+7), so its power is 26, which is what the menu shows.

## Turn flow

The per-frame function (`0x80010368`) switches on the phase (`0x800a7760`):

- 0: one frame of setup, goes to 1
- 1: picks the enemy's action for the turn, builds the command menu, goes
  to 2
- 2: the command menu (`0x80014a48`). Choosing Charge, Bow or Magic goes to
  phase 3. Choosing Others goes to phase 4.
- 3: the round (`0x8001d488`), a state machine on `0x800a77a8`
- 4: an Others command (`0x80020154`). Everything except the Dragon Knights
  returns to phase 2 without ending the turn.
- 5-7: intro and outro screens
- 8: the end of the battle

The enemy's action is chosen at the start of the turn, before the player
picks. The Ninja and Thief commands show it. Nothing in the menu phases
uses `rand()`, so the RNG stands still while the player decides.

### Command menu order

The list for a category is built by `FUN_80014f24` (kuwa): it walks the
groups 0 to 35 in index order and keeps the ones that are available, of that
category, and not hidden (Thief and Ninja once either was used this turn).
The bytes go to `0x800a7658` and the count to `0x800a73d0`. When the player
picks a category, `FUN_80013478` sorts that array with the BIOS `qsort`
(A(0x31), through `0x80147d48`), comparator `0x80014eb4`:

- the key is `FUN_8001aa30(group)`, the unit power the menu shows
  (the Strategist x1.5 included)
- it returns -1 when the first key is higher, 1 when lower and 0 when equal,
  so the list is highest power first

The BIOS `qsort` is a recursive quicksort and it is not stable, so units
with the same power come out in an order that depends on the whole list
(which units are left, in group order). Per call, `qsort(lo, hi)`:

```
while lo < hi:
    swap(v[(lo + hi) >> 1], v[hi])        # the pivot goes to the right end
    i = lo - 1; j = hi
    loop:
        do i++ while cmp(v[i], v[hi]) < 0 and i < j
        do j-- while i < j and cmp(v[j], v[hi]) > 0
        if i >= j: break
        swap(v[i], v[j])
    swap(v[hi], v[i])
    qsort(lo, i - 1)
    lo = i + 1
```

`WarSim.bios_qsort` and `Battle.menu(cat)` implement it. Checked against
60 live menus from `TeoWB2T1.State` with random members removed (all 60
lists match, ties included; `scripts/WarMenuOrder.lua`). The tie order does
not change the battle: the resolver only sees the power. It matters for how
many cursor presses reach a given unit.

### Round states (phase 3)

```
0     reset, 1 frame
1     the player's shout (0x14 frames, then a text box)
2/3   the enemy's action text ("Kwanda's Attack")
4     the resolver (0x8001b610): rolls the losses, starts the animation
5     the soldier animation, Charge/Bow rounds (0x8001c228)
6/7   other animation variants (Magic, the Dragon Knights)
8     results panel: applies the losses to the true counts
9..0x10  the banter event (a random character comments)
0x13  waits for the text boxes and sprites, then jumps to 0x800a77d0
0x14  end of the round
```

State 0x14 (`0x8001d488`, case 0x14):

```
if enemy soldiers == 0: victory (outcome 0), phase 8
else if player soldiers == 0: defeat (outcome 5), phase 8
else:
    if strategist buff > 0: buff = buff - 1
    thief/ninja flag = 0
    phase = 0 (next turn)
turns completed = turns completed + 1
```

The turn counter is incremented on the victory/defeat paths as well.
When all Charge, Bow and Magic units have been used, the command menu ends
the battle with outcome 8 after about 70 frames (`0x80013478`). Only
Others units left counts as none left.

## Enemy action choice

`0x8001afdc` runs once per turn in phase 1. The scenario has up to 6 enemy
actions (type, power, name) and a turn script of `(min, max)` pairs:

```
lo, hi = script[position]
n = hi - lo + 1
repeat:
    r = rand()
    k = 0x7fff / n                 (integer division)
    action = r / k + lo
until used[action] == 0
used[action] = 1
position = position + 1
if position > 4 (> 5 in `last`): clear used[], position = 0
```

So the enemy plays its actions without replacement, in the order the script
allows, and the whole thing repeats after 5 turns. The first turn of kuwa is
`(4, 4)`, which is always Kwanda's attack (it still draws one `rand()`).
Rejected draws cost one `rand()` each, so the number of calls is not fixed.

Quirk: `r / k` can equal `n` for the last few values of `r`
(`r >= n * k`). The action index is then `hi + 1`, outside the script's
range. That is a 1 in 8000 event for `n = 4`.

## Command resolution

The resolver (`0x8001b610`) runs once per Charge/Bow/Magic round, in state
4. It reads the matchup from a 3x3 table at `0x8002bbfc` (same in all six
regular scenarios), indexed by `player_category * 3 + enemy_type`:

```
                enemy Charge   enemy Bow   enemy Magic
player Charge   2 (tie)       0 (win)     1 (lose)
player Bow      1 (lose)      2 (tie)     0 (win)
player Magic    0 (win)       1 (lose)    2 (tie)
```

Definitions:

```
pPow = unit_power(unit) + player_soldiers / 3000    (Charge/Bow rows)
ePow = enemy_power + enemy_soldiers / 3000
raw  = unit_power(unit) without the soldier bonus
r1, r2 = rand() >> 16 & 0x7fff, taken in this order; roll(r) = r / 537 - 30
         (so the roll is a value from -30 to +31)
```

`unit_power` includes the Strategist multiplier. `enemy_power` is the raw
power byte of the enemy's action. Losses are soldiers removed from that
side. Results (verified live except where marked):

```
player Charge vs enemy Charge  (tie)
    enemy loss  = 100 * pPow + roll(r1)
    player loss = 100 * ePow + roll(r2)
player Bow vs enemy Bow  (tie)
    enemy loss  = 90 * pPow + roll(r1)
    player loss = 90 * ePow + roll(r2)
player Charge vs enemy Bow  (win)
    enemy loss  = 130 * pPow + roll(r1)
    player loss = 80 * pPow + roll(r2)
player Bow vs enemy Charge  (lose)
    enemy loss  = 80 * pPow + roll(r1)
    player loss = 130 * pPow + roll(r2)
player Bow vs enemy Magic  (win)
    enemy loss  = 120 * pPow + roll(r1)
    player loss = 0
player Magic vs enemy Bow  (lose)
    enemy loss  = 0
    player loss = 120 * ePow + roll(r1)
player Magic vs enemy Charge  (win)
    enemy loss  = 200 * raw          (no roll, no rand call)
    player loss = 0
player Charge vs enemy Magic  (lose)
    enemy loss  = 0
    player loss = 200 * enemy_power  (no roll, no rand call; raw power)
player Magic vs enemy Magic  (tie)
    r = rand()
    k = 0x7fff / (raw + enemy_power + 1)
    if r / k < raw: enemy loss = 200 * raw, player loss = 0
    else:           enemy loss = 0, player loss = 200 * enemy_power
```

Notes:

- In the two Charge/Bow rows where one side wins by the triangle, the
  damage uses only the player's power, both ways. The enemy's power does
  not matter there.
- Bow beats Magic and Magic beats Charge deal a fixed 120/200 per power
  point to the loser and nothing back.
- The Magic tie roll wins for the player when `r < raw * k`. For raw 19 vs
  12 that is `r < 19437`; the boundary was checked at `r = 19436` (win) and
  `19437` (loss).
- A round where the player lost the matchup (matrix value 1) sets
  `0x800a7498 = 1`. That arms the banter event. The Magic tie never sets
  it, even when the player loses.

### Clamping

After the losses are rolled, `0x8001b4e8` clamps each loss to the side's
current soldiers. If both are clamped (both armies would be wiped out in
the same round), the tie is broken with one more `rand()`:

```
r = rand()
player loss = player soldiers - r / (0x7fff / (player soldiers + 1)) - 1
```

The enemy stays at a loss equal to its soldiers (it dies). The player
survives with `r / k + 1` soldiers. For large armies `k` is small and `r / k`
can exceed the player's count, which makes the loss negative (the army
grows). It is a bug but a rare one.

If only the player is clamped the battle is lost, and if only the enemy is
clamped it is won.

### Applying the losses

The resolver only stores the losses. Nothing changes the true counts until
state 8 (`0x8001c68c`), after the soldier animation (it took 630 frames in
the traced Charge round and varies with the RNG):

```
player soldiers = player soldiers - player loss
enemy soldiers  = enemy soldiers - enemy loss
unit used[unit] = enemy loss        (any value other than -1 = used)
```

The HUD counters (`0x800a7350`/`0x800a7352`) tick down 5 per frame when the
fight animation ends, which is why a trace of them shows two staircases.

Every unit can be used once per battle. The used array is created at the
start of the battle and never cleared.

## Others commands

Choosing Others lists the Others-type units (type 3 first member). Each unit
has its own handler (`0x80020154`, selected in `0x8001ff3c` by unit id).
Apart from the Dragon Knights, none of them uses up the turn: after the
text the game returns to the command menu with the enemy action unchanged.

### Strategists (unit 32, handler `0x80020eb8`)

Sets `strategist buff = unit_power(unit 32)` (1 for Mathiu alone, 3 with
Leon, 4 with Apple too). The unit is marked used. While the buff is above
zero, `unit_power` multiplies every unit whose first available member is
type Charge by 1.5 (integer, see above). The buff drops by 1 at the end of
each completed turn, so a buff of 1 covers exactly the next round.
No `rand()`.

### Ninjas (unit 33, handler `0x8002051c`)

Always reveals the enemy's action for this turn. Sets `0x800a7691 = 1` and
marks the first available member as used up (`0xfc`). The unit stays
available while it has a member left. No `rand()`.

### Thieves (unit 24, handler `0x80020870`)

One `rand()`, `q = r / 0x1fff` (0 to 4):

```
r <= 16381 (q 0, 1)   reveals the enemy's action
r 16382..24572 (q 2)  fails
r >= 24573 (q 3, 4)   steals 2000 bits (the save's gold at +0x1c, max 999999)
```

All three outcomes set `0x800a7691 = 1` and use up the first available
member. Verified at both boundaries of the buckets.

### Merchants (unit 35, handler `0x80021284`)

One `rand()`, `q = r / 0x1fff`. Let `deficit = player cap - player soldiers`
(the cap is the army size at the start of the battle):

```
q == 0 or deficit == 0:  fails
q == 1:  gain = min(deficit, enemy soldiers / 8)
q >= 2:  gain = min(deficit, enemy soldiers / 4)
player soldiers += gain; enemy soldiers -= gain
```

The unit is marked used in every case. The bucket boundaries are the same
as the Thieves' (`r < 8191` fails, `8191..16381` is the 1/8 case).

### Dragon Knights (unit 34, handler `0x80021a98`)

Uses up the turn. If the enemy's action this turn is a Bow attack, the
Knights are countered: nobody takes damage. Otherwise the enemy loses
`enemy soldiers / 4` and the player loses nothing, whatever the enemy's
action was (it does not get to attack). In both cases the unit is marked
used. The countered case rolls the banter chance (below), the damaging
case does not.

## Banter event

After a round where `0x800a7498 == 1` (and after a countered Dragon
Knights round), state 8 rolls a banter event:

```
r = rand()
if r / 324 < 90  (r < 29160) and the unit has at least one "speaking"
available member: banter, else go straight to the end of the round
```

`0x8001af44` decides who can speak: the character must be available and have
a 2-bit field equal to 1 in a small table at `0x8002bb48` (the field is
`table[id >> 2] >> ((3 - (id & 3)) * 2) & 3`). In the banter:

1. State 9 draws `r = rand()` and picks the `(r / (0x7fff / n)) + 1`th
   speaking member (`n` = the number of speaking members). If the index
   is larger than `n` nobody is picked and the previous speaker is kept.
2. State 0xd draws `r = rand()`. `r / 324 > 44` (`r >= 14580`) picks one of
   the two possible lines, otherwise the other.

So a round the player lost can cost up to 3 extra `rand()` calls, and
they do not depend on any frame timing.

## Scenario data

Per-scenario values (kuwa layout; produced by `scripts/WarDataDump.py`).
Types: C Charge, B Bow, M Magic. A turn script entry `a-b` means "random
action index from a to b, not used yet"; indexes start at 0.

kuwa (Panna Yakuta): enemy 9000 soldiers, 300 soldiers per sprite.

```
0 C 12 Charge Attack    1 C  8 Charge Attack    2 B 11 Bow attack
3 M 12 Magic Attack     4 C 25 Kwanda's Attack
script: T1 4-4, T2..T5 0-3
```

gara (Garan): enemy 6000, 300 per sprite.

```
0 C 12   1 C  9   2 C  7   3 B  8   4 B 13
script: T1..T5 0-4
```

sca2 (Scarleticia 2): enemy 12000, 400 per sprite.

```
0 C 12   1 C 13   2 B  8   3 B  8   4 M 17 Milich's Attack
script: T1 0-0, T2 4-4, T3..T5 0-3
```

kita (Northern Checkpoint): enemy 3700, 450 per sprite.

```
0 C 13   1 C 20 Griffith's Charge   2 B 11   3 B 11   4 M 13
script: T1..T5 0-4
```

shas (Shasarazade): enemy 17000, 500 per sprite.

```
0 C 10   1 C 15   2 B 14   3 C 25 Sonya's Charge   4 M 17 Sonya's Magic
script: T1 4-4, T2..T5 0-3
```

last (the last battle): enemy 20000, 600 per sprite.

```
0 C 18   1 C 18   2 B 12   3 M 13   4 M 15   5 C 30 Yuber's Charge
script (6 turns): T1 0-4, T2 0-4, T3 5-5, T4 0-4, T5 0-4, T6 0-4
```

These agree with the community table of enemy actions (checked against
the Suikosource war guide). Because each action is used once, T2 to T5 of
kuwa is a permutation of actions 0-3, and `last` plays all 6 actions once.

## Scripted scenarios

Every overlay was compared with kuwa instruction by instruction (opcodes
and registers, then the immediates). gara, sca2, kita, shas and last differ
only in the constants listed under "Files" (kita also has a different
graphics pointer at `0x80010a7c`, which does not touch the battle). That
leaves three overlays that behave differently: teo1, sca1 and teo2. teo2
is covered in its own section below. teo1 and sca1 are static analysis
only (no savestate yet) and are implemented in `WarSim.py` on that basis.

Their layout differs from kuwa (the globals sit thousands of bytes away),
but units, Others commands, the end-of-round code, the enemy action pick
and the sprite states are the same as kuwa's (the sprite handlers are
byte-identical in teo1 and sca1). The three differences:

1. A scripted resolver (the enemy action only decides which text shows).
2. A turn limit in the command menu (`FUN_80013478`, `0x800135f4`): when
   the menu opens and the turn counter equals the limit, the battle ends
   with outcome 8 after the usual 70 frame delay. The limit is 3 in teo1
   and 1 in sca1 (kuwa has no such check, nor does teo2).
3. The outcome setter (`0x8001f7fc` in kuwa, kuwa `0x8001f804` and
   `0x8001f848`) does not write the flag `0x8017c0f8` for outcomes 5
   (defeat) and 8 in teo1 and sca1. main.exe tests that flag
   (`0x80125fcc`) and sets the gamestate to 99, GAME_OVER. So in every
   other war battle (teo2 included) outcomes 5 and 8 are a game over,
   but in teo1 and sca1 they are the scripted story loss and the game
   continues.

```
         enemy    per sprite  enemy actions (type power)   turn script
sca1     12000    400         M10 Poisonous Pollen,        T1 0-0, T2..T4
                              C10, B10, M10, C20 (Bow      0-3, T5 4-4
                              attack text)
teo1     14000    450         C30, C30, C40 (Teo)          T1 0, T2 1, T3 2
teo2     14000    450         C20, C20, C30 (Teo)          T1 0, T2 1, T3 2
```

The turn script of teo1 and teo2 has 3 entries and sca1's has 5 (the
cycle constant). The picks consume `rand()` like in kuwa.

teo1 (resolver `0x8001b624`, limit 3): the enemy never loses soldiers.
Whatever the player chose, the player loses `130 * P + roll(r1)` (one
`rand()`), `P` = the unit's power + player soldiers / 3000, clamped to the
army. The round is a Charge animation with `drift = +100` (the same
visuals as an enemy Charge against a player Bow). So the player's army
shrinks every round: with 8245 soldiers and Charge units of power 14 to 24
it ends the third round around 400 soldiers, and the battle ends when the
fourth menu would open. A smaller army is wiped out earlier (defeat,
outcome 5, no game over).

sca1 (resolver `0x8001b624`, limit 1): the enemy loses nothing; the
player loses `player soldiers * 8 / 10` (integer, no roll, no `rand()`).
The round is the Magic round without a casting circle (no casting, no
discarded `rand()`): the spell effect (115 frames), then the marked
sprites die at once, and no forming up follows. The command menu then
ends the battle (outcome 8, no game over) because the turn counter is 1.

### Teo 2 (verified)

Checked against `Teo2WBStart.State`/`TeoWB2T1.State` and 22 rows of a
brute-force spreadsheet of full battles (Charge units plus Strategists;
the sample is in `scripts/data/Teo2_bruteforce_sample.tsv`, checked by
`scripts/WarTeo2Check.py`). Every row's enemy soldier counts after each
turn matched, and 21 of 22 matched the total `rand()` index and final seed
exactly (the 22nd is the early-confirm case below).

- The seed at the start is `0x42` (not `0x43`); the first menu is 256 calls
  later (51 + 51 sprites; 8245 player soldiers, 14000 enemy, 450 per
  sprite).
- The enemy's action does not matter. Enemy loss `130 * P + roll(r1)`,
  player loss `40 * P + roll(r2)` for Charge (anything else: the player
  loses `130 * P + roll(r1)` and the enemy nothing), `P` = unit power
  (with the Strategist multiplier) + player soldiers / 3000. Charge units
  are 14, 15, 17, 19, 24; a Strategist buff makes 17/19/24 into 25/28/36.
- Its state 5 handler (a sprite whose run ends) makes 2 extra `rand()`
  calls for each player-side sprite, before the timer roll (sound rolls).
  No banter (`0x800a7498` is never set).
- Victory (enemy at 0) runs the victory screen (`FUN_80017770`) right after
  the last round: every player sprite picks a spot in -60..60 (3 `rand()`
  each, `form_up_one`), then sprite 0 once more. Kuwa has this too.
- The spreadsheet "Index" column is the total number of `rand()` calls since
  the seed (the RNG column is the state after that many), "Time" the real
  battle time.
- Whole sheet (720 rows, `scripts/WarTeo2Check.py` and
  `scripts/WarTeo2GapScan.py`): 635 rows reproduce exactly (enemy counts,
  total `rand()` index, final seed) assuming everyone has arrived. 62 of
  the other 85 reproduce exactly with one constant early-confirm gap:
  276 frames (give or take a few) for most, 320 to 324 for rows that open
  with the buffed 36. That is the bot's confirm cadence, applied after
  the last frame of each round's animation (including the 13 frame wait).
  23 rows are unexplained (their counts mostly differ after some round,
  so a different gap per round is the likely cause).
- Early confirm: the next turn starts whenever the player confirms. Sprites
  still walking back to their formation spots are re-aimed from where they
  are, which changes the timers and so the `rand()` use of that round
  (`Battle.gap` in `WarSim.py` = frames between a round's end and the
  next resolver; unset means everyone has arrived). In the 22 rows one
  needed it (a gap of 276 frames after round 4 reproduced its index and
  seed exactly), so the confirm timing of a run is an input to a
  prediction, not only the commands.

## The RNG stream

Everything that consumes `rand()` is in this document, in the order the
game runs it. The war battle has no hidden inputs: given the recruited
characters and the commands, the whole battle is a pure function of the
seed. The seed is reset to `0x43` when a war starts (see the event reset
table in [RNG.md](./RNG.md)).

### Battle start

The first command menu of kuwa (`KwandaWBT1.State`) is exactly 251 `rand()`
calls after the start (`KwandaWBStart.State`, seed `0x43`):

```
for each sprite (player side first, then enemy side):
    x = r / 537 + 180 (player) or -(r / 537) - 180 (enemy)    1 rand()
    y = r / 819 + 70                                            1 rand()
formation: FUN_800176a8, 3 rand() per sprite (see "Forming up")
first enemy action pick                                         1+ rand()
```

An army of `n` soldiers has `n / N + 1` sprites (N = soldiers per sprite).
For kuwa that is 19 sprites for 5625 soldiers and 31 for 9000. That is
`2 * 50 + 3 * 50 + 1 = 251`. After the formation the sprites walk to
their spots without using `rand()`.

### Where `rand()` is used

Per round, in order:

1. Phase 1 (turn start): the enemy action pick (1 call, more if it draws
   an action that was already used).
2. State 4 (resolver): 0 to 2 calls for the rolls, 1 for the Magic tie
   roll, then the animation setup (below), plus one throwaway `rand()` in
   every Magic branch.
3. The animation: the soldier sprites. A Charge or Bow round takes
   roughly 3000 to 30000 calls (the more sprites are running, the more),
   a Magic round only a few hundred to a few thousand.
4. State 8: the banter calls (up to 3).
5. Phase 1 of the next turn: the next enemy action pick.

Nothing uses `rand()` while the game waits for text boxes (states 0 to 3
and every `0x13` wait except for the sprites updating), so the time the
player spends in menus and dialogs does not matter. The only input
dependent timing is how many frames the text boxes take.

## Soldier sprites

Each army is drawn as `cap = soldiers / N + 1` sprites (the capacity is
fixed at the start of the battle). A sprite is 28 bytes. The fields that
matter for the RNG:

```
+0x00 s16 x    pixels * 16   (the other 16 bits hold a render value)
+0x04 s16 y    pixels * 16
+0x08 s16 vx   per frame, same units
+0x0c s16 vy
+0x10 s16 tx   target x in pixels
+0x12 s16 ty   target y in pixels
+0x18 u8  state
+0x1a s16 timer
```

(Dead sprites reuse `+0x08`/`+0x0c` for the start of their flying arc, and
only bits 4..15 of x and y are rewritten when a sprite is moved or
revived, so the low nibble of the old x and y survives.)

Sprite states:

```
0     idle, vx = vy = 0
2     walking to its formation spot (timer = frames left)
3     running at the enemy (timer = frames left)
4     fighting, waits `timer` frames, may die
5     fast run (same as 3, after being picked as a runner)
6     stumbled after a 1 in 2048 roll while running (timer 0x3d)
7     corpse (stays for the rest of the battle)
8     dying (301 frames, then 7)
9     archer (timer: 0 = ready, else shooting)
10-12 Merchant flight (see below)
```

Each frame (`0x80018530`) every sprite of side 0 is updated in index order,
then every sprite of side 1, calling the handler of its state. At the end
of the frame the "sprites still to kill" flag (`0x800a7400`) is
recomputed: 1 while either kill counter is above 0. Then the fx pool is
updated. The round state machine runs before the sprites in the same frame.

All divisions are C divisions (truncate toward zero), all positions are
16-bit and wrap.

### Aiming (`0x80018098`)

Sets the velocity and the timer from the sprite's position and target:

```
dx = tx - (x >> 4);  dy = ty - (y >> 4)
if |dy| < |dx|:
    vx = speed if dx > 0 else -speed
    timer = (tx * 16 - x) / vx
    if timer == 0: state = 0 else vy = (ty * 16 - y) / timer
else:
    vy = speed if dy > 0 else -speed
    timer = (ty * 16 - y) / vy
    if timer == 0: state = 2 else vx = (tx * 16 - x) / timer
```

### Starting a run (`0x800156b0`, "retarget")

Called for every sprite when a Charge round starts and again whenever a
running sprite's timer runs out. Does nothing for states 7 and 8. With
`(lo, hi)` = `(drift, 150)` for the player side and `(-150, drift)` for the
enemy (`drift` is +100, -100 or 0, see below):

```
r = rand()
if r / 324 < 20:                       (6.2%: a fast runner)
    tx = drift + rand() / 799 - 20;  ty = rand() / 537 + 50
    state = 5;  aim(speed = rand() / 8191 + 15)
else:
    tx = lo + rand() / (0x7fff / (hi - lo + 1))
    ty = rand() / 537 + 50
    state = 3;  aim(speed = rand() / 8191 + 13)
```

So it uses 4 `rand()` calls either way.

### State handlers

```
2: x += vx; y += vy; timer -= 1; if old timer <= 0: state = 0, v = 0
3: x += vx; y += vy;
   if rand() >> 4 == 1: state = 6, timer = 0x3d            (16/32768)
   else: timer -= 1; if old timer <= 0: retarget
4: n = min(2, alive[side] / 5); timer -= 1
   if old timer <= 0:
       if kills[side] > 0:
           if rand() / (0x7fff / (n + 1)) == 0 and
              (alive[0] == 1 or side != 0 or idx != 0):
               die(); spark; rand();           (the 2nd call picks a sound)
               kills[side] -= 1; alive[side] -= 1; return
       retarget
5: x += vx; y += vy; timer -= 1
   if old timer <= 0: state = 4, timer = rand() / 1057 + 60, v = 0
6: timer -= 1; if old timer <= 0: retarget
8: timer += 1; if old timer > 300: state = 7
0: vx = vy = 0
```

`die()` sets state 8, timer 0 and spawns a spark in the fx pool. The first
sprite of the player side cannot die unless it is the last one.
`alive[side]` is the number of sprites not yet dead (`0x800a7738`,
`0x800a773a`).

### Kill counters

The resolver stores how many sprites each side has to lose:

```
kills[side] = alive[side] - (new_soldiers / N + 1)
(all alive sprites if new_soldiers == 0)
```

where `new_soldiers` is the army after the loss. The counter can be
negative (the army grew). Sprites die only through `kills`, so the number
of sprites always follows the soldier count after the round.

## The three round animations

All of them end with `FUN_800176a8` ("forming up", below) except Magic.
Each state first waits 13 frames (the `0x13` wait while the text boxes
close) with the sprites already running. Then:

### Charge and Charge/Bow rounds (state 5)

Used for Charge vs Charge, Charge vs Bow and Bow vs Charge. The resolver
sets `drift` (0 for Charge vs Charge, +100 when the player Bow is attacked
by a Charge, -100 when the player Charge beats a Bow), then retargets every
sprite of both sides (`0x80015a34`: side 0 in index order, then side 1),
then sets the kill counters and the state timer to `0x3c`.

Each frame in state 5 (`0x8001c228`):

```
spawn_runner(side 0); spawn_runner(side 1)
fin = a7400 unless alive[0] == 0 or alive[1] == 0 (then 0)
if fin == 0:
    timer -= 1
    if old timer <= 0: form up; wait 13 frames; next state
```

The timer only counts down once both kill counters are 0, so the fight
lasts until the last sprite has died, plus 61 frames.

`spawn_runner(side)` (`0x8001613c`): `n = min(3 * alive[side], 60)`;
`r = rand()`; if `r / (0x7fff / (n + 1)) == 0`, take the highest index
sprite whose state is not 4, 5, 7 or 8 (if any) and make it a runner:
`tx = drift + rand() / 799 - 20`, `ty = rand() / 537 + 50`, state 5,
aim with `rand() / 8191 + 15`.

### Bow rounds (state 6)

Used for Bow vs Bow, Bow vs Magic and Magic vs Bow. The resolver puts the
archers (`0x800164ec`) in state 9 with timer 0: the player side, the enemy
side or both (a tie), allocates a pool of 30 arrows and sets the state
timer to `0xf0`. Nobody retargets or runs; the dead are chosen by the
arrows.

Archer (state 9, per frame):

```
if timer == 0:
    if rand() / 324 == 1: timer = 0x57              (about 1% per frame)
    return
timer -= 1
if timer == 0x1c:
    if rand() / 16383 == 1:                          (about 50%)
        if the target side has no living sprite: ground shot
        else: repeat t = rand() / (0x7fff / cap[target side])
              until state[t] is not 7 or 8; shoot sprite t
    else: ground shot                                (2 rand() calls)
```

An arrow takes 101 frames: when its timer runs out (`timer -= 1`, old
timer <= 0) it hits its target (kills it if the target is alive, its side
still has kills left, and the target is not the player's first sprite
unless it is the last one) and spawns a spark. A ground shot does
nothing else.

State 6 per frame (`0x8001c338`): once both kill counters are 0 the timer
counts down from `0xf0`. When it runs out the archers are set back to idle
(state 0), and when no arrow is in flight the sprites form up and the
round ends. Arrows are updated every frame in this state.

Rare quirk: `r / (0x7fff / cap)` can equal `cap`, which reads past the
sprite array. The sim ignores that arrow. (About 1 arrow in 3000.)

### Magic rounds (state 7)

The resolver sets the casting side (the Magic side of the matchup) to
state 2 and makes it walk to a circle (`0x80016bec`):

```
first living sprite: tx, ty = (+90, 70) player / (-90, 70) enemy
    aim(rand() / 4681 + 12), state 2
k = 0
each other living sprite, in index order:
    angle = (4096 / (alive - 1)) * k;  k += 1
    tx = sx + (cos(angle) >> 4) * 40 >> 8
    ty = (sin(angle) >> 4) * 20 >> 8 + 70
    aim(rand() / 4681 + 12), state 2
```

`sin` and `cos` are the BIOS-style `rsin`/`rcos` (4096 = full turn). The
quarter-wave table at main.exe `0x801765bc` is exactly
`round(4096 * sin(i * pi / 2 / 1024))` for `i = 0..1024`. Then one more
`rand()` is thrown away (called right after the kill counters are set).

State 7 per frame (`0x8001c498`): nothing happens until no sprite of
either side is in state 2. Then the spell effect (`0x8001e45c`) advances:

```
phase 0: v += 4, until v > 100               26 frames, one call per frame
phase 1: v += 2, until v > 150               76 calls, one call per 2 frames
phase 2: v -= 8, until v < 0                 13 frames
```

The second phase takes two frames per call because it waits for vblank
inside the call. When the effect finishes, all marked sprites die at once
(from the highest index down, `0x80016fe4`) and the round ends. There is
no forming up after a Magic round, so the casters stay in their circle.

### Forming up (`0x800176a8`)

After Charge and Bow rounds, every living sprite (both sides, side 0
first) picks a new spot:

```
tx = lo + rand() / (0x7fff / (hi - lo + 1))   (50..135 player, -155..-70 enemy)
ty = rand() / 537 + 50
aim(rand() / 4681 + 12); state = 2
```

3 `rand()` calls per living sprite. The sprites keep walking (no `rand()`)
while the results panel is up, which is why the next round always starts
with them idle.

## The fx pool

Sparks (hits, deaths) and flying bits use a pool of 30 entries. It never
touches the RNG except in one place: when a Dragon Knight throws a bit
(below) the game takes one more `rand()` only if a free entry exists. A
spark lives 17 frames. A bit starts with `vx = -30`, `vy = 0`, `vy += 1`
each frame, and ends when its y exceeds its ground height.

## Others, in the sprite engine

### Merchants

When soldiers change hands (`gain > 0`) the flow (`0x80021284`) is:

1. The kill counters are set from the new armies. The enemy's last living
   sprites (as many as the enemy's counter) fly to the player's side
   (states 10, 11, 12, 151 + 92 frames, no `rand()`) and become corpses.
2. Then dead player sprites come back, highest index first, as many as
   the player's counter is below 0. A revived sprite is placed at x = 0,
   y = 60 (keeping the old low nibble of x and y) and forms up
   (3 `rand()` calls each, `FUN_800174a0`).

If nothing changes hands there is nothing else: the roll is the only call.

### Dragon Knights

25 knights are created (`0x800191cc`), 5 `rand()` calls each:

```
x0 = r1 / 404 + 160;  y0 = r2 / 799 - 140
tx = r3 / 404 - 240;  ty = r4 / 799 - 80
wait = r5 / 270 + 20 frames (state 0x1e)
```

Then each knight flies for 181 frames (state 0x1f, `t` = 0..180):

```
x = x0 + (tx - x0) * t / 180
y = y0 + (ty - y0) * t / 180 + ((rsin(t * 2048 / 180) >> 4) * 100 >> 8)
if x < 80:
    r = rand()                 if r / 1057 == 0 and damage > 0:
                                   rand(); throw a bit (1 rand() if free)
    r = rand()                 if r / 1057 == 0 and damage == 0 (countered):
                                   state 0x21: shot down, falls, spark
```

Each knight is updated in index order, once per frame, and the loop ends
when no knight is waiting, flying or falling. In a countered round the
enemy archers (state 9) shoot at the same time, with the arrows landing
afterwards, and then the army forms up (3 calls per living sprite). When
the knights do damage the marked sprites die at once afterwards (no
`rand()`). Their iteration 0 only runs the sprite update (the 125 `rand()`
calls of the setup share a frame with the archers' first update).

The countered round ends with the banter roll, as above.

## Round timeline

Frames after the player confirms a command, for the Hero's Commander
Team Charge against Kwanda's attack, seed `0x12345678`, no buttons pressed
(frame numbers are the recorded frame counter, give or take one):

```
1..230     shout, enemy action text (states 1 to 3, no rand())
231        resolver (state 4), the runners start
232..244   13 frame wait (the sprites already run)
245..874   the fight (state 5), 630 frames in this seed
874        forming up (the fight ends)
875..887   13 frame wait
888..1068  results panel (state 8), 181 frames
1069..1081 13 frame wait, round end, next turn start
1082..1098 pick, menu fades in, ready
```

The first block depends on the text only: the resolver ran at frame 231
for this unit, 222 for the Bow unit 30 and 258 for the Magic unit 27 in
the recordings. The fight is the only part that depends on the RNG
(Magic rounds: the walk to the circle plus about 115 effect frames). From
the forming-up frame to a ready menu there are about 225 frames, unless a
banter text waits for a button. Buttons shorten the text waits.

## Reference implementation

`scripts/WarSim.py` implements all of the above (Charge, Bow, Magic and
all five Others commands) for the six regular scenarios. It is
executable documentation: one Python file, no dependencies, reading only
the overlay files. It starts from the seed and the recruited ids:

```python
from WarSim import start_battle
b = start_battle('kuwa', recruited=[0, 1, 2, 3, 4, 5, 7, 8, 9, 14, 15, 16,
                 17, 18, 19, 20, 21, 22, 23, 39, 48, 74, 83, 90])
b.units(0)            # groups offered under Charge
b.play(0, 0)          # Charge with unit 0; returns losses, frames, outcome
b.use_merchant(35)    # Others
```

`b.rng` is the game's seed after each step and `b.frames` the number of
sprite frames simulated. `scripts/WarChainDump.lua` records a list of
commands from the first kuwa menu (every frame: RNG, round globals, all
sprites, the fx pool, the arrows and the Dragon Knights);
`scripts/WarAnimCompare.py` replays the recording through `WarSim.py` and
compares every simulated frame, and `scripts/WarSimCompare.py` compares at
the command menus only (RNG, soldier counts, enemy action).

PSN build: the PSN release of the game (run through Adrenaline on a PSTV)
is the USA v1.0 disc (`Suikoden (v1.0).bin`; `MAIN.EXE` md5 `c87657cf...`), not the
v1.1 disc that BizHawk has been running. 99.9% of the text of v1.0's `MAIN.EXE`
equals the PSN RAM dump at the same addresses (the rest is runtime-modified
data) and its `war_kuwa.bin` differs from the dump by 112 runtime words. The
war overlays of v1.0 and v1.1 differ only in ~730 relocated address immediates and
6 or 7 padding words per file, so every table in this document is the same.
Compared with v1.1, `main.exe` is relinked (functions moved, the war overlay
code is the same with ~730 immediates relocated, `rand` is the same BIOS call
A(0x2f)), and `rsin` and `rcos` are a different implementation. They use the same quarter-wave
table (1024 entries) but mirror one entry differently:

```
                     disc build              PSN build
rcos, a < 0x400      T[0x400 - a]            T[0x3ff - a]
rsin, 0x400 <= a<0x800   T[0x800 - a]        T[0x7ff - a]
rsin, 0xc00 <= a<0x1000  -T[0x1000 - a]      -T[0xfff - a]
```

(the other quadrants match). Only the Magic circle (`FUN_80016bec`) and the
Dragon Knights' arcs use these, so Magic rounds keep the same `rand()` stream
but can place a sprite one pixel differently, and the next Charge round
reads those positions. Verified on one console chain (kuwa, Magic, Magic,
Charge): `start_battle(..., libgte='psn')` reproduces the console's sprite 5
(x 1530, y 1429, tx 96, ty 89), the final index 7689, the seed `0xb147d7d8`,
all 13 death frames and the 566-frame length; the disc build gives 10867 and
769 frames. `libgte='psn'` (the v1.0 disc) is the default of `WarSim.py` (the runs are on
the PSTV); `libgte='disc'` is the USA v1.1 disc as BizHawk runs it. Running the
v1.0 image in BizHawk gives the PSN behaviour without the patch.

To make BizHawk behave like the PSN build, `scripts/WarPsnPatch.lua` patches
ten instruction immediates of the disc's `rsin` (`0x8015084c`, `0x80150878`,
`0x8015089c`, `0x801508a8`, `0x80150854`) and `rcos` (`0x801508fc`,
`0x80150904`, `0x8015090c`, `0x8015094c`, `0x80150954`) in RAM: the quadrant
boundaries `<=` become `<` and the mirror constants drop by one.
`WarPsnPatchCheck.py` runs the original and the patched routines in a MIPS
interpreter for all 8193 angles from -0x1000 to 0x1000: the original equals the
disc routines and the patched equals the PSN routines exactly. Live check
(`WarPsnTest.lua`, kuwa, Magic, Magic, Charge, patch applied after the state
load): the menu seeds match the sim, the run ends at the console's seed
`0xb147d7d8` (the unpatched run ends at `0x6620060e`), and all 28 living sprites
at the third menu equal the console's RAM dump.

Not reproduced: the time spent in text boxes and the out-of-range arrow
target described above. The fx pool is modelled (a full pool changes the
number of `rand()` calls), though the recordings never needed it.

## Verification

All of this was run headless from `KwandaWBT1.State` / `KwandaWBStart.State`
(`scripts/spawn-headless-emuhawk.sh`). Do not run two instances at once, and
check that no cheat file freezes the counts (see notes/War_Battles.md).

Rules (one round at a time, seed set before the command):

- `scripts/WarRoundExperiments.lua`: Charge vs Charge on 6 seeds (every loss
  matched, the rolls are the first two `rand()` calls after the
  confirmation), all 9 matchup cells, the Magic tie roll at the boundary
  seeds (`r = 19436` wins, `19437` loses).
- `scripts/WarOthersExperiments.lua`: Thief buckets on 8 seeds (all three
  outcomes and both boundaries), Merchant gains for three deficits and five
  seeds, Strategist buff, Ninja, Dragon Knights (a quarter of the enemy,
  and the Bow counter).
- `scripts/WarMultiRound.lua`: enemy action picks for 3 seeds over 4 turns
  (a permutation, no repeats) and the unit used flags.

Animation and RNG:

- `scripts/WarChainDump.lua` records frames (see above). The final port
  (`WarSim.py`) was compared frame by frame (`WarAnimCompare.py`: RNG,
  alive/kill counters, every sprite, arrows, fx pool, knights) on
  command sequences of 3 to 9 commands, 16 recordings in all with 10 random
  seeds and random commands (all categories and all five Others units), and with
  `WarSimCompare.py` at every command menu. Every compared frame was
  identical, from the first command to the end of the battle (victory or
  defeat). Before the final code, a first port of the animation passed
  single rounds of all 9 matchups and both Magic tie outcomes frame by
  frame; the final `WarSim.py` was only run on the chains, which do not
  include every matchup (Magic vs Magic in particular).
- `WarSim.start_battle('kuwa', ...)` from seed `0x43` reproduces the T1
  savestate: the same RNG (`0xe9acc066` after 251 calls), enemy action and
  all 50 sprites.

Not covered by a recording: the other five regular scenarios, outcome 8
(no units left), the Merchant fail path without dead sprites to revive,
and the three scripted scenarios.
