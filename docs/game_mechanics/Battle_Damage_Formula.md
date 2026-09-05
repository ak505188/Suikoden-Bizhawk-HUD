# Battle Damage Formula

Covers the actual combat-resolution *code* (damage formula, critical hits,
elemental affinity) as reverse-engineered from `main.exe` in Ghidra. This
complements [Battles_and_Encounters.md](./Battles_and_Encounters.md), which
only documents the encounter/enemy-group *memory layout* found via
live-memory-diffing from the Lua HUD side — nobody had looked at the actual
disassembly for how damage gets computed until now.

## Where the code lives, not where you'd expect

Suikoden 1 dynamically loads per-room/minigame logic from overlay files (see
the Ghidra RE workflow notes), which made overlays the natural first guess
for the battle engine too. That guess was wrong: `data/05_batle/battle1.8`
and `battle2.8` (~3.4MB each — too big to fit in the PS1's 2MB RAM as a
single overlay in the first place) turned out to be battle background/music
asset packs. Byte-diffing a live RAM dump (from the `NeclordBS.State`
savestate) against those files found only a 32KB block of SPU ADPCM audio
data — no code match anywhere.

The actual battle engine is permanently resident in `main.exe`, which makes
sense in hindsight: unlike a specific room's one-off event script, combat
math is needed everywhere in the game. It was located via a retail debug
string the compiler never stripped out (`printf("ZOKUSEI %d AISYO %d\n",
...)` — "ZOKUSEI" = element, "AISYO" = compatibility), even though
player-facing text elsewhere uses a custom charmap that's invisible to a
plain string search.

## The central battle-state struct

`DAT_8017be3c` is a pointer to the main battle-state struct in RAM, with
**590 cross-references** throughout `main.exe` — it's read from constantly.
Known offsets so far:

| Offset | Field | Notes |
|---|---|---|
| `+0x1C` | `player_count` | Used throughout as the boundary between "party member" and "enemy" indices into the combatant array below |
| `+0x20` | `max_enemy_idx` | |
| `+0x50` | `enemy_data[]` | Stride `0x8c`; `[i]+0x0` = **Id, confirmed** (used to index `attack_data_table` for elemental compatibility — but for party members this exact byte matches each character's unique roster `Id` from `lib/Characters/Addresses.lua`, e.g. Hero=8, Viktor=35, live-verified in the Combat viewer; it's a per-character/per-monster identity value, not a shared species/type category as first guessed). `[i]+0x5` = a **busy/reaction-state byte, corrected 2026-09** — earlier passes through this codebase (including this doc, at one point) called it a "dead/invalid target" flag; that was wrong. User-observed live values: `0` = idle (not moving) **or** dead (both read the same — can't distinguish from this field alone), `1` = busy performing an action (attacking, using/receiving a medicine item), `8` = being hit/targeted by an attack (stays `8` even on a miss), `9` = seen specifically when hit by a Unite attack — exact `8` vs `9` trigger not confirmed. `battle_select_enemy_target` skips nonzero-here candidates for the next-actor roll, and `battle_execute_player_attack` blocks attacking a nonzero-here target — both consistent with "don't touch someone mid-reaction," not a death check (death is handled separately via `check_combatant_valid_target`'s HP comparison). **SOLVED 2026-09-05 — this is a genuine mutex/flags byte, with dedicated set/clear/wait opcodes in the animation-script interpreter.** `play_attack_animation` (`0x800e3820`) runs a bytecode script per combatant through a 45-entry opcode table (`PTR_LAB_8016babc`, `0x8016babc` — all 45 entries function-boxed and decompiled this session). Three of those opcodes operate directly on this field:
- **`anim_op_set_busy_flags`** (opcode 15, `0x800e3eac`): `enemy_data(self-or-target)+5 |= mask` — an OR/set-bits operation, where `mask` is a 16-bit value embedded in the script itself (truncated to a byte), not a fixed interpreter constant. A script flag picks whether this targets the acting combatant or its attack's target (via `enemy_data(attacker)+4`, which `play_attack_animation` sets to the target index on every call).
- **`anim_op_clear_busy_flags`** (opcode 16, `0x800e3f44`): the mirror, AND-NOT.
- **`anim_op_wait_until_busy_flags_clear`** (opcode 44, `0x800e3fdc`): checks `mask & flags`; if nonzero, **stalls the script at this exact instruction** (returns 0 without advancing the cursor, so the interpreter re-runs it next call) until the bits clear.

Set + clear + wait is a complete mutual-exclusion primitive, built right into the animation scripting language and reused by every attack/spell/item/Unite animation. This directly confirms the user's live-gameplay model: an attack's script can mark a combatant (itself or its target) busy, and a *different* combatant's script can block on that exact flag before proceeding — which is the real mechanism behind "multiple combatants can act concurrently unless one of them requires exclusivity." Because the mask value is data embedded per-script rather than a hardcoded constant, different attacks are free to write different bit patterns — consistent with why plain hits, Unite hits, etc. can read differently (`1`, `8`, `9`) without there needing to be one universal "hit-lock" constant in the interpreter itself.

**CONFIRMED 2026-09-05 via live script-byte extraction.** The actual script data lives in the
dynamically-allocated battle struct, not statically in the loaded `main.exe` image, so reading
it required dumping raw bytes from a running BizHawk instance (`TurnOrderRNGCall.State`
savestate — see `battle_execute_player_attack`'s script-pointer chain,
`enemy_data(attacker)+8` → table slot `[1]`) rather than Ghidra's static memory. The ordinary
physical Attack's animation script — byte-identical across Hero, Viktor, and the Dragon enemy,
i.e. one shared "basic attack" script, not per-character — opens with exactly:
```
opcode 14  (AND-NOT indirect flags, mask=2)          -- unrelated cleanup
opcode 15  (SET busy flags): target=SELF,   mask=1   -- attacker marks itself busy
opcode 15  (SET busy flags): target=TARGET, mask=8   -- attacker marks its target busy
```
This is an exact, byte-level match for the user's live-observed values (`1` on the actor,
`8` on the hit target) — not inference, straight from real script data. The `9` value
(Unite hits specifically) was **not** found this pass — would need either a savestate
captured mid-Unite-attack-execution, or locating the Unite execution function itself
(`battle_select_unite_attack` only selects/validates a Unite attack, it doesn't animate/
execute it — that function isn't found yet). **Do not use this field to filter out dead
combatants** — `0` covers both idle and dead.

Two sibling flag systems were found alongside it in the same opcode table, each with the identical set/clear/wait shape, presumably for different animation-sync purposes:
- A small array at `DAT_8017be3c+0x30` (base-struct-relative, not per-combatant, gated on "am I the current actor") — opcodes 9/10/11/12 (`anim_op_set/clear_sync_signal`, `anim_op_wait_until_sync_signal_set/clear`). Likely how two combatants' scripts rendezvous for a shared effect (a plausible mechanism for Unite-attack pairing specifically).
- A 16-bit flags field at `enemy_data+0x40` — opcodes ~23–26 (`anim_op_set/clear_effect_flags`, `anim_op_wait_until_effect_flags_set/clear`) — same shape, more bits available, purpose not investigated. |
| `+0xb40`/`+0xb94` | combatant stat array | Stride `0x54`; combined party+enemy array, indexed the same way as `player_count` above. Field offsets: `+0x26` = **SKL, confirmed** (used for hit chance — opposed, attacker vs target — and summed with LUK for crit chance; matches the persistent per-character SKL stat exactly, live-verified against `lib/Characters/Characters.lua`'s save-data reader), `+0x2a` = **AGL/SPD, confirmed** (the turn-order speed stat, see [Turn_Order.md](./Turn_Order.md); matches persistent SPD exactly), `+0x2e` = **LUK, confirmed** (summed with SKL for crit chance; matches persistent LUK exactly), `+0x30` = **ATK, corrected 2026-09** (user clarification: this is a distinct stat from PWR, not just an equipment-inclusive version of it — ATK = PWR + the equipped weapon's attack bonus, which is why it never matches the persistent base PWR stat exactly), `+0x32` = DEF-like defense stat (also doesn't always match persistent base DEF — likely equipment-inclusive too). `+0x46`/`+0x47`/`+0x48`/`+0x49` = the confirmed action-selection fields — see their own section below. `+0x10`/`+0x12` = max HP / current HP (confirmed live via the project's own Combat viewer module, see below). |
| `+0xF84`/`+0xF90` | `class_ptrs` | Per-party-member pointer table (stride `0xc`); `[i]+0x1c` reaches an equipment/class record with fields `+0x46` (weapon type), `+0x47`/`+0x49` (weapon-type-specific mastery byte), `+0x4c` (a weapon-type byte checked for the crit-chance-doubling condition), `+0x55` (item-specific element override) |
| `+0x1344` | `attack_data_table` | Pointer-table indexed by the combatant's `Id` (`* 4`, see `+0x50` above); each entry's `+0x20`-relative bytes are a 6-element (at least) compatibility row: `0`=neutral, `1`=weak, `2`=resist, `3`=immune |

None of this is formally typed as a Ghidra struct yet — still raw offset
arithmetic in the decompiler output. Worth reconciling against the
independently-derived RAM-side enemy struct in
[Battles_and_Encounters.md](./Battles_and_Encounters.md#enemy-struct-60-bytes-per-enemy-libbattlelua-readenemytable)
to see whether they agree (they were found via completely different
methods — disassembly vs. live memory reads — so agreement would be a good
cross-check, and disagreement would be informative too).

## `calc_hit_chance` (`0x800f7d5c`)

`calc_hit_chance(attacker_idx, target_idx) -> bool` (returned as `-1`/`0`):

```
chance = attacker.SKL(+0x26) - (target.SKL(+0x26) - 80), clamped to [60, 99] percent
if (attacker is a party member and their combatant-record +0x4a bit 0x10 is set)
   or (attacker is an enemy and their equip-record +0x4c byte == 0x12):
    chance = chance / 2
return (rand() % 100) < chance
```

A straightforward opposed roll — both sides use the *same* stat (SKL), so
SKL doubles as both accuracy and evasion. The halving condition looks like
a "blinded"/accuracy-debuff status flag for party members and a specific
enemy equip-type check for enemies, but neither has been independently
confirmed.

## Action selection: `combatant_rec+0x46..+0x49` (CONFIRMED 2026-09-05)

Every combatant record carries a small "what did this combatant queue up this
turn" block, found by tracing a real dispatch jump table
(`g_actionTypeDispatchTable`, `0x800c13ec`, 5 function-pointer entries) that
reads `+0x47` and jumps straight into one of five handlers — this is the
same field the project's Combat viewer displays as `ACT`:

| Offset | Field | Notes |
|---|---|---|
| `+0x46` | `ActionTag` | `0` = no action queued/resolved yet, `1` = this turn's action is executing/executed. |
| `+0x47` | **`ActionType`** | `0`=Attack, `1`=Defend, `2`=Rune, `3`=Item, `4`=Unite — **confirmed via the dispatch table itself** (table indices line up with these values) **and user-verified live in-game**. `calc_damage`'s Defend-halving check (`== 1` exactly, not "nonzero") already matched this without needing correction — it was just documented as a plain boolean before this was known to be a 5-way enum. |
| `+0x48` | **`AbilitySlot`** | The selected Rune/Item/Unite menu-slot index — meaning depends on `ActionType`. Unused for Attack/Defend. |
| `+0x49` | **`TargetIdx`** | The selected target's combatant index — **one shared field for all five action types**, read identically by `battle_execute_player_attack` (Attack) and all three resolvers below (Rune/Item/Unite). |

Three separate resolver functions turn `AbilitySlot` into an actual
spell/item/Unite id and validate `TargetIdx`, one per non-trivial
`ActionType` (Attack and Defend don't need a resolver — Attack goes straight
to `battle_execute_player_attack`/`battle_execute_enemy_attack`, Defend to an
un-decompiled `FUN_800f40b8`):

- **`battle_select_special_ability`** (`0x800f5500`, `ActionType==2`, Rune):
  resolves `AbilitySlot` through a per-character "ability set" table (keyed
  by the character's equip-record class/weapon-type byte, `equip_ptr+0x4c`)
  into a spell id. Slot index `4` (the character's Level-4/highest
  elemental spell) is special-cased — see "Magic Unite spells" below. Also
  contains an internal branch for a second, differently-tabled path
  (`DAT_8016a630`) for characters whose ability-set flag is nonzero — this
  is **not** related to Unite Magic (see below); its real purpose (possibly
  an enemy/monster innate-ability table sharing the same `ActionType==2`
  slot) isn't confirmed yet.
- **`battle_try_special_attack`** (`0x800f5050`, `ActionType==3`, Item):
  resolves `AbilitySlot` by indexing the attacker's own inventory array
  (`equip_ptr+0x1c+0x20`, 4 bytes/entry: a `ushort` item id plus at least a
  use-count byte at `+0x3`) into an item id. Decrements the use-count on
  cast; at `0` calls `FUN_800ca408(class_ptr, slot_idx)` — very likely
  "remove this now-empty inventory slot".
- **`battle_select_unite_attack`** (renamed from `FUN_800f5790`,
  `0x800f5790`, `ActionType==4`, Unite): resolves `AbilitySlot` through its
  own table (`DAT_8016d18c`). This is the **manually-selected character-pair
  physical Unite Attack** command (e.g. Viktor+Flik "Twin Dragons") —
  confirmed unrelated to the magic Unite spells below. Its most interesting
  behavior: it loops every *other* party member looking for one who also
  has `ActionType==4` **and the same `AbilitySlot` value** as the current
  attacker (and is still a valid target) — this is the "wait for your Unite
  partner(s) to also select the same Unite command this turn"
  synchronization check, and it returns early (defer) if a match is found
  rather than firing immediately.

### Magic Unite spells (CONFIRMED 2026-09-05 — `battle_check_magic_unite`, `0x800f5398`)

Suikoden 1 also has five **magic** Unite spells — Scorched Earth
(Fire+Earth), Storm Fang (Earth+Wind), Water Dragon (Wind+Water), Thor
(Water+Lightning), and Blazing Camp (Lightning+Fire) — per
[Suikosource's Unite Magic page](http://www.suikosource.com/runes/unitemagic.php).
Per that source, each requires two Level-4 spells of adjacent elements cast
in the same round, triggers *automatically* (no separate menu command), the
faster caster's MGC/2 gets added to the base power, targeting/resistance
follows a strict Invulnerable→Strong→Weak→normal priority, and Thor can
only single-target if the faster caster's spell was specifically Ball of
Lightning (the only targeted Lv4 among the relevant elements).

This is a **completely different mechanic from the `ActionType==4` Unite
menu command above** — it lives entirely inside `battle_select_special_ability`
(the Rune resolver, `ActionType==2`). When a caster selects `AbilitySlot==4`
(their own Level-4 spell) and is a normal spellcaster, the resolver first
calls **`battle_check_magic_unite(attacker_idx, own_lv4_spell_id)`**
(renamed from `FUN`/originally-misnamed `battle_check_team_combo`, since it
was first found via the `+0x48==4` "combo" special-case and initially
mistaken for a physical team-combo check):

- Scans every *other* still-unresolved (`action_tag==0`) living party
  member for one who *also* has `ActionType==2` and `AbilitySlot==4` this
  round — i.e. someone else who *also* queued their own Level-4 elemental
  spell this turn, matching Suikosource's "two lv4 spells... cast in the
  same round" rule exactly.
- For each such candidate, checks the pair of spell ids against a lookup
  table (`DAT_8016c724`, 3 bytes/entry — `{spellIdA, spellIdB, comboSpellId}`
  — 40 entries total, consistent with 8 raw pairings × 5 real combo
  outputs; ids `34`/`35` confirmed present across the first 16 entries).
- On a match: marks the *partner's* action as already resolved (so they
  don't also independently cast their own spell), plays a shared animation,
  and returns the matched `comboSpellId` — which the caller feeds into the
  **same** spell definition table (`DAT_8016d33c`) normal spells use, not a
  separate table. No match → falls back to the caster's own solo Level-4
  spell.

This resolves what was previously an open question ("two Unite-shaped
paths, not reconciled"): they're two genuinely different mechanics, not a
duplicated implementation of the same one.

#### `DAT_8016c724` fully decoded

The 40-entry pairing table was decoded by reading each spell id's
`DAT_8016d33c[id]+0x1c` handler-start pointer and checking it against the
already-known `apply_elemental_multiplier` call-site addresses (each
handler's start address falls just before its own known call site, as
expected) — 40 entries = 8 raw pairings × 5 real combos, and every element
has exactly 2 ids (its Lv4 and Lv5 spell), since apparently which tier a
given character's "slot 4" resolves to depends on their own ability-set:

| Element | Lv4 id | Lv5 id | Lv4 evidence | Lv5 evidence |
|---|---|---|---|---|
| Fire | `4` | `29` | handler `0x80101130`, right before Explosion's call site `0x80101ac4` | handler `0x80101e88`, right before Final Flame's `0x801028e4` |
| Earth | `24` | `33` | handler `0x801116d0`, right before Earthquake's `0x80111ce8` | handler `0x80112048` — Earth's Lv5, not previously named/found (target-type `0`, so it likely never calls `apply_elemental_multiplier`) |
| Wind | `16` | `31` | handler `0x8010a67c`, right before Storm's `0x8010ace4` | handler `0x8010b044`, right before Shining Wind's `0x8010b918` |
| Water | `12` | `30` | never seen calling `apply_elemental_multiplier` — consistent with Water spells being ally-targeted heal/buff (see the Water/element-`1` gap already noted above); both ids have target-type `0` | (same) |
| Lightning | `20` | `32` | handler `0x8010e4cc`, right before Ball of Lightning's `0x8010ef44` — **target-type `3` (single-target)** | handler `0x8010f418`, right before Thunder God's `0x8010fea0` — target-type `1` (AOE) |

The 5 combo outputs, with their own `DAT_8016d33c` entries labeled in Ghidra:

| id | Spell | Elements | Target type |
|---|---|---|---|
| `34` | Scorched Earth | Fire + Earth | AOE (all enemies) |
| `35` | Storm Fang | Earth + Wind | AOE (all enemies) |
| `36` | Blazing Camp | Lightning + Fire | AOE (all enemies) |
| `37` | **Thor** | Water + Lightning | **`3` (single-target)** |
| `38` | Water Dragon | Wind + Water | `0` |

**Thor is the only one of the 5 flagged single-target** — an exact,
independent match for Suikosource's specific note that Thor uniquely *can*
single-target, and only when the faster caster's contribution was
specifically Ball of Lightning (Lightning's Lv4, `id 20`, itself confirmed
single-target above — consistent with Thor "inheriting" single-target only
from that particular tier). This cross-check gives high confidence in the
whole decode, not just Thor's entry.

The element adjacency forms the expected 5-cycle Fire–Earth–Wind–Water–
Lightning–(Fire), matching Suikosource's page exactly.

Not yet done: confirming the MGC/2 bonus and resistance-priority rules
Suikosource describes against this table's actual consumer code (not yet
traced past `battle_check_magic_unite` itself — the `+0x14` handler pointer
this resolves to is presumably where that logic lives); naming Earth's and
Water's Lv4/Lv5 spells properly (their handler addresses are now known,
just not yet decompiled/cross-referenced against the external spell-name
reference).

All three resolvers independently re-validate `TargetIdx` via
`check_combatant_valid_target`, gate one of their "target type" flag values
(bits `& 3` of the resolved definition's own `+0x16`/`+0x1c` field, depending
on the resolver) on a shared global counter at `DAT_8017be3c+0x2c` (**not**
the per-combatant `+0x2c` MGC stat — this is a fixed base-struct offset,
likely some kind of "uses available this turn" pool, possibly the Unite
gauge/combo count — not yet identified), and store a pointer from the
resolved definition into their own dedicated base-struct slot
(`+0x14` Rune, `+0x10` Item, `+0x18` Unite) — almost certainly an
animation/effect script pointer, one slot per action type.

Still open: what `DAT_8017be3c+0x2c`'s counter actually represents; the
still-unconfirmed `DAT_8016a630` branch inside `battle_select_special_ability`
(see "Magic Unite spells" below for why this is no longer believed to be a
second Unite path); the Defend handler (`FUN_800f40b8`) and the `[0]`/Attack
dispatch table entry (it calls `battle_execute_enemy_attack`, not the player
version — not yet reconciled with where `battle_execute_player_attack` is
actually invoked from).

## `calc_damage` — physical attack formula (`0x800f7e90`)

`calc_damage(attacker_idx, target_idx)`, both indices into the combatant
array above:

1. **Base value**: `attacker.ATK(+0x30) - target.DEF(+0x32)`.
2. **Random variance**:
   - If base `< 10`: `base = (base + 1) - (rand() % 4)` — a small flat
     ±0..3 adjustment.
   - Else: `base = base + (base/2 - rand()%base) / 5` — roughly ±10%
     variance scaled to the base value itself.
3. **Defend command**: if the target is a party member and their
   `ActionType` (`+0x47`) `== 1` (Defend — see the "Action selection"
   section above), `base /= 2`.
4. **Elemental weapon bonus** (attacker must be a party member):
   - The attacker's equipped weapon type (a byte on their equipment
     record) is mapped to an element id via `g_abWeaponTypeToElement`
     (`{0xff, 0, 1, 2, 3, 4}` — weapon types `1..5` map straight to
     element ids `0..4`; an item can instead override this via its own
     stored element field).
   - If that element's compatibility byte for the target's `Id` is `1`
     (weak), `base += base / 2` — a flat +50% bonus, on top of (not
     instead of) the variance already applied.
   - Two specific weapon types (`1` and `3`) get an *additional* bonus:
     `base += (base / 20) * mastery_byte`, where `mastery_byte` is read
     from `equip_struct + 0x46 + weapon_type` — i.e. self-indexed by the
     weapon-type value itself (type `1` → `+0x47`, type `3` → `+0x49`).
     That addressing implies `+0x46` onward is a small per-weapon-type
     mastery/proficiency array (one byte per weapon category, up to 5),
     but `calc_damage` only ever reads two of its slots. Either the other
     three weapon types' mastery bonus is applied somewhere else (a
     dedicated ranged/magic path, perhaps one of the still-unmapped
     `apply_elemental_multiplier` callers), or only these two types get
     this particular bonus at all — not yet determined. Verified against
     raw disassembly (`0x800f80dc`-`0x800f8140`); the decompiler's several
     "unreachable block" warnings in this function turned out to be
     nothing but the standard GCC/MIPS divide-by-zero and
     `INT_MIN / -1`-overflow trap idiom inserted around every signed
     `div`/`%`, not hidden logic.
5. **Floor**: damage is clamped to a minimum of `1`.

## `check_critical_hit` (`0x800f835c`)

`check_critical_hit(combatant_idx) -> bool` (returned as `-1`/`0`, C-style):

```
chance = (combatant.SKL(+0x26) + combatant.LUK(+0x2e)) / 8, clamped to [3, 25] percent
if combatant is a party member and their weapon-type byte (equip+0x4c) == 0x0f (15):
    chance *= 2   -- up to 50%
return (rand() % 100) < chance
```

`0x0f` is very likely a "high-crit" weapon category (classically a
knife/dagger-type weapon) — not yet confirmed against the actual weapon-type
enum.

## `apply_elemental_multiplier` (renamed from `FUN_80125b28`, `0x80125b28`)

The magic/rune-attack equivalent of `calc_damage` — the complete magic
damage formula, not just its elemental-scaling step.
`apply_elemental_multiplier(?, element_id, target_idx, attacker_idx,
base_power)`:

```
base_total = base_power + floor(attacker.MGC_stat / 2)
if target's compatibility byte for element_id == 1 (weak):   damage = base_total * 2
if target's compatibility byte for element_id == 2 (resist): damage = floor(base_total / 2)
if target's compatibility byte for element_id == 3 (immune): damage = 0
otherwise (neutral):                                          damage = base_total
element_id == 7 (Dark/Soul-Eater) bypasses the whole compatibility check
and always returns base_total unscaled - see the per-site table below for
why this is confirmed to be an element, not a generic bypass sentinel.
```

The attacker's stat term is read from the combatant record at an offset
I've been calling "MGC" by inference (magic spells scaling off it is the
obvious guess) — **confirmed empirically** 2026-09-05: a live cast against
a target *weak* to the spell, attacker MGC `190`, base_power `500` (see
Charm Arrow below) predicted `(500 + floor(190/2)) * 2 = 1190`, which
matched the actual observed damage exactly. No random variance anywhere
in this formula, unlike `calc_damage`'s physical path — magic damage in
Suikoden 1 is fully deterministic given base_power, the caster's MGC, and
the target's element compatibility.

The multiplier itself:
- Looks up the target's compatibility byte for `element_id` from the same
  `attack_data_table` structure `calc_damage` uses, indexed by the target's
  `Id` (`enemy_data[target_idx]+0x0` — **confirmed to be "Id", not
  "species"**: for party members this exact byte matches each character's
  unique roster `Id` from `lib/Characters/Addresses.lua`, e.g. Hero=8,
  Viktor=35, live-verified in the Combat viewer — it's a per-character/
  per-monster identity value used as a table index, not a shared
  type/category id).
- `1` (weak) → `base_total * 2`
- `2` (resist) → `base_total / 2`
- `3` (immune) → `0`
- anything else → unchanged

Called from **21 sites** spanning `0x800ff174` through `0x80117350` — a
~94KB range of `main.exe` that auto-analysis mostly failed to break into
functions (a large undefined-code gap). Ghidra's own xref search
(`get_xrefs_to`) only found 17 of these — 4 more (`0x800ff174`,
`0x801033e8`, `0x80105748`, `0x80111ce8`) sat in bytes Ghidra hadn't
disassembled as code yet, so they were invisible to xref analysis despite
being real calls. Found instead with a raw byte-pattern search for the
`jal` instruction's own opcode encoding (`ca96040c`) across the whole
binary — a search that doesn't depend on Ghidra having recognized the
surrounding bytes as code, unlike xref search. Worth doing this kind of
byte-level completeness check whenever a suspiciously-round xref count
comes out of a region with large undefined-code gaps.

### The 17 callers

Each site follows the same shape: loop over a target index, skip it if a
per-combatant byte at `combatant_rec(target)+0x45` (`DAT_8017be3c +
target*0x54 + 0xb85`) is set (an "already resolved/invalid target" flag),
otherwise call `apply_elemental_multiplier(a0, element_id, target,
attacker, base_power)` — base_power passed as a compile-time constant, not
computed. That constant is exactly what `apply_elemental_multiplier` adds
the attacker's stat bonus to (see its own doc above), so it's the spell's
base power before any scaling.

| Address | `a0` (spell level) | element | base power | Spell |
|---|---|---|---|---|
| `0x800ffcbc` | 2 | 0 (Fire) | 150 | Firestorm |
| `0x80100bdc` | 3 | 0 (Fire) | 400 | Dancing Flames |
| `0x80101ac4` | 4 | 0 (Fire) | 700 | Explosion |
| `0x801028e4` | 5 | 0 (Fire) | 900 | Final Flame |
| `0x8010998c` | 2 | 4 (Wind) | 400 | The Shredding |
| `0x8010ace4` | 4 | 4 (Wind) | 500 | Storm |
| `0x8010b918` | 5 | 4 (Wind) | 500 | Shining Wind |
| `0x8010c6e8` | 1 | 3 (Lightning) | 150 | Angry Blow |
| `0x8010d3c8` | 2 | 3 (Lightning) | 100 | Rainstorm |
| `0x8010e064` | 3 | 3 (Lightning) | 600 | Raging Blow |
| `0x8010ef44` | 4 | 3 (Lightning) | 1000 | Ball of Lightning |
| `0x8010fea0` | 5 | 3 (Lightning) | 900 | Thunder God |
| `0x8011349c` | 2 | 2 (Earth) | 300 | Voice of Earth |
| `0x80114300` | 1 | 7 (Dark) | 2 | Deadly Fingertips (instant-death; `2` stands in for its non-HP effect, not real damage) |
| `0x8011519c` | 2 | 7 (Dark) | 300 | Black Shadow |
| `0x80116078` | 4 | 7 (Dark) | 2 | Hell (instant-death to all enemies) — `a0=4` duplicates Judgement's level rather than being `3`, but confirmed by code structure, not numbering: see below |
| `0x80117350` | 4 | 7 (Dark) | 1500 | Judgement |

Identified 2026-09-04 by cross-referencing against an external reference
implementation's spell data
(`Suikoden-RNG-lib/lib/Game/Combat/Magic/Spells.js`) — every undisputed
match lines up on damage value exactly, which is what makes the mapping
solid despite having no in-binary name strings to confirm against (see
`lib/Charmap.lua` for why: player-facing text isn't plain ASCII).

Two things this resolved from the earlier (wrong) reading of this table:

- **`a0` is spell level (1-5), not dead metadata.** It's true that
  `apply_elemental_multiplier`'s decompiled body never reads `param_1` —
  that part still stands — but it clearly still carries real meaning to
  *something* (this mapping fits it to spell level with only one
  exception, `0x80116078`). The earlier claim that it "doesn't correlate
  with power monotonically" was true but the wrong test — power isn't
  level-monotonic in the game's own spell data either (e.g. Lightning
  Lv2/Rainstorm does *less* damage than Lv1/Angry Blow), so checking for
  monotonic power was never going to show the correlation that's actually
  there.
- **Element `7` is not a generic "physical/no-element bypass" sentinel —
  it's the Dark/Soul-Eater element specifically**, which narratively
  ignores normal elemental weak/resist/immune resistances by design
  (`apply_elemental_multiplier`'s `param_2 != 7` check literally
  implements that exemption). Black Shadow and Judgement both hit their
  exact reference damage values under element `7`.

### The 4 additional sites (found via byte-pattern search, not xref)

| Address | `a0` | element | base power | Spell |
|---|---|---|---|---|
| `0x800ff174` | 1 | 0 (Fire) | 100 | Flaming Arrows (single-target) |
| `0x801033e8` | 1 | 5 (Resurrection) | 70 | Scolding (double dmg vs undead) |
| `0x80105748` | 4 | 5 (Resurrection) | 500 | Charm Arrow — ROM value is 500, not the reference's 400 (confirmed live, see below) |
| `0x80111ce8` | 4 | 2 (Earth) | 700 | **Earthquake** |

Element `5` = Resurrection, confirmed by Scolding's exact match. This also
explains why element `1` (presumably Water) never appears across all 21
sites: every single Water-rune spell in the reference data targets allies
only (healing/buffs, `SIDE.ALLY`) — none of them would ever need an
enemy-species elemental-compatibility lookup, so none call this function
at all. Same reasoning already covered why each element's ally-targeted
Lv1/Lv3-type spells were absent from the original 17.

**`0x80116078` = Hell, confirmed by behavior not numbering.** The code
immediately after this call site is structurally near-identical to
Deadly Fingertips's (`0x80114300`) confirmed instant-death
implementation: both check a target-immunity flag
(`*(ushort*)(species_ptr+0x26) & 0x4000`, skip if set), then implement the
kill itself the same way — decrement an alive-count field at `+0x2c` and
clear a status byte at `+0x52`. `0x80116078`'s version does extra
bookkeeping on top (writing two more combatant-record bytes plus a global
results-array entry) consistent with it being the AOE version hitting
multiple targets, vs. Deadly Fingertips' single target. So despite `a0=4`
oddly duplicating Judgement's level instead of being `3`, the actual
executed logic confirms this is Hell ("sudden death to all enemies,
except bosses") — `a0` apparently isn't a strictly unique per-spell
level id in every case, at least not for the two instant-death spells.

## How spells call RNG: the cast state machine (CONFIRMED 2026-09-05)

`apply_elemental_multiplier` itself has no RNG (magic damage is fully
deterministic — see above). But a spell *cast* is not just that one
function call: each spell's `DAT_8016d33c[id]+0x1c` field is a **code
pointer** into a per-spell entry function, which schedules a **multi-phase,
per-tick state machine** (a heap-allocated context struct, `DAT_8017a030` in
Explosion's case, with a phase counter driving a `switch` across several
"cases" — the same tick-resumable-coroutine pattern already seen elsewhere
in this codebase, e.g. `battle_advance_turn`'s per-slot state-pointer array).
Traced end-to-end for **Explosion** (Fire Lv4, `element=0`, `base_power=700`):

- **`spell_explosion_cast_entry`** (renamed from `FUN_80101130`,
  `0x80101130`) — the actual `+0x1c` pointer. Just schedules the next phase
  via a shared (not spell-specific) scheduler.
- **`spell_explosion_vfx_setup`** (renamed from `FUN_80101158`,
  `0x80101158`) — allocates the per-cast context and sets up Explosion's
  particle effects. **Consumes roughly 70 `rand()` calls here alone**, all
  for cosmetic particle scatter: a 20-iteration loop (2 `rand()` calls each,
  X and Y jitter) for one particle batch, a 15-iteration loop (2 calls each)
  for a second batch. None of this touches damage.
- **`spell_explosion_tick_state_machine`** (renamed from `FUN_8010149c`,
  `0x8010149c`) — the per-tick driver. An impact-phase case (`case 3`) calls
  `rand()` several more times: once for a particle's velocity jitter, twice
  more (in two 20-iteration loops) for `rand()%0x3c` feeding what looks like
  a per-impact sound-effect variant/pitch select, and once more for a
  camera-shake-style accumulator (`+= rand()%0x50`). Only in the **final**
  case (`case 5`) does the actual damage get applied — `apply_elemental_multiplier(4, 0, target_idx, attacker_idx, 700)` then
  `apply_hp_damage_display` — confirming Explosion's already-documented
  parameters exactly, with **no `rand()` call in this step**.

**Net finding**: the vast majority of a spell cast's RNG consumption is for
visual/audio polish (particle scatter, impact sound variety, screen shake),
not gameplay. The exact call count is baked into each spell's own VFX code
and isn't obviously inferable from the outside — anyone trying to predict
or manipulate the RNG stream around a spell cast needs to account for the
spell's *entire* animation, not just its (RNG-free) damage step.

**Animation duration is a free byproduct of this same tracing work**: each
`tick_state_machine`'s phases are bounded by hardcoded immediate constants
compared against the phase's own tick counter (e.g. Flaming Arrow's
`if (piVar6[0x2d] < 0x60) goto ...`) — summing those across all phases and
dividing by 60 (NTSC frames/sec) gives the animation's real length without
needing any live capture. See
[Spell_RNG_Tracing_Methodology.md](./Spell_RNG_Tracing_Methodology.md) for
the full step-by-step process (this is now a recurring task); durations
confirmed so far:

| Spell | Phase tick counts | Total ticks | ≈ seconds @ 60fps |
|---|---|---|---|
| Earthquake | 64 + 64 + 128 + 64 | 320 | ~5.3s |
| Charm Arrow | 64 + 32 + 64 + 64 | 224 | ~3.7s |
| Flaming Arrow | 64 + 96 + 74 + 60 | 294 | ~4.9s |

### Earthquake: a qualitatively bigger RNG sink (CONFIRMED 2026-09-05)

Traced the same way (`spell_earthquake_cast_entry` → `spell_earthquake_vfx_setup` →
`spell_earthquake_tick_state_machine`, `0x801116d0`/`0x801116f8`/`0x80111994`),
prompted by the user noting some spells (Charm Arrow, specifically) push the
RNG stream by *tens of thousands* of calls:

- **`spell_earthquake_vfx_setup`** consumes **~100 `rand()` calls** just in
  setup (already more than Explosion's ~70) — a 20-iteration loop with 4
  calls each (~80, debris particle X-position + a 3D velocity/rotation
  vector) plus a second 20-iteration loop with 1 call each (~20).
- **`spell_earthquake_tick_state_machine`** has a 4-phase structure
  (phases of 64/64/128/64 ticks — 320 ticks total for the whole cast, ~5.3
  seconds at 60fps NTSC) with the damage application (`apply_elemental_multiplier(4, 2,
  target_idx, attacker_idx, 700)`, confirming Earthquake's documented
  params exactly, again with no RNG in that step) happening in the final
  phase, same shape as Explosion.
- **The key difference**: this function has a **shared epilogue that runs
  every single tick, in every phase** (not confined to one specific case
  like Explosion's impact phase), which loops all 20 particle slots and
  calls `rand()` once for each particle still active, to continuously
  jitter its velocity/wind-drift. Particles only go inactive once their
  X-position crosses a fixed threshold — Explosion's particles, by
  contrast, are randomized once at setup and just decay deterministically,
  with **no** per-tick `rand()` call in its own epilogue.

#### The mechanism, fully closed out (CONFIRMED 2026-09-05, validated against a real cast)

Initially assumed this epilogue could add "several thousand" calls based on
a rough per-tick-per-particle estimate — a live capture (see below) and
completing the trace corrected and precisely quantified that. The missing
piece was **where a particle's "active" flag actually gets set** — it
turned out to be **`FUN_80122eb4`** (called from `spell_earthquake_tick_state_machine`'s
phase-2 case, once per particle, at that particle's staggered spawn tick —
particle `i` of 20 spawns at phase-2 tick `i*2`, i.e. ticks 0, 2, 4, ...,
38): its first line is `param_1[7] = 1` (the flag the epilogue checks),
and it **also calls `rand()` twice** — once to pick the particle's initial
X spawn position (`x = (rand() % 198 + 1) - 100`, roughly ±99), once more
for the other two axes (which don't affect X). Since the particle's X
*velocity* is a fixed per-tick decay constant set once at construction
(`0xffff9556`, never touched by RNG) and deactivation is a fixed X
threshold, **the random spawn position is the actual source of run-to-run
variability** in how many ticks (and therefore how many further per-tick
`rand()` calls) a single cast consumes — not the per-tick jitter roll
itself, which costs a fixed 1 call per active particle per tick but varies
in *how many ticks* that applies over.

This fully closes the mechanism: `100` (setup, fixed) + `2 × 20 = 40`
(particle activation, fixed count, but each call's *value* affects that
particle's lifetime) + a variable number of per-tick jitter calls that
depends on those random spawn positions.

**Validated live**: the user provided a savestate one frame before an
Earthquake cast begins. Capturing the real RNG value at regular frame
checkpoints across the cast (see [RNG.md](./RNG.md) for the general
technique) showed the exact predicted shape — 100 calls in the first
frame, then total silence for ~124 frames (phases 0/1, no particle
activity), then a clean bell-curve burst (particles waking in a staggered
wave, peaking at exactly ~20 calls/frame — all 20 active simultaneously —
then winding down as they deactivate one by one), settling by around frame
250. (A second burst appeared further out, ~320-440, but that turned out
to be a *different* combatant's action — Ain Gide's Attack — bleeding into
the same capture window, not part of Earthquake itself; the real cutoff is
the lull at ~250.) Cutting there, the real measured total was **1626**
calls for that specific seed.

A pure-code simulator (`simulateEarthquake` in `lib/Magic.lua`; prototyped
in Python during development, not kept in the repo) implementing the exact
formulas above — no emulator required — predicts **exactly 1626** for that
same seed: a precise match, confirming the model is correct, not just
plausible. Running it across 5000 random seeds gives a tight distribution:
min 1519, max 1786, mean ~1649 — narrower than an earlier casual estimate
of "up to 2000" (confirmed after the fact to have
been an approximate recollection, not a real discrepancy to chase).

**Broader validation**: injected 20 more arbitrary seeds directly into the
same savestate and measured each one's real settle point live, then
diffed against the simulator's prediction for that exact seed — **all 20
matched exactly, zero discrepancy**, for 21/21 exact matches total
including the original. The simulator is accurate across a wide seed
range, not just the one case it was built against. (Building the
validation harness surfaced one bug worth remembering: an initial "N
consecutive unchanged frames" settle-detector falsely fired during the
~124-frame dead zone *before* the particle burst even starts, since a
single unchanged-run threshold can't distinguish "hasn't started yet"
from "is over" — fixed by requiring a minimum elapsed-frame count, past
the latest any particle could still plausibly be active, before counting
any unchanged streak toward settling.)

### Charm Arrow: a completely different mechanic, confirming "tens of thousands" (CONFIRMED 2026-09-05)

Traced next at the user's request (their earlier recollection that Charm
Arrow specifically pushes RNG by tens of thousands turned out to be spot
on, unlike the Earthquake "up to 2000" estimate). The active handler
(`spell_charmarrow_tick_state_machine`, renamed from `FUN_801052f8`,
`0x801052f8`) uses a **fundamentally different VFX mechanic** from
Earthquake's discrete 20-particle batch — a **16384-byte grid** (a
pre-rendered gradient/blob texture, confirmed via a live savestate read to
already hold a smooth radial pattern — almost certainly a "charm heart"
shape baked in during an earlier non-RNG setup phase, not randomized).

Same phase-switch architecture as Earthquake (cases 0/1/2/3 on a counter),
but only case 3 (64 ticks) touches RNG at all — cases 0/1/2 (64+32+64=160
ticks combined) have none. Total across all 4 cases: 224 ticks, ~3.7
seconds at 60fps NTSC. Each of case 3's 64 ticks:
- Decrements its own counter (starts at 64, so ticks run with values 63
  down to 0).
- Repeatedly draws `idx = rand() % 16384` and inspects `grid[idx]`: a
  nonzero-and-below-16 value gets zeroed (a "success" — decaying that
  cell), a value ≥16 gets masked to its low nibble (also a success), and
  an already-zero cell is a wasted draw that just retries. Each tick
  repeats until **exactly 160 successes** land.
- Since successes remove grid occupancy over time, later ticks have fewer
  non-empty cells left to find, needing more retries — this is the exact
  mechanism behind a steadily *ramping* per-tick call count (286 calls on
  tick 1, climbing to 608 by tick 64 in the validated capture), unlike
  Earthquake's bell curve.
- The final tick (counter reaches 0) applies damage —
  `apply_elemental_multiplier(4, 5, target_idx, attacker_idx, 500)`,
  confirming Charm Arrow's already-documented parameters exactly
  (element 5/Resurrection, base power 500 — the ROM value, not the
  external reference's 400) — again no RNG in the damage step itself.

**Validated bit-for-bit**: the user provided `CharmArrow.State`, one frame
before case 3's first `rand()` call. Reading the grid directly from the
live savestate and simulating the exact algorithm above against it
reproduced the **real per-tick call count for all 64 ticks exactly** (0
mismatches) — total 24436 calls for the core 64-tick phase, matching a
live capture precisely. `FUN_80105858`, the state Charm Arrow hands off
to right after, is confirmed to be pure cast-teardown (`heap_free` on the
per-cast context, nothing else) — everything from there on is genuinely
unrelated battle flow, not part of the spell.

**The "tail" following the cast, fully explained (not just excluded)**:
initially measured as a vague "~12-16 calls", the user correctly flagged
that as suspicious — a fixed per-spell cost shouldn't vary. Breaking it
down frame-by-frame across several seeds found it isn't one thing:
- A **fixed 10-call block** (pattern `4, 3, 2, 1`, byte-identical across
  every seed tested) — this is `battle_select_enemy_target` running
  repeatedly: it costs exactly one `rand()` call per still-eligible
  combatant in a single roll, and each of the 4 non-caster combatants in
  this battle was set to Defend (`ActionType==1`, no RNG at all), so they
  resolve near-instantly and drop out of the eligible pool one by one —
  4 eligible on the first post-cast roll, then 3, then 2, then 1. Being
  purely a function of party composition, not RNG values, it's identical
  every time.
- A **genuinely variable remainder** (2-6 calls in the tested seeds) —
  the final roll (the "1") picks whoever acts next, and *who wins* really
  does depend on the RNG stream, which Charm Arrow's own ~24,000+ calls
  have thoroughly scrambled by seed. A different seed can hand that last
  slot to a different action entirely, so what's captured here is just
  the first few setup calls of whatever that turns out to be, cut short
  by the settle-detector — not a stable "tail" at all.

Either way, none of this is Charm Arrow's own cost, so it's correctly
excluded from the simulator regardless of which part is fixed vs.
variable.

**Broader validation**: injected 20 more seeds directly into the same
savestate. 16 settled cleanly within the capture window, and every one
matched the simulator's prediction on the core 64-tick phase exactly (0
discrepancy) — the 12-16 call difference in each case is the mixed
fixed+variable post-cast activity described above, not simulator error.
The other 4 simply didn't settle within the frame cap, meaning whatever
action won that final roll was substantial enough to keep running past
the capture window (same contamination pattern as Earthquake's Ain
Gide's Attack, not a simulator flaw).

The validated simulator is `simulateCharmArrow` in `lib/Magic.lua`, with
the confirmed initial grid template embedded alongside it in
`lib/CharmArrowGrid.lua` (a fixed deterministic template, not derived from
the RNG stream — the same for every Charm Arrow cast).

### Flaming Arrow: 20 respawning particles, randomized velocity, and a stale-memory gotcha (CONFIRMED 2026-09-05)

Traced next, following the same process as Earthquake and Charm Arrow. The
active handler (`spell_flamingarrow_tick_state_machine`, renamed from
`FUN_800fed6c`, `0x800fed6c`) uses a **third distinct VFX mechanic** — 20
discrete "arrow" particles (like Earthquake's 20, but behaving
differently), all starting inactive.

Same phase-switch architecture (a counter at `DAT_8017a030[0x2e]`), but
only phase 1 touches RNG. Phases run 64/96/74/60 ticks (0/1/2/3) — 294
ticks total, ~4.9 seconds at 60fps NTSC. Phase 1 is a fixed **96 ticks**
(`0x60`) — every tick, any currently-inactive particle is respawned via
`spell_flamingarrow_spawn_particle` (renamed from `FUN_80123b68`,
`0x80123b68`, 4 `rand()` calls each: a random spawn position via the same
"point on a sphere" nested-circle technique as Earthquake's 2D version,
a random **velocity scale** factor `(rand()%64)+128` — unlike Earthquake,
where velocity is a fixed constant, Flaming Arrow's is genuinely
randomized — and a random `rand()%100` lifetime). Position updates
deterministically after that (confirmed no RNG in the render/update
function, `FUN_8012424c`). A particle despawns on **either** of two
independent conditions, both genuinely exercised in live data (confirmed
via a full 20-particle dump at several checkpoint ticks): lifetime
dropping below 1, or its `trail_x` field (arithmetic-shifted right 12
bits) dropping below magnitude 5. On the 96th tick specifically, the
spawn step still runs (still costs RNG) but the phase then immediately
force-deactivates every particle regardless of state — no decay step
runs that tick.

`SquareRoot0` (`0x8014efe4`), used by the spawn function, is a standard
PSX SDK library routine (PSX GTE hardware leading-zero-count instructions
plus a 192-entry `int16` lookup table at `0x8017242c`) — not part of the
spell logic, just called by it. Its exact bit-manipulation algorithm was
extracted and replicated bit-for-bit in Python/Lua.

**A subtle bug that cost real debugging time**: `spell_flamingarrow_spawn_particle`
only ever writes `trail_x = trail_x & 0xfff | (new_high_bits << 12)` —
preserving whatever was already in the field's low 12 bits rather than
zeroing them. Since the despawn check discards those bits (`>>12`), this
is invisible for many ticks, but the residue still accumulates through
every `trail_x += velocity` addition and can eventually shift *which*
tick a threshold-crossing despawn happens on — which then cascades (a
respawn draws 4 new `rand()` calls, shifting the entire subsequent RNG
stream). A raw pre-cast memory dump of `FlamingArrow.State` found 17 of
the 20 particle slots share a common zeroed template, but 3 (indices
17-19) carry distinct nonzero garbage left over from the pool's prior
use — a fixed, RNG-independent property of this savestate (analogous to
Charm Arrow's baked grid), now baked into the simulator as
`RESIDUAL_LOW12`.

A second, unrelated bug also needed fixing: C's `/` truncates toward
zero for negative operands, while Python's `//` floors toward -∞ —
already known from Earthquake's decay check, but it resurfaces here in
`trail_x`'s initial `(iVar5*5)/6` computation and needed the same
`c_div` treatment.

**Validated bit-for-bit**: the user provided `FlamingArrow.State`, one
frame before phase 1's first `rand()` call, and reported the first frame
alone advances RNG 80 times (exactly 20 particles × 4 calls — all 20
spawn simultaneously on tick 1, confirmed). A 150-frame live capture
settled at tick 95 (512 total calls). Simulating the full mechanism
above against the captured seed reproduced the **real per-tick call
count for all 95 active ticks exactly** (0 mismatches), including full
per-particle `active`/`lifetime`/`trail_x` state matching exactly at
several spot-checked ticks (1, 20, 23).

**Broader validation**: injected 20 more seeds directly into the same
savestate (following the same LCG-step-counting methodology as
Earthquake/Charm Arrow). All 20 settled cleanly and matched the
simulator's predicted total exactly (0 discrepancies) — confirming the
96-tick phase-1 bound (not the 95 ticks that happened to be sufficient
for the original seed) is the correct general model.

The validated simulator is `simulateFlamingArrow` in `lib/Magic.lua` (with
`SquareRoot0`'s table embedded as a constant), with tests in
`tests/test_Magic.lua`.

## Open questions / not yet done

- Full Ghidra struct definitions for the battle-state struct, the
  combatant stat record, and the equipment/class record — everything above
  is still raw pointer-offset arithmetic.
- Turn order / speed-based initiative calculation — **solved**, see
  [Turn_Order.md](./Turn_Order.md).
- AI/enemy action selection — not yet located.
- `+0x26` (SKL) and `+0x2e` (LUK) confirmed exactly via the project's own
  live Combat viewer module (`modules/RNG/submodules/Combat`) —
  cross-checked against `lib/Characters/Characters.lua`'s independent
  save-data stat reader for two characters and got an exact match on both
  stats (and on SPD/AGL again). Notably `+0x30` (**ATK**, not PWR — see
  correction below) and `+0x32` (DEF) did **not** match the same
  characters' persistent base PWR/DEF stats exactly — turns out `+0x30` is
  a genuinely distinct stat (ATK = PWR + weapon attack bonus), not just an
  equipment-inclusive PWR as first assumed. Worth keeping in mind when
  cross-checking any other stat this way: an exact match confirms identity,
  a close-but-not-exact match doesn't necessarily mean the wrong offset.
- Whether `g_abWeaponTypeToElement`'s 5 element ids correspond to specific
  named elements — not yet cross-referenced against any string table or
  the rune system. (The *magic*-side element ids are now known — `0`
  Fire, `2` Earth, `3` Lightning, `4` Wind, `5` Resurrection, `7` Dark,
  `1` presumably Water — but `g_abWeaponTypeToElement`'s ids `0-4` haven't
  been confirmed to line up with these same numbers rather than a
  separate weapon-only numbering.)
- `0x80116078`'s `a0=4` still doesn't match its confirmed identity (Hell,
  which should be level 3 by spell order) — behavior confirms the spell,
  but the numbering discrepancy itself is unexplained.
- The external `Suikoden-RNG-lib` reference has at least one confirmed
  inaccuracy (Charm Arrow: it lists 400 dmg, the ROM's real value is
  500, confirmed via live gameplay math) — worth treating its damage
  numbers as a strong lead, not ground truth, until cross-checked.
