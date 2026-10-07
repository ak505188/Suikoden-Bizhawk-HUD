# Battle Damage Formula

Covers the actual combat-resolution *code* (damage formula, critical hits,
elemental affinity) as reverse-engineered from `main.exe` in Ghidra. This
complements [Battles_and_Encounters.md](./Battles_and_Encounters.md), which
documents the encounter/enemy-group *memory layout* found via live-memory-
diffing from the Lua HUD side.

## Where the code lives

The battle engine is not in an overlay like most per-room/minigame logic
(see the Ghidra RE workflow notes) — `data/05_batle/battle1.8`/`battle2.8`
are background/music asset packs (an SPU ADPCM audio block, no code). The
real battle engine is permanently resident in `main.exe`, located via a
retail debug string the compiler didn't strip (`printf("ZOKUSEI %d AISYO
%d\n", ...)` — "ZOKUSEI" = element, "AISYO" = compatibility) even though
player-facing text elsewhere uses a custom charmap invisible to a plain
string search.

## The central battle-state struct

`DAT_8017be3c` (Ghidra type `BattleState *`, global name `g_pBattleState`)
is a pointer to the main battle-state struct in RAM (590 cross-references
throughout `main.exe`). Known offsets:

- **`+0x04`** — `dwRoundNumber`: The battle's round counter — e.g.
  Zombie Dragon's AI checks this for "guaranteed Fire Breath on round
  1."
- **`+0x08`** — `dwCurrentActorIdx`: The combatant index whose turn is
  currently executing. A mirror of `+0x3420` (`g_nPendingIndex`),
  copied over on the tick right after the turn-order roll resolves, so
  the two fields read as equal almost all the time in a live viewer.
- **`+0x1C`** — `player_count`: Boundary between "party member" and
  "enemy" indices into the combatant array below.
- **`+0x20`** — `max_enemy_idx`
- **`+0x2c`** — `dwUsesAvailableCounter`: The count of currently valid
  attack targets (i.e. living/targetable enemies) this round — despite
  the generic-sounding name, this is not a spell/item "uses" pool. It
  bounds a per-round enemy candidate list cached in the menu context
  struct (`DAT_80179fe8+0x38[]`, one combatant index per entry) that
  both the manual target-cursor screen and Free Will's auto-targeting
  read identically; a target-type-`1` Rune spell (AOE, no explicit
  target) is blocked outright when this is `0`. Not the per-combatant
  `+0x2c` MGC stat — this is a fixed base-struct offset. Where the
  candidate list itself gets built each round is not yet located.
- **`+0x30`** — sync-signal array: Base-struct-relative array, gated on
  "am I the current actor" — plausibly Unite-attack pairing.
- **`+0x34`** — `SyncSignals+4`: A general "force a full round-state
  resync now" signal — checked by
  `battle_process_round_end_status_and_formation`'s phase-4→5 cleanup,
  and set both by Queen Ant's round-3 end-of-round callback and by the
  scripted Ted-vs-Queen-Ant forced-turn mechanism (see below).
- **`+0x50`** — `enemy_data[]`: Stride `0x8c`, raw 1-indexed actor
  numbers (same convention as the combatant array below). `[i]+0x0` =
  **Id** — indexes `attack_data_table` for elemental compatibility;
  for party members this exact byte matches each character's roster
  `Id` (`lib/Characters/Addresses.lua`, e.g. Hero=8, Viktor=35) — a
  per-character/per-monster identity value, not a species/type
  category. `[i]+0x5` = a **busy/reaction mutex byte**:
  `0`=idle-or-dead (both read the same — don't use this to filter dead
  combatants), `1`=busy performing an action, `8`=being hit/targeted
  (stays `8` even on a miss), `9`=hit by a Unite attack. It is a
  genuine mutex maintained by dedicated opcodes in the per-combatant
  animation-script interpreter (`play_attack_animation`,
  `0x800e3820`, running a 45-entry opcode table `PTR_LAB_8016babc`):
  `anim_op_set_busy_flags` (opcode 15, `0x800e3eac`, ORs a
  script-supplied mask into this byte, targeting self or the attack's
  target), `anim_op_clear_busy_flags` (opcode 16, AND-NOT),
  `anim_op_wait_until_busy_flags_clear` (opcode 44, stalls the script
  until the bits clear). The ordinary Attack script sets bit `1` on
  the attacker and bit `8` on the target. A 16-bit field at
  `enemy_data+0x40` (opcodes ~23–26) is a second, separate flag system
  used for effect/counter gating.
- **`+0xb40`** — combatant stat array: Stride `0x54`; combined
  party+enemy array, addressed by **raw 1-indexed actor numbers** —
  actor 1 = first party member, actor `player_count+1` = first enemy
  (`+0xb94` is the same array pre-shifted by one stride, a shortcut
  for 0-indexed callers; both conventions appear in the codebase).
  Field offsets: `+0x10`/`+0x12` = max/current HP, `+0x26` = **SKL**
  (hit chance, crit chance), `+0x2a` = **AGL/SPD** (turn-order speed
  stat, see [Turn_Order.md](./Turn_Order.md)), `+0x2c` = **MGC**,
  `+0x2e` = **LUK** (crit chance), `+0x30` = **ATK** (PWR + equipped
  weapon's attack bonus — a distinct stat from base PWR), `+0x32` = a
  DEF-like stat (also likely equipment-inclusive), `+0x44` =
  formation-position byte, `+0x45` = alive/valid flag (`0`=valid),
  `+0x46`–`+0x49` = action-selection fields (own section below),
  `+0x4a` = status-effect bitmask (own section below). Enemy-side
  records in some encounters (e.g. Queen Ant's fight) use a distinct
  layout for some fields — e.g. enemy MGC there is read at `+0x1c`,
  not `+0x2c`.
- **`+0xF84`** — `class_ptrs`: Per-party-member pointer table (stride
  `0xc`, same 1-indexed convention); `[i]+0x1c` reaches the
  character's own **persistent Stats struct** (Ghidra type
  `PersistentStats`) — the same struct
  `lib/Characters/Characters.lua`/`lib/Party.lua` already read from
  save data, not a separate battle-only "equip record."
- **`+0x1258`** — `RngCallbackTable` pointer: A STATIC `main.exe`
  table at `0x8016b680` (not per-battle heap data). Known slots:
  `[0]`=`rand()`, `[1]`=`play_attack_animation`, `[3]`=`calc_damage`,
  `[4]`=`apply_hp_damage_display`, `[7]`=sub-animation-slot-finder
  (used by opcodes 24/32), `+0x158`=slot
  `86`=`calc_rune_element_attack_damage` (see below).
  Overlay/monster-script code reaches `main.exe` functions indirectly
  through this table.
- **`+0x1330`/`+0x1334`** — scripted-turn-override hook: When armed
  (`+0x1330=1`), `+0x1334` holds a function pointer (into a monster's
  own overlay) invoked as a per-round callback. Used by scripted/story
  encounters for two distinct purposes: forcing a battle to end after
  a fixed round count (Queen Ant, Mt. Seifu), and forcing a specific
  character's specific action with no player input (the
  Ted-vs-Queen-Ant scripted fight). See "Queen Ant" sections below.
- **`+0x1344`** — `attack_data_table`: Pointer table indexed by the
  combatant's `Id` (`*4`); each entry is a `MonsterRecord` (own
  section below).
- **`+0x3420`** — `g_nPendingIndex`: The next actor index to run its
  turn; normally set by the weighted-RNG turn-order roll, but can be
  forced directly by a scripted-turn override.
- **`+0x30a0`** — per-status duration-slot table: `BattleState +
  status_id*0x10 + combatant_idx*0x80 + 0x30a0`: per-combatant
  per-status record (active flag, a second flag, a counter, and a
  computed value from `FUN_800e1e3c`, likely a status
  icon/animation-loop handle). Used by the 6 status ids that don't
  have their own dedicated countdown byte (see status-effects
  section).

`CombatantRec`/`EnemyData`/`ClassPtrEntry`/`MonsterRecord` are Ghidra struct
types with known sizes (`CombatantRec=0x54`, `EnemyData=0x8c`,
`ClassPtrEntry=0xc`), declared as single array elements at their correct
starting offsets — index further via pointer arithmetic using each struct's
own size rather than array subscripting, since the real element counts vary
by battle. Several regions are known to hold fields not yet individually
pinned down (most of the `+0xdc`–`+0xb40` and `+0xb94`–`+0x1258` gaps,
`+0x1268`–`+0x1344`, `+0x1348`–`+0x3420`) and are left as `undefined1[]`
padding rather than guessed at.

## `calc_hit_chance` (`0x800f7d5c`)

`calc_hit_chance(attacker_idx, target_idx) -> bool`:

```
chance = attacker.SKL(+0x26) - (target.SKL(+0x26) - 80), clamped to [60, 99] percent
if (attacker is a party member and attacker has status "Bucket" (combatant_rec+0x4a bit 0x10))
   or (attacker is an enemy and target's Rune.Id (persistent Stats +0x4c) == 18, Hazy Rune):
    chance = chance / 2           -- integer division; chance >= 60 here, so it floors
return (rand() % 100) < chance   -- compiled as `-(uint)(cond)`, so true reads back as -1, not 1
```

Both sides use the same stat (SKL), so it doubles as both accuracy and
evasion. The two halving branches are asymmetric by design: a party
attacker's own Bucket status (an offensive accuracy debuff) halves their
own chance, while an enemy attacker's chance is halved by the *target's*
own Hazy Rune (a defensive evasion buff) — not the enemy's own equipment.

### On a miss or a hit: dodge and counter

**Corrected 2026-09-25.** Earlier versions of this section read the `+0x56`
byte both counter checks use as a `PersistentStats` "can counter" flag, and
concluded that the opcode-26 script flag decides who can be countered. Both
were wrong. `ClassPtrs[idx]+0x04` points into main.exe's static weapon
table (near `DAT_80165890`; live values `0x80165b30`, `0x80166370`, ...,
with the weapon's charmap name right after `+0x58`), not at
`PersistentStats` (`ClassPtrs[idx]+0x00 → +0x1c`, which holds unrelated
values at `+0x56`). `+0x56` of the weapon record is its **range class**,
the same byte the [target-validity rule](#free-will-automatic-action-selection)
reads:

| Value | Range | Examples (live) |
|---|---|---|
| 1 | Short | Flik |
| 2 | Long | Kasumi, Krin, Stallion, Tengaar |
| 3 | Medium | McDohl |

Suikoden-RNG-lib's `Characters.js` already records this as `range`. It also
records the opcode-26 result below as `counterEligible`, which turned out to
be redundant with range (see below).

Both physical-attack functions resolve a miss, each differently:

- **`battle_execute_player_attack`** (`0x800f4e64`, despite the name, an
  *enemy's* basic Attack; the fallback when the enemy's AI returns `-1`,
  see [AI/enemy move selection](#aienemy-move-selection)) returns `0`
  (wait, retry next tick) before any roll if the target's busy byte
  (`EnemyData+5`) is nonzero. On a failed `calc_hit_chance` it calls
  **`check_dodge_counter`** (`0x800f78e4`, its only caller), which needs:
  1. attacker index `> dwPartyCount + 1`: an off-by-one, so the first
     enemy slot can never be countered;
  2. the attacker's species `MonsterRecord+0x26` bit `0`;
  3. the defender's range byte bit `0` (Short and Medium pass, Long fails).

  Then Defending (`ActionType == 1`, the queued action this round) or
  Counter Rune (`Rune.Id == 16`) guarantees the counter with no RNG;
  otherwise `rand() & 1`. A success is a real counter-attack chained
  through `counter_attack_reprisal` → `counter_attack_reprisal_continue` →
  `counter_attack_apply_damage`, an ordinary `calc_damage` hit on the
  attacker. If it fails, the attacker's own species bit `3` decides: clear
  is a plain miss (`ordinary_miss_continue`), set treats the miss as a hit.
  Every hit then goes through the [cover check](#cover-mechanic-battle_check_counter_attack-find_cover_target)
  (no RNG). Enemies never roll a crit.

  **First-slot rule live-confirmed 2026-09-25**
  (`scripts/VerifyFirstEnemyCounter.lua`, `Seifu6Ant.State`, 30 seeds,
  every party member Defending): the first Soldier Ant missed 7 times and
  was never countered, while slots 2-6 missed 37 times and were countered
  every time. That script meant to equip Hazy for more misses but wrote
  the rune id into the weapon record (`+0x04` pointer, `+0x4c`), so Hazy
  never applied; the result doesn't depend on it.
- **`battle_execute_enemy_attack`** (`0x800f491c`, despite the name, the
  *party's* basic Attack). If the target species has bit `15`, the
  compiled `(flags & 0x8000) || calc_hit_chance() == 0` short-circuits:
  no hit roll, no `rand()`, straight into the miss branch. In the miss
  branch, checked in order:
  1. target species bit `1` and attacker range byte `!= 2` (not Long):
     arms `counter_attack_reprisal`, the monster counters. No `rand()`,
     no slot rule.
  2. target species bit `2`: plain miss (`ordinary_miss_continue`).
  3. neither: falls through to `battle_check_crit_and_branch`, which rolls
     a crit and applies damage with no second hit roll. **The failed roll
     is thrown away and the attack lands.**

  `counter_attack_reprisal` also does nothing unless the attacker's
  `enemy_data+0x40` bit `0` is set, armed by `anim_op_set_effect_flags`
  (opcode `26`, `0x800e4fd8`, 6 bytes `[26][target:u16][mask:u16]`,
  `target == 1` arms the enemy instead of the caster) with mask `0x1` in
  the attacker's own slot-1 basic-Attack script (Suikoden-RNG-lib's
  `counterEligible`). The disc scan (`disc_extract/`, validated 10/10
  against live reads) found **60 characters arming on self** and **18 whose
  slot 1 doesn't**: Cleo, Eileen, Fuma, Juppo, Kage, Kirkis, Krin, Lorelai,
  Meg, Odessa, Quincy, Rubi, Sarah, Stallion, Sydonia, Sylvina, Ted,
  Tengaar. (Their opcode-26 `target=1` calls are in another slot, e.g.
  Kage's and Stallion's slot 9.)

  **Corrected 2026-09-25: this flag is redundant, and the scan's reading of
  the 18 is probably wrong.**
  - All 18 are Long range, so the range check already stops any counter
    against them; `counterEligible` never changes an outcome.
  - Live, Stallion and Tengaar *do* end every attack with bit 0 set on
    themselves (flags `0x13`). Their `target=1` calls are most likely in the
    projectile script, which runs as a sub-actor whose anim target is the
    shooter, so "arms the enemy" really arms the shooter. That also has to
    be true for their plain misses to finish, since `ordinary_miss_continue`
    waits on the same bit (see
    [Continuation chains and death](#continuation-chains-and-death)).
  - All 18 have counter scripts (slots 3/5) that never finish in the
    walker, consistent with the game never letting them counter.

  So a monster counters a party member's miss if species bit `1` is set
  and the attacker's range isn't Long. Kasumi (Long) can't be countered
  even though her script arms the flag on herself. The earlier
  "reach-category hypothesis DISPROVEN" conclusion drawn from her was
  wrong: range is the gate.

  **Live-confirmed 2026-09-25** (`scripts/VerifyKasumiCounter.lua`,
  `KasumiMoraviaSoldiersCounterTest.State`, 30 seeds, every party member
  forced to Attack the same soldier with flags `0x0003`, SKL pinned to 1
  so the hit chance sits at its 60% floor):

  | Char | Range | Result over 30 attacks |
  |---|---|---|
  | McDohl | 3 | 12 misses, all 12 countered |
  | Flik | 1 | 12 misses, all 12 countered |
  | Kasumi | 2 | 0 misses (27 hits, 3 crits) |
  | Stallion | 2 | 0 misses (26 hits, 4 crits) |
  | Tengaar | 2 | 0 misses (27 hits, 3 crits) |

  The long-range characters never missed because bit `1` without bit `2`
  leaves them no plain-miss path. Flik was in the back row with a Short
  weapon, which the menu and Free Will never allow (Free Will picks Defend
  for him); forcing `ActionType = 0` by memory write still made him walk
  up and attack, so **the executor never checks row**. Krin died to enemy
  idx 10 before his turn in every run.

  Species bit `1` is set on 38 of 122 monsters (soldier/mercenary types
  plus Anji, Kanak, Leonardo, Sydonia, Varkas, Sonya Shulen, Ain Gide,
  Ninja Master); Sonya Shulen and Ain Gide were confirmed in gameplay by
  the user. Bit `15` is only on the two Neclord fights (`flags=0xc004`:
  `ve1.bin` Warrior's Village, lvl55 HP10000, AI `0x80013d18`; `ve3.bin`
  Neclord's Castle, lvl55 HP7500, AI `0x8001675c`): bit `2` without bit
  `1`, so every physical Attack on him is a plain miss.

Across `outputs/Bestiary.json`'s 124 records, what a party member's failed
hit roll becomes:

| Bits 1 / 2 | Count | Failed roll becomes |
|---|---|---|
| 2 only | 63 | plain miss |
| 1 only | 31 | counter, or a hit for Long range |
| 1 and 2 | 7 | counter, or a plain miss for Long range |
| neither | 23 | always a hit |

"1 and 2" is Bandit, Assassin, Holly Spirit, Veteran Soldier, Ninja,
Imperial Guards. "Neither" includes FurFur, BonBon, Wild Boar, Black Wild
Boar, Death Boar, Killer/Red Slime, Giant Snail/Slug, Ivy, Mad Ivy, Eagle
Man, Hawk Man, Slot Man, Clay Doll, Demon Sorcerer, Black Elemental, Queen
Ant, Crystal Core, Shell Venus and Golden Hydra: a party physical Attack
can't miss them (same fall-through line as the live-confirmed case, but
not watched live on one of these).

`rand()` calls per basic-Attack outcome:

| Attacker | Outcome | Calls |
|---|---|---|
| Party | hit or crit (incl. fall-through) | 2 |
| Party | counter or plain miss | 1 |
| Party | vs bit 15 (Neclord) | 0 |
| Enemy | hit (incl. bit-3 fall-through) | 1 |
| Enemy | counter via Defend / Counter Rune | 1 |
| Enemy | counter or miss after the coin flip | 2 |
| Enemy | target busy (waits a tick) | 0 |

**Attempted full-roster static resolution (2026-09-20): mechanism found,
but not a ROM-static path.** `battle_load_party_combatants` (`0x800debe8`)
resolves each live party member's `classData` pointer via
`GAMESTATE_BASE` (`0x801b8000`, confirmed as a compile-time-fixed constant
— its only write site, `0x800c9478`, loads the literal `0x801b8000`) +
`offset*4 + 0x1b9c`, the exact same chain `lib/Party.lua`'s
`getCharacterDataAddress` already uses (cross-confirmed: both read a u32
"pointer" at that computed address, then `+0x1c` for the `PersistentStats`
address). `classData+0x20` (read once resolved) is what
`battle_load_party_combatants` copies into `EnemyData+0x08`
(`pActionScriptTable`) — i.e. this is a **character-level property, not a
battle-only one**: it does not require an active battle to read, only the
character to be recruited and the game running (`GAMESTATE_BASE` is the
same 0x1d60-byte block that gets saved/loaded to the memory card wholesale
via `FUN_80129ca8`, and per-character recruitment flags live in the same
block at `0x1B9AF4`+, one byte per roster slot). However, the actual
**pointer values** stored in this array are populated by a "new
game"/recruit-time initializer this pass did not locate within a
reasonable search — meaning they're not derivable from `main.exe`'s own
static data without knowing that initializer's source table (if one
exists at all; it's equally possible these are computed addresses rather
than a copied template). **Practical implication for extending this
roster survey**: a single non-battle savestate (anywhere in-game, not
mid-fight) with as many of the ~108 characters recruited as possible would
let a script walk every known roster `Id`, resolve `classData` via the
formula above, read `classData+0x20`, and decode each character's
opcode-26 target — all without ever starting a battle. This is
substantially cheaper than needing one battle-savestate per party
composition (the originally-assumed "Option B"), but it's still a live
capture, not the fully static (Option A) result this pass aimed for.

## Action selection: `combatant_rec+0x46..+0x49`

Every combatant record carries a "what did this combatant queue up this
turn" block, driven by a real dispatch jump table
(`g_actionTypeDispatchTable`, `0x800c13ec`, 5 entries reading `+0x47`) — the
same field the project's Combat viewer displays as `ACT`:

- **`+0x46`** — `ActionTag`: `0` = no action queued/resolved yet, `1` =
  this turn's action is executing/executed.
- **`+0x47`** — **`ActionType`**: `0`=Attack, `1`=Defend, `2`=Rune,
  `3`=Item, `4`=Unite.
- **`+0x48`** — **`AbilitySlot`**: Selected Rune/Item/Unite menu-slot
  index; meaning depends on `ActionType`. Unused for Attack/Defend.
- **`+0x49`** — **`TargetIdx`**: Selected target's combatant index —
  one shared field for all five action types.

`ActionType`/`AbilitySlot`/`TargetIdx` all read `255` (`0xFF`) when a
combatant's action is uninitialized/cleared — a fill pattern, not a real
`ActionType==255` enum value, and distinct from `ActionTag`'s own `0`/`1`
flag.

Three resolver functions turn `AbilitySlot` into an actual spell/item/Unite
id and validate `TargetIdx` (Attack goes straight to
`battle_execute_enemy_attack`, genuinely shared between both party and
enemy despite the name, see
[Turn_Order.md](./Turn_Order.md#how-a-turn-actually-starts-battle_dispatch_current_actor_action)
— and Defend to `battle_resolve_defend_action`, `0x800f40b8`):

- **`battle_select_special_ability`** (`0x800f5500`, Rune): resolves
  `AbilitySlot` through a per-character ability-set table (keyed by the
  character's persistent-stats `Rune.Id`, `+0x4c`) into a spell id. Slot `4`
  (the character's Level-4 elemental spell) is special-cased — see Magic
  Unite below. A second, differently-tabled internal branch (`DAT_8016a630`)
  handles characters with a nonzero ability-set flag — see below.
- **`battle_try_special_attack`** (`0x800f5050`, Item): resolves
  `AbilitySlot` by indexing the attacker's inventory array
  (`equip_ptr+0x1c+0x20`, 4 bytes/entry: `ushort` item id + a use-count
  byte). Decrements the use-count on cast; at `0` calls
  `FUN_800ca408(class_ptr, slot_idx)` (removes the now-empty slot).
  Waits for every combatant to be idle first. Timing:
  [Item turns](./Turn_Order.md#item-turns).
- **`battle_select_unite_attack`** (`0x800f5790`, Unite): resolves
  `AbilitySlot` through its own table (`DAT_8016d18c`) — the manually
  selected physical Unite Attack. There is no "wait for the partner" sync:
  the participant who wins the turn roll first runs the whole Unite, and the
  partner loop only *fails* it if a participant is invalid (corrected
  2026-09-27; see [Physical Unite attacks](#physical-unite-attacks)).

All three resolvers re-validate `TargetIdx` via `check_combatant_valid_target`
and store a pointer from the resolved definition into their own base-struct
slot (`+0x14` Rune, `+0x10` Item, `+0x18` Unite) — an animation/effect
script pointer, one slot per action type.

### Physical Unite attacks

Traced 2026-09-27 from `main.exe` decompiles. Handler and helper names are
the ones given in Ghidra that day. **Live-confirmed the same day** on
Talisman Attack (`scripts/VerifyTalismanUnite.lua`,
`VarkasSydoniaUniteTest.State`, 10 rounds over 6 seeds):

- The first participant to reach its turn runs the Unite. It waits, with
  no RNG, until every combatant is idle. Both participants go to
  ActionTag `1` on the same frame the Unite starts (frame S).
- Both animations have fixed timing from S. Pahn's impact bit is set at
  S+66 and Gremio's at S+74, whoever starts. Damage lands the frame after
  the **initiator's** impact: S+75 when Gremio starts (2 seeds), S+67 when
  Pahn starts (6 seeds, AGL pinned to 60 vs 1). The partner's impact never
  triggers damage, even when it comes first.
- The damage frame has exactly 2 `rand()` calls. In all 8 rounds the
  damage matched (Pahn roll + Gremio roll) × 2, e.g. 104 = (31+21)×2. The
  target's busy byte is `9` while it reacts, for 37 frames (Gremio's slot
  15 reaction).
- S is the tick after the resolver first finds everyone idle. The resolver
  polls, with no RNG, from the dispatch tick until then.
- The handler ends at S+136, the tick after Pahn's done bit `0x4` (S+135;
  Gremio's is at S+130). The turn loop resumes at once: next roll at
  S+137, next current actor at S+138. That's while both participants
  are still busy walking back (return script `0x8016d214`, started when
  each one's `0x4` is seen). Busy clears at S+176 (Gremio) and S+188
  (Pahn). None of these offsets depend on who starts.
- The static walker (`AttackTimingWalker.py --party pan 9`, `gre 9`)
  predicts the impacts (66 / 74) and done bits (135 / 130) exactly.
- A dead partner, whether killed by the boss mid-round or by writing HP
  `0` and letting `party_member_death` run: the initiator's turn becomes
  the Defend fallback. That means ActionTag `1`, roll gate `0`, and no RNG.
  `ActionType` stays `4` until the round-end reset.
- **No Defend damage reduction for that character.** In all 6 dead-partner
  runs, Pahn took the full, unhalved `calc_damage` hit. In the same log,
  real Defenders' hits matched the halved formula. The halving tests
  `ActionType == 1`, which a failed Unite never sets, so this holds for the
  whole round. Only hits before Pahn's failed turn were observed.

#### Unite menu eligibility: `compute_unite_eligible_slots` (`0x800ef104`)

`battle_menu_compute_command_availability` enables the Unite command only
when this function finds at least one Unite. For each of the 32 Unite
definitions that include the commanded character's roster Id, **every**
required Id, the character's own included, must match a party member
that passes all of these:

- **At or after the commanded character in command order.** The search
  starts at the menu's current position (`DAT_80179fe8+0x10`) and walks
  the per-position combatant list (`DAT_80179fe8+0x1c + pos*4`).
  User-confirmed: only the participant earliest in command order can
  select a Unite. If that participant picks anything else, the later
  participants can't select that Unite this round.
- **Menu flag `DAT_80179fe8+0xb4 + pos*4 == 1`.** Its meaning isn't
  traced (likely "hasn't had a command taken yet").
- **Valid combatant** (`check_combatant_valid_target`: not dead or fled).
- **`+0x4a & 0x61 == 0`**: not Poisoned (`0x1`, id0), asleep (`0x20`,
  id5) or Unbalanced (`0x40`, id7).

So any of those three statuses on any participant, the commanded
character included, removes that Unite. An Unbalanced character never
has the Unite command (user-confirmed). HP isn't checked. The eligible
slots go to `DAT_80179fe8+0x80`, the count to `+0xa8`. The Unbalanced
case and the command-order rule are user-confirmed. The `+0xb4` flag is
decompile only; the command-order rule alone explains the user's
observations, so its role hasn't been isolated.

The resolver below doesn't recheck status, only validity. A participant
who gets one of those statuses after the menu still takes part. Only
death or fleeing makes the Unite fail.

**Resolver** (`battle_select_unite_attack`, `0x800f5790`), run on the
initiator's turn. `check_combatant_valid_target` returns `0` for a valid
combatant, `-1` otherwise.

1. Not every combatant idle (`battle_check_all_combatants_idle`): return
   `0`, poll again next tick. No RNG.
2. Any party member with `ActionType==4` and the same `AbilitySlot` (the
   initiator included) invalid, meaning dead, fled or HP minus pending
   damage below 0: return `-1`.
3. Def `+0x16 & 3 == 1` (all enemies) and `dwUsesAvailableCounter < 1`:
   `-1`. `& 3 == 3` (one enemy) with an invalid target: retarget to the
   first enemy in combatant order that is valid and has HP minus pending
   damage > 0 (`battle_find_first_ready_enemy`, `0x800f6344`), `-1` if
   none. That's the same pick a basic Attack makes (per the user), except
   the Attack accepts HP minus pending = 0.
4. Otherwise store the handler `DAT_8016d2d0[def+0x19]` in
   `g_pBattleState+0x18` and return `1`.

On `-1` the dispatcher runs `battle_resolve_defend_action`: the initiator
loses the turn (ActionTag `1`, roll gate `0`). The partners keep
`ActionType 4`, so each fails the same way on its own turn: if any
participant is dead, the Unite fails for everyone (per the user).
On `1` the dispatcher state `LAB_800f4550` calls the handler
with the current actor every tick until it returns something other than
`-1`. It then sets `+0x30 = 1` and goes back to `battle_advance_turn`
without resetting `nRollGateCountdown`. **The turn loop is paused for the
whole Unite**, and nothing else starts.

**Every handler** (24 of them, `unite_<name>_stage1` + later stages) first
calls `unite_gather_participants` (`0x800f91c0`). That sets ActionTag `1`
on every participant, so the partners' turns are used up. It lists the
participants in the def's **Id order** (p0, p1, ... below), not
initiator-first. It also copies the initiator's target into theirs and
clears everyone's `+0x40` effect flags. The handlers then start each
participant's own script (their table slots 9-16), and poll `+0x40` bits
the scripts set with opcode 26: `0x2` = impact, `0x10` = cue, `0x4` =
participant done. The Unite ends when every participant has set `0x4`.

**Damage.** Only two helpers call `calc_damage`, and neither rolls hit,
crit, counter or cover:

- `unite_damage_on_actor_impact(gate, n, m, p[])` (`0x800f9488`): when
  `gate`'s `+0x40 & 0x2` is set, the gate's target takes
  `sum(calc_damage(p[i], target)) * m / 10`.
- `unite_damage_target(target, n, m, p[])` (`0x800f95e8`): the same sum,
  applied when the caller decides. Skips a target with `+0x45 != 0`.

So one damage event costs one `calc_damage` roll per participant, made in
p0, p1, ... order, and uses each participant's own ATK. `m / 10` is the
multiplier below. p0, p1, ... is the def's Id list at `+0x1a`, read from
`main.exe` (defs at `0x8016cd0c`, stride `0x24`). Names are the def's own
charmap string at `+0x0`, as the game shows it.

| Slots | Name | Participants (p0, p1, ...) | × | Fires on |
|---|---|---|---|---|
| 1 | Talisman attack | Pahn, Gremio | 2 | initiator impact |
| 2 | Fisherman attack | Tai Ho, Yam Koo | 3 | initiator impact |
| 3 | Wild arrow attack | Kirkis, Sylvina | 1 | p1 impact, all |
| 20 | Wild arrow attack | Kirkis, Rubi | 1 | p1 impact, all |
| 21 | Wild arrow attack | Kirkis, Stallion | 1 | p1 impact, all |
| 4 | Elf attack | Kirkis, Stallion, Sylvina | 2 | initiator impact |
| 5 | Pirate attack | Anji, Kanak, Leonardo | 2 | p0 impact |
| 6, 22-25 | Blacksmith attack | the four smiths | 3 | p3 impact |
| 7 | Bumpy attack | Krin, Humphrey | 1.5 | p0 cue (`0x10`) |
| 8 | Pretty boy attack | Flik, Alen, Grenseal | 3 | p2 impact |
| 9 | Pretty girl attack | Camille, Tengaar, Kasumi | 2.5 | p1 impact |
| 10 | Beauty attack | Cleo, Eileen, Valeria | 0.4 | timer, all |
| 26 | Beauty attack | Cleo, Eileen, Sonya | 0.4 | timer, all |
| 11 | Flash attack | Liukan, Fukien, Kai | 2 | timer |
| 12 | Kobold attack | Kuromimi, Gon | 2 | initiator impact |
| 13 | Dragon Knight attack | Futch, Milia | 2 | initiator impact |
| 14 | Fatal attack | Gen, Kamandol | 2 | p1 impact |
| 15 | Trick attack | Meg, Juppo | 1 | sweep, all |
| 16 | Warriors attack | Tengaar, Hix | 2 | timer |
| 17 | Couple attack | Eileen, Lepant | 2 | p1 impact |
| 18 | Bandit attack | Varkas, Sydonia | 2.5 | target's impact |
| 19 | Carpenter attack | Gen, Sansuke | 2 | initiator impact |
| 27 | Kobold +1 attack | Kuromimi, Fu Su Lu, Gon | 3 | p1 impact |
| 28 | Beat'em up attack | Pahn, Ronnie | 3 | p1 impact |
| 29 | Ninja attack | Kasumi, Fuma, Kage | 2 | p1 impact |
| 30 | Martial arts attack | Eikei, Pahn, Morgan | 0.5 | timer, all |
| 31 | Lepant family attack | Lepant, Eileen, Sheena | 2 | target's cue |
| 32 | Master pupil attack | Hero, Kai | 1 | each impact, each |

Notes on the "Fires on" column:

- **initiator impact**: gated on the current actor's own `0x2`, so the
  timing depends on which participant won the turn roll.
- **all**: one damage event per living enemy, in enemy index order,
  except Trick (15). Trick hits enemies as a sweep passes their screen X
  position (`+0x68`), so its order is positional.
- **timer**: fixed tick counts inside the handler. Flash: phase 2, tick 32.
  Warriors: phase 2, tick 32 of stage 3. Beauty: after phase 2 (tick 32).
  Martial Arts: handler tick `0x8c`.
- **Master Pupil (32)**: each participant, on its `0x10` cue, takes the
  next enemy that was valid and idle at the start. On its impact that enemy
  takes the full 2-person sum ×1. Each enemy is hit once.
- A handler may fire more than once if a script sets the impact bit more
  than once. The static scripts weren't checked for that.

**Other RNG inside a Unite.** The handlers themselves call `rand()` in only
one place, Beauty's VFX. The rest comes from script opcode 40
(`anim_op_roll_status_effect_chance`). That opcode always rolls once unless
the owner is a party member wearing the Turtle Rune (Rune.Id 25), which
skips both the roll and the status.

- **Unbalanced (status 7, 100%) on the participant itself**: Pahn's slot
  10 in Beat'Em'Up (28) and Kasumi's slot 10 in Pretty Girl (9). No other
  participant's Unite script has opcode 40. For a party member arg 100
  always lands; the only exceptions are a Turtle Rune (no roll) or being
  Unbalanced already (roll, no new status). The walker puts the roll at
  f394 of Pahn's script (impact f60) and f191 of Kasumi's (impact f56).
- **Beauty (10, 26)**: every living enemy plays Cleo's slot 15 as its hit
  reaction, which rolls Sleep (status 5, arg 30). For an enemy the check
  is inverted (applied when `roll % 100 >= 30`), so Sleep lands **70%**
  of the time. That's one roll per enemy.
- **Beauty VFX**: the setup spawns 30 particles, each costing
  `rand() % 32` + `rand() % 64` + `vfx_randomize_sphere_particle` (3
  `rand()`), for **150 fixed calls**. For the next 128 ticks each
  particle re-randomises (3 more calls) whenever its sprite animation
  ends, so the total depends on the seed. It can be simulated the same
  way as the other spell VFX (shared sheet `DAT_800aa01c`, seq `0xd`).

The shared-effect sub-scripts spawned through opcode 24 weren't scanned.



A separate mechanic from the `ActionType==4` command above: Suikoden 1 has
five **magic** Unite spells — Scorched Earth (Fire+Earth), Storm Fang
(Earth+Wind), Water Dragon (Wind+Water), Thor (Water+Lightning), Blazing
Camp (Lightning+Fire) — per
[Suikosource's Unite Magic page](http://www.suikosource.com/runes/unitemagic.php).
Each requires two Level-4 spells of adjacent elements cast the same round,
triggers automatically, and follows a strict targeting/resistance priority.

It lives entirely inside `battle_select_special_ability` (Rune resolver):
when a caster selects `AbilitySlot==4` (their own Lv4 spell),
`battle_check_magic_unite(attacker_idx, own_lv4_spell_id)` scans every other
still-unresolved party member for one who *also* queued `ActionType==2` +
`AbilitySlot==4` this round, checks the spell-id pair against a lookup table
(`DAT_8016c724`, 3 bytes/entry, 40 entries), and on a match marks the
partner's action resolved, plays a shared animation, and returns the
combo spell id (fed into the same spell table normal spells use). No match
falls back to the caster's own solo Lv4 spell.

The 40-entry table decodes to 8 raw pairings × 5 combo outputs (every
element has a Lv4 and Lv5 id):

| Element | Lv4 id | Lv5 id |
|---|---|---|
| Fire | `4` | `29` |
| Earth | `24` | `33` |
| Wind | `16` | `31` |
| Water | `12` | `30` |
| Lightning | `20` | `32` |

| id | Spell | Elements | flags (`+0x16`) |
|---|---|---|---|
| `34` | Scorched Earth | Fire + Earth | `1` |
| `35` | Storm Fang | Earth + Wind | `1` |
| `36` | Blazing Camp | Lightning + Fire | `1` |
| `37` | **Thor** | Water + Lightning | `3` |
| `38` | Water Dragon | Wind + Water | `1` |

Thor is the only one flagged single-target, and only when the faster
caster's contribution was specifically Ball of Lightning (Lightning's own
Lv4, itself single-target). Element adjacency forms the expected
Fire–Earth–Wind–Water–Lightning 5-cycle. Thor's `+0x16` flag word (`3`,
vs. `1` for the other four combos) matches its documented single-target
behavior and cross-validates the same field's meaning in the full spell
table below (`3` = single-target, `1` = AOE, wherever both a spell and a
sibling of its own level differ only in that bit).

**Turn use and damage** (decompile, 2026-09-27). The combo fires on the
turn of whichever caster rolls first. The partner is the first party
member, in index order, with ActionTag `0`, `ActionType 2`, `AbilitySlot
4` and a matching Lv4 spell. The partner gets ActionTag `1` (turn used)
and loses a Lv4 charge (`decrement_rune_level_charge`, `0x800f5344`).
There's no alive or validity check on the partner, which needs a live test.
Damage comes from `calc_dual_element_spell_damage` (`0x80125c94`), which
has no RNG:

```
dmg = base_power + caster.MGC / 2
c   = max(compat[elemA], compat[elemB])    -- worst of the two wins
c == 1: x2    c == 2: /2    c == 3: 0    c == 0: unchanged
```

The worst compatibility wins: immune beats resist beats weak. The
`caster` argument is most likely the initiating caster, not yet
confirmed.

### The full spell table: `DAT_8016d33c`

`DAT_8016d33c` is the canonical spell definition table both
`battle_select_special_ability` (normal Rune casts) and
`battle_check_magic_unite` (combo casts) index into. Its first dword is a
count (`0x26` = 38), followed by 38 consecutive 4-byte pointers (1-based:
spell id `N` → array index `N-1`), each pointing to a 0x20-byte struct:

- `+0x00`: the spell's display name, **charmap-encoded** (see
  [lib/Charmap.lua](../../lib/Charmap.lua)), null-terminated, no fixed
  length (padding fills the rest of the name region up to `+0x16`). The 5
  combo-Unite structs (ids 34-38) do *not* have a valid charmap name here —
  those bytes are non-printable, presumably unused since combo casts never
  show a normal "cast X" name prompt.
- `+0x16`: the target flags word, fully decoded: bit `0x8` = ally audience,
  low 2 bits = target validation. All six values that occur (`0`, `1`, `2`,
  `3`, `8`, `0xA`) are listed per spell in "Target flags by spell" below
  and decoded in "`+0x16` flags word" further down.
- `+0x1c`: the `cast_entry` code pointer (see "How spells call RNG" below).

All 38 ids, decoded directly from the charmap names (element/level grouping
inferred from struct adjacency and cross-checked against the already-traced
spells below — marked ✓ where an independent RNG trace confirms the row):

`base_power` is terse here — anywhere it says "see notes below," the full
mechanism (formula, target scope, field offsets) is spelled out in the
notes list right after this table, not lost, just not duplicated in-cell.

| id | Element | Lv | Name | flags | base_power |
|---|---|---|---|---|---|
| 1 | Fire | 1 | Flaming Arrows ✓ | `3` | 100 |
| 2 | Fire | 2 | Firestorm ✓ | `1` | 150 |
| 3 | Fire | 3 | Dancing Flames ✓ | `1` | 400 |
| 4 | Fire | 4 | Explosion ✓ | `1` | 700 |
| 29 | Fire | 5 | Final Flame ✓ | `1` | 900 |
| 5 | Resurrection | 1 | Scolding ✓ | `3` | 70 (×2 vs undead) |
| 6 | Resurrection | 2 | Yell ✓ | `A` | revive+heal, see notes |
| 7 | Resurrection | 3 | Scream ✓ | `8` | heal, see notes |
| 8 | Resurrection | 4 | Charm Arrow ✓ | `1` | 500 |
| 9 | Water | 1 | Drops of Kindness ✓ | `A` | heal, see notes |
| 10 | Water | 2 | Fog of Deception ✓ | `1` | debuff, see notes |
| 11 | Water | 3 | Water of Kindness ✓ | `8` | heal, see notes |
| 12 | Water | 4 | Rain of Kindness ✓ | `8` | heal, see notes |
| 30 | Water | 5 | Mother Ocean ✓ | `8` | heal, see notes |
| 13 | Wind | 1 | Wind of Sleep ✓ | `1` | inflicts Sleep/id5, see notes |
| 14 | Wind | 2 | The Shredding ✓ | `3` | 400 |
| 15 | Wind | 3 | Healing Wind ✓ | `A` | heal, see notes |
| 16 | Wind | 4 | Storm ✓ | `1` | 500 |
| 31 | Wind | 5 | Shining Wind ✓ | `1` | 500 |
| 17 | Lightning | 1 | Angry Blow ✓ | `3` | 150 |
| 18 | Lightning | 2 | Rainstorm ✓ | `1` | 100 |
| 19 | Lightning | 3 | Raging Blow ✓ | `3` | 600 |
| 20 | Lightning | 4 | Ball of Lightning ✓ | `3` | 1000 (single-target) |
| 32 | Lightning | 5 | Thunder God ✓ | `1` | 900 |
| 21 | Earth | 1 | Clay Guardian ✓ | `2` | buff, see notes |
| 22 | Earth | 2 | Voice of Earth ✓ | `1` | 300 (no flying) |
| 23 | Earth | 3 | Copper Flesh ✓ | `2` | status, see notes |
| 24 | Earth | 4 | Earthquake ✓ | `1` | 700 |
| 33 | Earth | 5 | Guardian of Earth ✓ | `0` | buff, see notes |
| 25 | Dark | 1 | Deadly Fingertips ✓ | `3` | 2 (instant-death) |
| 26 | Dark | 2 | Black Shadow ✓ | `1` | 300 |
| 27 | Dark | 3 | Hell ✓ | `1` | 2 (death, AOE) |
| 28 | Dark | 4 | Judgment ✓ | `3` | 1500 |
| 34 | Fire+Earth | combo | Scorched Earth ✓ | `1` | 1300, see notes |
| 35 | Earth+Wind | combo | Storm Fang ✓ | `1` | 1000, see notes |
| 36 | Lightning+Fire | combo | Blazing Camp ✓ | `1` | 1500, see notes |
| 37 | Water+Lightning | combo | Thor ✓ | `3` | 2000, see notes |
| 38 | Wind+Water | combo | Water Dragon ✓ | `1` | 800, see notes |

**id / struct / cast_entry** (same 38 ids, in table order above):

| id | struct | cast_entry |
|---|---|---|
| 1 | `8016D61C` | `800FEAEC` |
| 2 | `8016D63C` | `800FF428` |
| 3 | `8016D65C` | `80100140` |
| 4 | `8016D67C` | `80101130` |
| 29 | `8016D69C` | `80101E88` |
| 5 | `8016D8FC` | `80102DC0` |
| 6 | `8016D91C` | `80103824` |
| 7 | `8016D93C` | `80104468` |
| 8 | `8016D95C` | `80105080` |
| 9 | `8016DBBC` | `801058AC` |
| 10 | `8016DBDC` | `80106178` |
| 11 | `8016DBFC` | `801068CC` |
| 12 | `8016DC1C` | `8010726C` |
| 30 | `8016DC3C` | `80107FB4` |
| 13 | `8016DEE0` | `80108B58` |
| 14 | `8016DF00` | `801093EC` |
| 15 | `8016DF20` | `80109D98` |
| 16 | `8016DF40` | `8010A67C` |
| 31 | `8016DF60` | `8010B044` |
| 17 | `8016E1C0` | `8010C118` |
| 18 | `8016E1E0` | `8010CBD8` |
| 19 | `8016E200` | `8010D848` |
| 20 | `8016E220` | `8010E4CC` |
| 32 | `8016E240` | `8010F418` |
| 21 | `8016E4A0` | `80110438` |
| 22 | `8016E5B0` | `80112A8C` |
| 23 | `8016E4C0` | `80110CC8` |
| 24 | `8016E4E0` | `801116D0` |
| 33 | `8016E500` | `80112048` |
| 25 | `8016E8A0` | `80113A68` |
| 26 | `8016E8C0` | `801148AC` |
| 27 | `8016E8E0` | `80115654` |
| 28 | `8016E900` | `80116638` |
| 34 | `8016EB60` | `801179BC` |
| 35 | `8016EB80` | `80118938` |
| 36 | `8016EBA0` | `80119584` |
| 37 | `8016EBC0` | `8011A7F4` |
| 38 | `8016EBE0` | `8011BDE4` |

Notes:

- **Id 22 resolves the earlier structural anomaly**: its struct address
  (`8016E5B0`) sits outside the otherwise-contiguous Earth block
  (`8016E4A0`/`E4C0`/`E4E0`/`E500`), which previously looked like it might
  mark id22 as a special/unique-rune slot. Its charmap name decodes to
  "Voice of Earth", confirming it's simply Earth Lv2 — allocated
  out-of-line for unknown reasons (build/patch ordering, most likely), not
  structurally special. Its `apply_elemental_multiplier` call site
  (`0x8011349c`) independently confirms `Lvl=2, Element=2 (Earth)`,
  matching the struct-derived row exactly.
- **Hell's level, now independently confirmed (not just struct-position
  inferred)**: its `apply_elemental_multiplier` call site (`0x80116078`)
  passes `a0=3` literally — Dark Lv3, matching the struct-order inference
  exactly. See also the "How spells call RNG" table below, updated to drop
  the earlier "Lv4\*" uncertainty marker.
- The Resurrection and Dark elements only have 4 levels each (no Lv5 entry
  in this table), unlike the 5 elements with Unite Magic.
- **`base_power`/effect coverage**: 21/38 ids have a confirmed
  `apply_elemental_multiplier`-based `base_power`, cross-checked 1:1 against
  ["The 21 callers"](#the-21-callers) below (element and level both match
  with zero discrepancies — see that section for full derivation, including
  the compatibility-scaling formula the power feeds into). Coverage of "21
  callers" was verified exhaustively, not just via xref lookup: a whole-
  `main.exe` raw-instruction scan for the `jal 0x80125b28` opcode returns
  exactly those 21 call sites and no others (per
  [[feedback-ghidra-xref-completeness]]). A second pass traced the remaining
  17 non-elemental ids by decompiling their `cast_entry` → `vfx_setup` →
  `tick_state_machine` chains and searching for the two other HP-mutation
  entry points, `apply_hp_damage_display` (`0x800e1654`, confirmed via the
  same exhaustive `jal`-opcode-scan technique: sign convention is
  **negative = heal, positive = damage**) and `apply_status_effect`
  (`0x800e04dc`). All 38 ids now have a confirmed element/level/name and a
  confirmed mechanism, with 26/38 having a confirmed numeric power/magnitude
  (21 elemental + 5 combo) and the rest having a confirmed non-numeric
  effect (heal formula, stat multiplier, or status id) — **Wind of Sleep
  (id13) is now resolved too (2026-09-19)**, closing out the last
  unconfirmed mechanism: see its own entry below.
  - **Water (ids 9, 10, 11, 12, 30)**: four are heals — Drops of Kindness
    (id9) and Healing Wind (id15, Wind not Water — see its own row) heal a
    single target to full (`-(HP_Max - HP_Current)`); Water of Kindness
    (id11) and Rain of Kindness (id12) both apply a fixed party-wide +300
    (same magnitude at two different levels — not further resolved *why*
    they'd differ in power if at all); Mother Ocean (id30) is the party-wide
    heal-to-full upgrade. **Fog of Deception (id10) is the one exception**:
    not a heal at all — an all-enemies debuff multiplying `combatant_rec
    +0x36` by 0.8 (i.e. -20%). This corrects the prior pass's blanket "all 5
    are heal/buff" note. `+0x36`'s exact identity: confirmed (2026-09-19,
    via `calc_hit_chance`'s own disassembly) to NOT be the same field that
    formula reads for SKL-based accuracy/evasion — that's fixed at `+0x26`
    and `calc_hit_chance` never touches `+0x36`. It's a genuinely separate,
    still-unnamed field sitting in `combatant_rec`'s `0x34-0x43` gap (see
    the `+0x42` note just below — both live in that same gap, likely part
    of one small derived-stat array).
  - **Yell and Scream (ids 6, 7) are healing/revival spells, not debuffs**:
    this corrects the prior pass's naming-based guess. Yell revives a
    downed single ally (clears the KO/`bValidFlag` immediately before
    healing) for `HP_Max/3`; Scream is a fixed party-wide +300 heal, no
    revive check. Both fit the "Resurrection" element name far better than
    the original "debuff" guess did.
  - **Clay Guardian and Guardian of Earth (ids 21, 33) are stat buffs, not
    status-effect casts**: both multiply `combatant_rec+0x42` (`aUnk_0x34`
    Ghidra field `+0xe`) by 1.5; Clay Guardian targets one ally, Guardian of
    Earth applies it party-wide. Neither calls `apply_status_effect` — the
    earlier hypothesis that they shared Copper Flesh's status mechanism was
    wrong. **`+0x42`'s likely identity (2026-09-19)**: `+0x34` through
    `+0x42` spans exactly 8 `u16` slots — the same width and (by position)
    plausibly the same layout as `lib/BattleSnapshot.lua`'s independently
    RE'd `FUN_800d4ec0` item-bonus accumulator array, whose slots 6/7
    (`bonus6`/`bonus7`, the "ATK-final"/"DEF-final" accumulators a flat
    accessory bonus lands in on top of the base PWR/DEF-derived values) sit
    at the same relative end of an 8-slot block. If that mapping holds,
    `+0x42` is the character's **fully-computed final DEF** (post
    equipment-bonus), consistent with "DEF-family" — not literally the same
    field as `calc_damage`'s own `target.DEF(+0x32)` read, but very likely
    feeds into it via the same post-confirm derived-stat population this
    project has already flagged as stale for ~5 frames after `confirmRound()`
    (see [[feedback-derived-stat-timing-after-confirmround]]). Not
    independently confirmed by tracing that copy step itself this pass —
    flagged as the strongest lead, not proven.
  - **Copper Flesh (id23)** is the one id in this group that genuinely does
    call `apply_status_effect(ctx, 8)`, via helper `FUN_80111220` — found
    only through the raw `jal`-opcode scan (dispatched indirectly through a
    phase-switch jump table, so it has no static xref and doesn't appear in
    `get_function_callees` either — see [[feedback-ghidra-xref-completeness]]).
    Status id8 is independently named "Copper Flesh" in the status-effects
    section above, an exact match to this spell's own name.
  - **Wind of Sleep (id13) — RESOLVED 2026-09-19.** The prior pass's "zero
    calls, direct or indirect, full stop" claim for `tick_state_machine`
    (`FUN_80108d54`) was wrong — it missed `case 3`'s
    `play_attack_animation(target_idx, param_1, &DAT_8016de9c)` call, made
    against every valid (non-instant-death-immune) **enemy** combatant (the
    loop runs `dwPartyCount+1..dwTotalCombatants`, the enemy index range) —
    meaning Wind of Sleep targets enemies, not allies, matching its
    offensive Fire/Lightning/Earth Lv1 siblings' pattern far better than the
    earlier "party status" framing did. `DAT_8016de9c`'s bytecode was
    sequentially parsed opcode-by-opcode (each opcode's exact
    cursor-advance width individually re-decompiled and confirmed — opcodes
    3, 4, 5, 15, 21, 22, 38, 39, 41 — not just pattern-matched) and contains
    `anim_op_roll_status_effect_chance(status_id=5, chance_arg=30)` at a
    verified-aligned position, immediately preceded by a `set_busy_flags`/
    followed by a matching `clear_busy_flags` pair (a coherent, sensible hit
    -reaction script shape). **`status_id=5` is the exact same status Beast
    Commander's attack inflicts** (see the status-effects section
    above), at the identical `chance_arg=30` — strong evidence both attacks
    reuse a common status-roll script template rather than being
    independently authored, and confirms `id5` really is **Sleep** by
    design (the user reverted the earlier tentative "Charm" naming given
    this cross-confirmation, 2026-09-19) — its permanent/inputs-ignored
    behavior is a genuine engine bug in Sleep's implementation, not
    evidence it's a different status.
  - **Combo Unite spells (ids 34-38)**: confirmed to never call
    `apply_elemental_multiplier`, but all 5 DO call `apply_hp_damage_display`
    directly, via a shared, not-`apply_elemental_multiplier` dual-element
    helper `FUN_80125c94(element_a, element_b, target, attacker, base_power)`
    — base_power confirmed for all 5 (see table above). This helper's own
    element-compatibility math (presumably how Unite spells hit multiple
    resistances/weaknesses at once) wasn't traced this pass.
- **`+0x16` flags word — FULLY DECODED 2026-09-19.** Two independent axes,
  not one:
  - **bit `0x8`**: ally-audience flag (spell targets ally/allies rather
    than enemy/enemies).
  - **low 2 bits** (the field's actual consumer, `battle_select_special_
    ability` `0x800f5500`, `*(iVar8+0x16) & 3`): `0`=unconditional, no
    target validation (full-party effects, e.g. Guardian of Earth); `1`=
    only checks `dwUsesAvailableCounter >= 1` — at least one living enemy
    exists — with no specific-target validation (AOE-all-enemies spells);
    `2`=validates the given `TargetIdx` as-is, no reselect (single
    ally-target spells — Clay Guardian, Copper Flesh, and, combined with
    bit `0x8` as flag `0xA`, Yell/Drops of Kindness/Healing Wind); `3`=
    validates `TargetIdx` and, if invalid, reselects the next living enemy
    via `FUN_800f6344` (confirmed by decompiling it — the loop scans
    `dwPartyCount+1..dwTotalCombatants`, the enemy range, NOT allies) —
    single enemy-target attack spells (Flaming Arrows, Ball of Lightning,
    Deadly Fingertips, Judgment, Thor, etc.). This corrects an
    **independently wrong** 2026-09-07 plate comment on
    `battle_select_special_ability` that labeled `3`="ally target" — that
    was never live/behaviorally verified and directly contradicted by every
    flag-`3` spell in this table being a confirmed single-target *enemy*
    attack. Cross-validated against every row in the spell table above with
    zero exceptions (notably Hell/id27 flag=`1`=AOE vs. Deadly Fingertips
    /id25 flag=`3`=single, both instant-death Dark spells, correctly
    distinguished by this exact legend).

### The unique-rune ability table (`DAT_8016a630`)

`battle_select_special_ability`'s ability-set record has a `+0x16` flag byte
that takes three distinct values, read from all 34 entries of the
equipped-rune lookup table (`DAT_8016a0e0`):

- `0` — the 5 basic elemental runes (Fire/Water/Wind/Earth/Lightning) + Soul
  Eater: normal leveled spell progression through `DAT_8016d33c`.
- `1` — exactly 6 entries, charmap-decoded by name as **Boar Rune, Shrike
  Rune, Falcon Rune, Hate Rune, Trick Rune, Clone Rune** — real Suikoden 1
  unique/single-character runes, distinct from the generic elemental set.
  `DAT_8016a630` is a separate special-ability definition table specifically
  for these unique runes, structurally parallel to (but a distinct pool of
  entries from) `DAT_8016d33c`'s elemental spell table, and read via the
  identical `+0x1c`=cast-handler / `+0x16&3`=target-type-flags shape.
- `2` — every remaining entry (from index 14 onward) — unconditionally
  **rejected** by `battle_select_special_ability` (`if (flag != 1) return
  -1`, inside the branch that only runs when flag isn't `0`) — these rune
  slots can never be selected as a normal Rune action through this code
  path at all.

The per-rune `DAT_8016a0e0` record also has an undocumented `+0x18` field
(slot count) and a fuller `+0x16` flags word (bit `0x8000` = roster-id
whitelist for character-restricted unique runes).

#### Falcon Rune (Valeria, Rune.Id 10)

Traced 2026-09-27 from `main.exe`, **live-confirmed the same day**
(`scripts/VerifyFalconRune.lua`, `Dragon.State`, 4 seeds × 3 rounds: 12 of
12 hits matched `3 × calc_damage` using the first `rand()` of the damage
frame, none matched ×1, no misses). Falcon's rune
record (`DAT_8016a0e0[10]`, flag `1`) maps slot 0 to ability id 3.
`DAT_8016a630[3]` has target type 3 (one enemy; an invalid target is
replaced by the first ready enemy) and cast handler `0x800f8c24`.
Unique runes skip `decrement_rune_level_charge` and the shared item-use
script.

```
rune_falcon_cast_entry (0x800f8c24):
    Valeria plays her own script slot 13 at the target
    multiplier global DAT_8017a008 = 30; DAT_80179ff8 = her slot 14 script
rune_falcon_wait_impact (0x800f86f0), each tick:
    Valeria's +0x40 & 0x2 (impact, f62 of slot 13):
        target plays Valeria's slot 14 (at Valeria)
        target's +0x50 = rune_falcon_apply_damage
rune_falcon_apply_damage (0x800f881c), on the TARGET, each tick:
    target's +0x40 & 0x2 (impact, f94 of slot 14):
        dmg = ★calc_damage(Valeria, target)
        apply_hp_damage_display(target, dmg * 30 / 10)    -- exactly 3 x dmg
rune_falcon_wait_done (0x800f87d4): Valeria's +0x40 & 0x4 -> done,
    gate unchanged
```

So Falcon does exactly `3 × calc_damage(Valeria, target)`, with no hit
roll and no crit. `calc_damage` is her normal one (ATK − DEF with the
variance roll, weapon-element weakness and Rune Piece bonus included), so
the ×3 applies after all of those (user-confirmed live 2026-09-29; the
scripted run's Valeria had no piece and no element). `dmg × 30 / 10` loses nothing to
rounding. Neither script calls `rand()` (static walker), so the only RNG
is the one `calc_damage` roll. Live, the target's impact bit was set 158
frames after Valeria's `ActionTag` flipped and the damage landed on the
next frame (+159), on every hit. The walker's estimate (slot 13 impact
f62, then slot 14's impact 94 frames later) came out one frame short,
since it walked slot 14 with Valeria's sprite rather than the target's.

#### Boar Rune (Rune.Id 8)

Traced 2026-09-29 from `main.exe`, **live-confirmed the same day**
(`scripts/VerifyBoarRune.lua`, `Seifu6Ant.State`, Pahn, 6 seeds × 2
casts: 12 of 12 hits matched `2 × calc_damage` using the `rand()` of the
damage frame, none matched ×1, no misses, and all 12 casts Unbalanced
Pahn). Boar's rune record (`DAT_8016a0e0[8]`, flag `1`, roster whitelist
bit set) maps slot 0 to ability id 1. `DAT_8016a630[1]` (`0x8016ca2c`)
has target type 3 (one enemy, reselected if invalid) and cast handler
`rune_boar_cast_entry` (`0x800f8a9c`). That handler is Falcon's,
instruction for instruction, except for the multiplier global:

```
rune_boar_cast_entry (0x800f8a9c):
    caster plays its own script slot 13 at the target
    DAT_8017a008 = 20; DAT_80179ff8 = caster's slot 14 script
then the shared Falcon chain: rune_falcon_wait_impact ->
    rune_falcon_apply_damage (on the target) -> rune_falcon_wait_done
damage = ★calc_damage(caster, target) * 20 / 10    -- exactly 2 x dmg
```

So Boar does exactly `2 × calc_damage`, with no hit roll and no crit, and
one `rand()` (the variance roll). `× 20 / 10` loses nothing to rounding.
The ×2 applies after everything `calc_damage` does itself for a party
attacker: element weakness +50% (the Rune Piece type's element, else the
weapon's innate one) and the Fire/Earth Rune Piece amp. Both runes call
the same `calc_damage` as a basic attack; the user confirmed both bonuses
live 2026-09-29. (The scripted runs had no element and no piece, so they
didn't exercise either.)

**Self-Unbalance.** None of the handlers touch status. The Unbalanced
comes from opcode 40 (`status 7`, `chance 100`) near the end of the
caster's own slot 13 script. Three party files have this Boar-shaped slot
13/14 pair: Pahn (`pan`, roster 6), Eikei (`eik`, 66) and Morgan (`moh`,
52); only Pahn was live-tested. For a party member, chance 100 always
lands. The Turtle Rune skip can't apply, since the caster is wearing
Boar. The "already Unbalanced" skip can't either, since Unbalanced
disables Rune. So each cast costs exactly one more `rand()`, and the
caster is always Unbalanced.

`apply_status_effect(…, 7)` sets `+0x4d = 1`. At each round end,
`battle_process_round_end_status_and_formation` clears the status if
`+0x4d` is already 0, then decrements it. So a cast in round R leaves the
caster Unbalanced for all of round R+1 (Defend/Item only, no Unite). The
status is cleared at the end of R+1. Live, across all 12 casts: `+0x4d`
went 1 → 0 at R's end, the bit cleared at R+1's end (`+0x4d` → 255). The
slot's active word (`+0x1d58`) stays 1 after the clear, but something
between that round end and the next prompt resets it to 0, so a second
Boar two rounds later re-Unbalances normally. That reset code wasn't
identified.

**Timeline** (Pahn; frames from S, the tick the cast entry runs; identical
in all 12 live casts and to the static walker):

```
S+0     caster busy 1, target busy 8, caster starts slot 13
S+60    caster impact (0x2)           walker, Eikei/Morgan: S+56
S+61    target starts the caster's slot 14; target busy 9
S+261   caster fx 0x10
S+291   caster fx 0x4
S+292   rune_falcon_wait_done returns done (gate unchanged)
S+293   next turn roll, if anyone is left to act; S+294 new actor
S+321   target's slot 14 impact (0x2)
S+322   ★ damage rand() + HP drop; target busy 0 if it survives,
        busy 1 (death) until S+415 if the hit kills it
S+344   ★ Unbalanced roll; caster busy 0     walker: Eikei 340,
                                             Morgan 339
S+347   round over, if Boar was the last action and the target lived
        (S+418 after a kill): the round-end status/backfill tick, 3
        frames after the last busy clears (the round-end wait itself
        passes 1 frame after; see TickBasedAlgorithm.md ROUND_END)
```

Unlike Falcon, the handler is done **before** the damage. The next actor
is picked at S+293 and starts at S+294, so both Boar `rand()` calls land
during that actor's turn, on animation time. The caster stays out of turn
order (busy) until S+344.

### Free Will: automatic action selection

`battle_menu_fight_run_bribe_freewill`'s Free Will branch (choice `3`)
schedules `FUN_800ee5b8`, which runs once and populates every living party
member's `ActionType`/`TargetIdx` in a single pass — no per-character menu
navigation. For each party member, in the order given by a shared per-round
roster array (`DAT_80179fe8+0x1c[]`):

```
ActionType = Defend                                       -- default
if StatusFlags & 0x60 (id5 or Unbalanced/id7):              -- can't act
    skip (stays Defend)
elif validTargetCount(actor) == 0:                         -- see reach rule below
    skip (stays Defend)
else:
    scan forward from a SHARED, PERSISTENT cursor (carried across party
    members within this one Free Will pass, not reset per character)
    through the enemy candidate list (dwUsesAvailableCounter entries,
    DAT_80179fe8+0x38[]), wrapping, for the first entry valid for THIS
    character
    ActionType = Attack; TargetIdx = that enemy
    cursor += 1                                            -- carries to the next character
```

The shared, advancing cursor is what spreads Free Will's attacks across
different enemies instead of piling everyone onto one target — it is not a
per-character independent choice.

`validTargetCount`/per-candidate validity (`FUN_800eec20`, also used by the
manual Fight-menu's Attack option and its own target-cursor screen,
`battle_menu_select_target`) is a weapon-reach rule keyed off
`PersistentStats.bWeaponReachIndex` → the `DAT_80165890` table's `+0x56`
"range class" byte:

- **`1` (melee)**: Zero valid targets at all if the wielder is in the
  **back row** (`bFormationPos > 3`); otherwise falls through to the
  normal-reach rule below.
- **`2` (ranged)**: Every living enemy is valid, front or back row.
- **anything else (normal reach)**: Only **front-row enemies** are
  valid, regardless of the wielder's own row.

This is the same reach rule `calc_damage`'s weapon-elemental-bonus check and
the manual target-select screen's confirm-time reachability check both use —
one shared per-character "who can I hit" rule consumed by three different
callers.

## Status effects: `combatant_rec+0x4a`, `apply_status_effect` (`0x800e04dc`)

**The field**: a 16-bit bitmask, `combatant_rec+0x4a` (same struct as
`ActionType`/`AbilitySlot`/`TargetIdx` at `+0x46..+0x49`). Mask table
(`DAT_8016baa8`, 9×u16): `id0=0x0001`, `id1=0x0002`, `id2=0x0004`,
`id3=0x0008`, `id4=0x0010`, `id5=0x0020`, `id6=0x0080`, `id7=0x0040`,
`id8=0x8000`.

**`id1`/`id2`/`id3` are one escalating ailment ("Balloon"), not three
separate ones**: stages 1/2/3 of the same status — repeated infliction
pushes the afflicted character from stage 1 to 2 to 3, and reaching stage 3
(`id3`) removes them from the party. `anim_op_roll_status_effect_chance`'s
`status_id==1` handling searches whether stage-slots 1, 2, or 3 are already
occupied and applies to the first free one, rather than unconditionally
targeting slot 1. `apply_status_effect` gives exactly `id1`-`id3` (and only
those three) a shared equipment-immunity check, since they're a related
family sharing one "immune to this ailment" accessory check.

**`apply_status_effect(combatant_idx, status_id)`**: two branches —
- **Enemy** (`combatant_idx > partyCount`): ORs the mask bit into `+0x4a`.
  No duration tracking, no immunity check — effectively permanent until
  cleared elsewhere.
- **Party member**: a switch on `status_id` sets an internal tick-duration
  regardless of any caller-supplied default: `id0=12, id1=4, id2=6, id3=8,
  id4=10, id5=15, id6=22, id7=21`. `id5` and `id7` also immediately set
  `ActionTag (+0x46) = 1`, marking the combatant's turn as already-resolved
  without ever going through normal action selection — their `ActionType`
  reads back as the `255` "cleared/uninitialized" sentinel, silently
  skipping their turn rather than forcing an uncontrolled Attack (`id7`
  additionally sets an unidentified `+0x4d=1`). `id8` takes a separate,
  simpler path: sets `combatant_rec+0x4c=2` (a distinct field from the
  persistent Stats struct's own `+0x4c` `Rune.Id` — a coincidental offset
  match, different struct) and skips straight to the same no-duration
  flag-set the enemy branch uses. For `id1`-`id3` specifically (party
  members only), first scans the character's equipment/item list for an
  entry of "type `3`" with a nonzero flag byte — if found, blocks the
  status entirely (an immunity accessory/rune). Otherwise sets the bit and
  populates a per-combatant per-status "slot" record (see the
  `+0x30a0` table above: active flag, a second flag, a counter, and a
  computed value from `FUN_800e1e3c`, likely a status icon/animation-loop
  handle).

**`anim_op_roll_status_effect_chance(combatant_idx)`** (animation-script
opcode 40, script args: `status_id`, `chance_arg`): rolls
`roll = ((rand() * 100) / 0x7fff) % 100` (0-99) against `chance_arg`. The
direction depends on who owns the script (re-read from the decompile
2026-09-27):

- **Party member:** the status lands when `roll < chance_arg`, so the
  chance is `chance_arg`% (`100` = always). It's also skipped, after the
  roll, if the member already has that status (its duration slot is in
  use).
- **Enemy:** inverted. The status lands when `roll >= chance_arg`, so the
  chance is `100 - chance_arg`% (Beauty's Sleep, arg 30, lands 70%).

Either way the roll costs exactly one `rand()`, except in the Turtle Rune
case. Party members get an extra
unconditional-immunity check first: if their persistent-stats `Rune.Id`
(`+0x4c`) `== 25` (Turtle Rune), the roll never happens at all — one of
several rune ids gating hardcoded passive effects on this same field
(`15`/Killer doubles crit chance, `18`/Hazy halves the wearer's attacker's
hit chance, `16`/Counter guarantees a successful dodge/counter — see
"Passive rune effects" below for the full list). This opcode always targets
its *own* `combatant_idx` (no self/target redirect like
`anim_op_set_busy_flags` has): a status-inflicting physical attack works by
the attacker's script marking the target hit (via `anim_op_set_busy_flags`)
while the target's own independently-running script (each combatant in
`enemy_data` runs its own script cursor) reaches this opcode as part of its
own hit-reaction sequence, inflicting the status on itself.

A battle-initialization routine (4 call sites clustered at
`0x800de85c`-`0x800de8b4`) reads each party member's *persistent* save-data
`Status` byte (`lib/Characters/Characters.lua`'s `Status = buffer[0x17]`,
real offset `+0x16`) bit-by-bit (`0x1`/`0x2`/`0x4`/`0x8`) and re-applies
`id0`-`id3` respectively to the fresh in-battle record if set — these 4 are
the classic "still afflicted from the overworld when you enter a new fight"
ailments (this is why only 4 of the 9 ids get an equipment-immunity check
in `apply_status_effect` too — the other 5 are battle-only, no carryover to
protect against).

**Round-end processing** (`battle_process_round_end_status_and_formation`):
- **`id3`** (bit `0x8`): the afflicted party member vanishes entirely from
  the HP list, sprite lies face-down on the battlefield — a one-shot,
  never-expiring effect (`+0x45=1`/`+0x46=1`) triggering front-row
  backfill — a KO/Petrify-equivalent removal from active combat.
- **`id5`** (bit `0x20`) is **Sleep** — settled 2026-09-19 (see below): it
  is the status `Wind of Sleep`'s own attack script independently rolls
  (`status_id=5, chance_arg=30`, identical to Beast Commander's own attack
  — see "Source" below), which the user accepted as confirmation over an
  earlier, briefly-considered "Charm" rename. Its real behavior is buggy
  relative to a "normal" Sleep implementation, though: `ActionType` reads
  back as the `255` "cleared/uninitialized" sentinel after a round passes,
  meaning the turn is silently skipped without ever going through normal
  action selection — matching the enemy-side behavior documented for this
  same bit in `Turn_Order.md`. It shares Unbalanced's (`id7`) visual status
  icon, and while it does skip the afflicted character's turn when their
  turn comes up in order, going back to that character afterward still
  lets the player *input* Defend or Item, exactly like Unbalanced — but
  unlike Unbalanced, that input is ultimately **ignored** (the character
  still doesn't act). Further live-confirmed differences from Unbalanced:
  it does **not** expire after 1 turn, has **no expiration at all**, and
  does **not** clear when the afflicted character is hit — a genuine
  engine bug, root-caused below, not a "Sleep that wakes on hit" design
  gone missing.

  **Source and root-cause, fully traced 2026-09-19** (`BeastCommander.State`,
  static Ghidra + live capture, see `scripts/CheckBeastCommanderAI.lua`):
  Beast Commander's `MonsterRecord.pAttackScriptTable` (`0x800a2248`,
  `b_data.bin`) `+0x08` "hit script" (`0x800a229c`) contains, at relative
  `+0xba`, `anim_op_roll_status_effect_chance(status_id=5, chance_arg=30)`
  — a flat **30% chance per landed hit** to inflict `id5` on the victim
  (for a party-member target, `chance_arg` is the direct infliction %, not
  inverted like the enemy-target branch). This is baked into Beast
  Commander's ordinary attack, not a separately-selected special move —
  "every hit has a 30% chance to also inflict `id5`" is the real mechanic.
  Live capture confirms this exactly: bit `0x20` sets the instant the hit
  lands, `ActionTag`/`ActionType` behave exactly as documented, and the
  status persisted, completely unchanged, through 2 full additional
  rounds (Cleo set to Defend each round, per the "input is ignored"
  finding above) with zero decay.

  **Why it never expires, root-caused via 3 functions**:
  - `apply_status_effect` (`0x800e04dc`) sets `id5`'s generic per-status
    slot-table "counter" field to **`0`**, not to the computed
    duration (`15`) — that `15` only feeds
    `build_sprite_poly_resource(status_id_context, duration)`, almost
    certainly a cosmetic icon/animation-loop parameter (the resulting
    handle, e.g. `0x801903c0` in the live capture, never changes for the
    rest of the fight), not a real countdown. Live-confirmed: the slot's
    `counter` field read exactly `0` from the moment the status applied
    through 2 full rounds afterward, never incrementing or decrementing.
  - `battle_process_round_end_status_and_formation` (`0x800f64f0`), the
    main per-round status-decay function, explicitly does **not** process
    `id5` — only `id3` (Balloon removal), `id7` (dedicated `+0x4d`
    countdown), and `id8` (dedicated `+0x4c` countdown) get decay logic
    there.
  - `battle_refresh_combatant_derived_stats` (`0x800f6ea0`) has the
    **only** `id5`-clearing code anywhere in `main.exe`: a 50%-per-round
    "wake up" roll (`(rand()*100)/0x7fff < 50`, clearing bit `0x20` and
    `ActionTag`) — but its loop is bounded `idx = dwPartyCount+1 ..
    dwTotalCombatants`, i.e. **enemies only**. There is no equivalent
    check anywhere for party-member combatants (`idx = 1..dwPartyCount`).

  **Conclusion**: for a party member, `id5` has no removal code path
  anywhere in the game — a genuine, confirmed engine bug (the wake-up
  mechanic exists and presumably was meant to apply to both sides, but
  only got wired up for enemies), fully explaining the live-observed
  "never expires, doesn't clear on a hit" behavior. An enemy afflicted
  with `id5` (if that's ever achievable) would naturally clear it at
  ~50%/round; the asymmetry is the bug. Not a "Sleep" ailment at all —
  see the corrected "Full roster" entry below.

`id7` (bit `0x40`) and `id8` (bit `0x8000`) use their own dedicated
one-byte countdown fields (`+0x4d` and `+0x4c` respectively, decremented
once per round, expiring via `clear_status_effect` when they hit `0`)
rather than the generic per-status duration-slot table the other ids use —
both resolve in only 1-2 rounds given the initial values `apply_status_
effect` sets. `clear_status_effect`'s own guard clause no-ops for every
status except `id8` unless the generic duration-slot's "active" flag is
also set — `id7`'s natural expiry depends on that slot-table data.

**`id0` (Poison)**: a periodic-damage effect (full formula below).

**`battle_menu_compute_command_availability`** (`0x800eedd0`) populates the
Fight-menu's 5 command slots (Attack/Defend/Rune/Item/Unite)
enabled/disabled before the player picks an action:
- **Attack slot** disabled if `combatant_rec+0x4a & 0x60` (bit
  `0x20`=`id5` OR bit `0x40`=`id7`).
- **Rune slot** disabled if `combatant_rec+0x4a & 0xe0` (bit `0x20`=`id5` OR
  bit `0x80`=`id6` OR bit `0x40`=`id7`).
- **Defend** always enabled; **Item** gated only by the item count.
- **Unite slot** enabled only if at least one Unite passes
  `compute_unite_eligible_slots`. That checks **every** participant,
  the commanded character included, for `+0x4a & 0x61` (Poison, Sleep,
  Unbalanced). See
  [Unite menu eligibility](#unite-menu-eligibility-compute_unite_eligible_slots-0x800ef104).

This means `id7` ("Unbalanced") disables Attack, Rune and Unite, leaving
only Defend/Item selectable for 1 turn, and those selections actually
execute. An Unbalanced character can never Unite (user-confirmed), and
neither can anyone whose Unite needs them. `id6` ("Silence-equivalent")
is a Rune-only disable, nothing else. `id5` shares the same
Attack+Rune-disabled *menu* state with `id7`
(same icon too), but is not functionally equivalent to it — per the
user's live confirmation, `id5`'s Defend/Item input is accepted by the
menu but then silently ignored (the character still doesn't act), and
unlike `id7` it doesn't expire after 1 turn, seemingly never expires, and
survives the afflicted character taking a hit. So `id5` and `id7` share
UI/menu-gating code (both go through the same `& 0x60` checks) without
sharing real behavior — not two names for one status, and not simply
"Sleep vs. Unbalanced" either, as previously guessed. They're wired
through different duration/expiry mechanisms (`id5` the generic
duration-slot table, `id7` its own dedicated `+0x4d` countdown) — and per
the fully-traced root cause above, `id5`'s duration-slot data genuinely
never governs its removal for party members, since no code anywhere
decrements or clears it for them. That's the confirmed explanation for
the divergence, not just a hypothesis anymore.

`id4` is "Bucket," the accuracy-halving status from `calc_hit_chance`'s own
`+0x4a` bit `0x10` check. The real game shows a visible bucket icon over
the afflicted character, which needs a real handle computed by
`FUN_800e1e3c` (spawned only through the genuine `apply_status_effect` code
path).

**Full roster**: `id0`=Poison, `id1`/`id2`/`id3`=**Balloon** (escalating,
stage 3 = removed from party), `id4`=**Bucket** (accuracy-halving),
`id5`=**Sleep** (name settled 2026-09-19 — see below; fully traced the
same day: shares `id7`'s icon and menu restriction, but inputs are
ignored, it never expires, and it doesn't clear on taking a hit —
root-caused to a genuine engine bug, see above. Not truly equivalent to
Unbalanced despite the shared UI. Inflicted by a flat 30% chance on every
landed hit from Beast Commander's ordinary Attack — confirmed via its hit
script's `anim_op_roll_status_effect_chance(status_id=5, chance_arg=30)`
call — and, at the *identical* 30% chance, by the spell **Wind of Sleep**
(id13, see "The full spell table" above) against every enemy it hits, a
second, independent confirmation of the same `status_id`/`chance_arg`
pair — the spell's own name matching this status id is what settled the
naming: a brief "Charm" rename was considered given the behavioral
mismatch with a "normal" Sleep, but withdrawn once Wind of Sleep's own
script confirmed it targets this exact status), `id6`=**Silence-equivalent** (Rune-only
block), `id7`=**Unbalanced** (Attack+Rune restricted, "defend or item
only"), `id8`=**Copper Flesh** (HP-locked/damage-immune for 3 turns).

### Poison (`id0`): mechanics and per-tick damage formula

**Application**: `anim_op_roll_status_effect_chance` (opcode 40, script
args `status_id=0`, `chance_arg`) rolls RNG2 once regardless of the
outcome. For a party-member target the infliction condition is
`roll_pct(0-99) < chance_arg` — so `chance_arg=100` makes the roll
unconditionally succeed, and `chance_arg=0` would make it unconditionally
fail; the roll always consumes RNG, but the outcome can be scripted to be
deterministic on either end. Not gated by the Turtle-Rune immunity check
either way (that check runs before this roll, separately).

**The periodic tick itself: zero RNG, exactly `floor(HP_Max / 20)` per
round** — disassembly of `battle_refresh_combatant_derived_stats`'s
round-start processing (`0x800f6ea0`): for each living party member with
Poison active (`combatant_rec+0x4a & 1`), the code does

```
lh   v0, 0x10(s0)      ; v0 = signed HP_Max (combatant_rec+0x10)
div  v0, s2            ; s2 == 0x14 == 20 (set earlier in the same function)
mflo v0                ; v0 = floor(HP_Max / 20), C truncating division = plain floor since positive
subu a1, a1, v0        ; subtract from the round's accumulated regen total
```

i.e. Poison deals a flat 5% of max HP every round, rounded down — not a
random amount, not scaled by current HP, not affected by DEF or any other
stat. This gets netted against the same round's regen sources (`+5` each
from certain items, weapon-type-2 mastery×5, and Sunbeam Rune) before being
applied via `apply_hp_damage_display(idx, -total)` — so a character with
enough regen sources active can end up healing instead of taking poison
damage on a given round, and the whole thing is skipped (no call at all) if
the netted total is exactly 0.

**Duration: none. Poison never wears off by itself** (corrected
2026-09-30; this used to say "12 rounds"). For a party member,
`apply_status_effect` does set a per-status value of `12` for Poison.
But that value only goes to `build_sprite_poly_resource` (the status
icon). The duration slot's own fields are set to `active=1, 1,
expired=0`, with no counter anywhere:
- `+0x30a8` is an "expired" flag. Only `clear_status_effect` sets it,
  and `FUN_800e02cc` (the per-frame status-icon updater) frees the icon
  once it's set.
- Round-end decay (`battle_process_round_end_status_and_formation`)
  handles only ids 3, 7 and 8.

So Poison lasts until something calls `clear_status_effect(idx, 0)`:
- the death routine `FUN_800e2c90`, which clears every status
- cure fragments `0x800f2d24` / `0x800f3140` (not yet mapped to items)
- `FUN_801204ec`, which clears ids 0–6 together

It also carries over between battles via the save-data Status byte.
This is the same no-countdown behavior as Sleep (`id5`) below. The
Mosquito's opcode 40 passes no duration either way.

### Passive rune effects (`Rune.Id`, persistent Stats `+0x4c`)

`class_ptrs[idx]->+0x1c` reaches the character's persistent Stats struct
(`lib/Party.lua: getCharacterRune` reads the same struct), and `+0x4c` on
it is `Rune.Id` (0-33, the same 34-entry enum decoded above). There is no
separate "weapon-type" struct or field on this offset. A number of engine
functions hardcode per-rune checks against this field directly, rather than
routing through a generic passive-effect system:

- **`14` (`0x0e`) Double-Beat** — `battle_execute_enemy_attack`: enables
  the multi-target attack-repeat path (e.g. Zombie Dragon's Fire
  Breath).
- **`15` (`0x0f`) Killer** — `check_critical_hit`: doubles crit chance
  (up to 50%).
- **`16` (`0x10`) Counter** — `check_dodge_counter`: guarantees a
  successful counter-attack roll on an eligible monster's missed
  attack (see "On a miss or a hit: dodge and counter" above).
- **`18` (`0x12`) Hazy** — `calc_hit_chance`: halves an attacking
  enemy's hit chance against whichever combatant has Hazy equipped
  (boosts the wearer's own evasion).
- **`19` (`0x13`) Gale** — `battle_compute_ally_derived_stats`: doubles
  the SPD stat slot in the per-round derived-stats computation.
- **`20` (`0x14`) Sunbeam** — `battle_refresh_combatant_derived_stats`
  (battle) and `FUN_80126408` (a separate, non-battle subsystem): in
  battle, contributes `+5` to a per-round REGEN total; via a shared
  helper `FUN_801261b0(20)` in the `DAT_8017db24` subsystem (very
  likely the overworld step-counter), heals every party-roster member
  by 1 HP (capped at max) per step.
- **`21` (`0x15`) Holy** — `FUN_801328b0` (the `DAT_8017db24`
  subsystem): gates a boolean check, OR'd with a separate
  roster-id-based check.
- **`22` (`0x16`) Fortune** — `battle_calc_party_exp_award` (renamed
  from a wrong earlier identification, `battle_calc_enemy_aggro` — see
  "EXP award formula" below): doubles the wearer's own EXP award for
  the battle.
- **`23` (`0x17`) Prosperity** — `battle_process_enemy_turns`: doubles
  a battle-wide accumulated total (`DAT_80179fd0+0x224c`) built by
  summing `MonsterRecord.wGoldDrop` (`+0x34`) across every enemy
  actually defeated this battle (gated on a per-enemy "was defeated"
  flag, not just presence in the encounter). The encoding has a bit-0
  "compressed large value" branch (`(raw/10)*100` when the low bit is
  set).
- **`24` (`0x18`) Champion's** — `FUN_80126228`/`FUN_801261b0` (the
  `DAT_8017db24` subsystem): in a `rand()`-based weighted
  lottery/selection event, bypasses a luck-threshold check and forces
  success.
- **`25` (`0x19`) Turtle** — `anim_op_roll_status_effect_chance`:
  unconditional immunity to status-effect infliction.
- **`26` (`0x1a`) Phero** — `find_cover_target`: gates a fallback
  "cover for any opposite-gender ally" condition.

The numeric mapping (id → mechanism) is read directly from code. `MonsterRecord.wGoldDrop`
(`+0x34`) was formally added to the Ghidra struct (struct resized 52→54
bytes).

**Other persistent-Stats fields found**: a `+0x4d` byte checked against a
31-entry `DAT_8016b080` table in the out-of-battle rune-equip menu (a
mastery/eligibility gate, distinct from the cover-mechanic's classData
fields). One `+0x4c` reader, `0x800f81e8`, compares two combatants'
MGC-stat difference (`<10`) and conditionally calls the RNG wrapper — not
otherwise identified.

### Cover mechanic: `battle_check_counter_attack`, `find_cover_target`

**`battle_check_counter_attack`** (`0x800f4d5c`) is the cover mechanic's
real entry point (the name is a historical misnomer, kept unrenamed given
how many places already reference it — it is not a counterattack check).

When an attack is about to land on `target_idx`:

1. **`find_cover_target(target_idx)`** (`0x800f79e0`) resolves whether some
   *other* party member should intercept the hit instead, but only when
   `target_idx`'s own current HP is below 25% of max. Two independent
   trigger paths, checked in order:
   - **A designated low-HP story pairing**: `target_idx`'s own
     "classData[0]" byte (a field one level before the persistent Stats
     struct) is matched against a lookup table at `0x8016c814`, interleaved
     `(self_id, partner_id)` byte pairs, terminated by `0xFF`. Full table
     is 15 pairs: `(8,2) (8,6) (8,1) (1,6) (2,3) (32,38) (38,32) (33,63)
     (9,4) (0,30) (30,0) (62,0) (8,23) (32,45) (14,80)`. Resolving roster
     Ids via `lib/Characters/Addresses.lua` gives (self → cover partner, in
     priority order — a self-id appearing more than once yields a
     multi-candidate priority chain):

     | Self | Cover partner(s), in priority order |
     |---|---|
     | Hero | Gremio → Pahn → Cleo → Kasumi |
     | Cleo | Pahn |
     | Gremio | Camille |
     | Tai Ho | Yam Koo → Kimberly |
     | Yam Koo | Tai Ho *(mutual with Tai Ho's first pick)* |
     | Tengaar | Hix |
     | Sylvina | Kirkis |
     | Eileen | Lepant |
     | Lepant | Eileen *(mutual with Eileen)* |
     | Sheena | Eileen |
     | Kuromimi | Gon |

   - **Phero Rune fallback**: if the above found nobody, and `target_idx`'s
     `Rune.Id == 26` (Phero), scans every other valid, non-busy party
     member (wrapping from `target_idx+1`) for the first one whose own
     "classData+10" byte *differs* from `target_idx`'s — a gender byte.

   **Exact conditions** (decompile re-read and live-checked 2026-09-30,
   `scripts/VerifyCover.lua` + `VerifyCoverCompare.py`, 85/85 predictions
   plus 42 cover timelines exact; pseudocode and JS in
   [TickBasedAlgorithm.md](../../TickBasedAlgorithm.md#find_cover-find_cover_target-0x800f79e0)):
   - **Trigger:** `(short)combatant_rec+0x12 < (short)+0x10 >> 2`. That's
     committed HP (not minus pending damage) against HPMax, strictly less.
     Live: Hero at 28 HPMax was covered at 6 HP, never at 7.
   - **Pair partner:** for each table pair in order whose self-id is the
     target's `classData[0]`, the first party member with the partner's
     roster id (`EnemyData+0`) that isn't the target and passes
     `check_combatant_alive` (not busy, `+0x45` clear, HP − pending > 0).
     A partner who is absent or fails that moves on to the next pair.
     There's no row check. Live: Gremio busy, so Pahn covered; Gremio and
     Pahn busy or KO'd, so back-row Cleo covered.
   - **Phero:** only reached under the same HP trigger. Its scan checks
     `+0x45` and busy, not pending damage. Live: Pahn with Phero was
     covered by Cleo, skipping Ted. Decompile-only quirk: for a target in
     the last party slot, the first index scanned is `partyCount + 1` (an
     enemy) before the wrap.
   - **Nothing else disables cover:** no check for Sleep, Unbalanced,
     Poison, Defend or a queued action (decompile only).

   **The gender byte** (`classData+10`). `classData` is the member's
   loaded `data/04_play/<code>.bin` header (byte 0 roster id, bytes 1-9
   name, byte 10 gender), live-matched through `ClassPtrs[i]` at
   `battle_state+0xf84 + i*0xc`. Phero compares for *difference*, so
   Milich (2) counts as opposite to everyone, and Kuromimi and Gon (3)
   don't count as opposite to each other.

   Female (1), 18 characters:
   : Eileen, Cleo, Camille, Sylvina, Sonya, Ronnie, Kasumi, Milia,
     Tengaar, Valeria, Kimberly, Lorelai, Sarah, Lotte, Hellion, Mina,
     Meg, Odessa

   Male (0), 57 characters:
   : Gremio, Kirkis, Mose, Pahn, Liukan, Hero, Anji, Varkas, Krin, Kasim,
     Flik, Fukien, Futch, Gen, Humphrey, Kage, Kwanda, Luc, Lepant,
     Sydonia, Tai Ho, Viktor, Warren, Yam Koo, Juppo, Kessler, Leonardo,
     Griffith, Kanak, Alen, Grenseal, Rubi, Morgan, Clive, Fuma, Sheena,
     Hix, Crowley, Fu Su Lu, Eikei, Kamandol, Quincy, Meese, Maas, Mace,
     Moose, Blackman, Kreutz, Stallion, Kirke, Kai, Sergei, Sansuke,
     Antonio, Lester, Pesmerga, Ted

   Other values:
   : 2 Milich; 3 Kuromimi and Gon (the kobolds)
2. If a cover character is found, `battle_check_counter_attack` plays
   reciprocal "jump in front" animations between the two, then sets the
   attacker's own per-actor "next micro-state" slot (`combatant_rec+0x50`)
   to **`apply_covered_attack_damage`** (`0x800f5e90`); with no cover
   found, to **`apply_uncovered_attack_damage`** (`0x800f5960`) instead.
   Either way, the attacker's main attack animation still plays against the
   *original* `target_idx` — the actual redirect happens later. The
   ally's `0x8016c270` sets its own busy bit 8 at dispatch, so both the
   ally and the target are busy from t0 (live: all 42 covers).
   `battle_execute_player_attack` (the enemy basic Attack) is the only
   caller.
3. Once the animation reaches its "apply damage" point, whichever state
   function was set runs: `apply_covered_attack_damage` computes and
   applies damage against the **cover character** instead of the original
   target (who takes zero damage — full substitution, not a split or
   partial block); `apply_uncovered_attack_damage` applies it to the
   original target normally (with a couple of alternate hit-reaction
   animations gated on the target's own equip-record `+0x46` byte — a
   weapon/armor-class field, unrelated to `Rune.Id`).

**`PersistentStats`** (`classData+0x1c`) known fields: `+0x44`
(`bWeaponReachIndex`, byte) indexes a per-weapon-type ability/reach table
(`DAT_80165890`, 77 entries, confirmed to be per-weapon-*item* data —
charmap-decoded entry 0 = "Wolf Fang Staff/Dragon Fang Staff/Heaven Fang
Staff", an exact match to `Suikoden-RNG-lib`'s `Weapons.js` item id 1),
used in `battle_menu_select_target`/`FUN_800eec20`, gating whether a
character can target the back row unassisted regardless of formation
position. That same table's `+0x55` field (per-weapon-item byte,
`element+1`, `0`=none) is the weapon's own **innate element** — see
`calc_damage` below. `+0x46` is `Rune_Piece_Type` (not a weapon-type
field — see below), `+0x47`-`+0x4b` are 5 elemental Rune Piece counts
(`lib/Characters/Characters.lua`'s `Weapon.Fire_Piece_Count` etc.), `+0x4c`
`Rune.Id`, `+0x55` item element override (a *different* struct than the
`+0x55` mentioned above — this one lives off `ClassPtrEntry+0x4`, not
`PersistentStats`; only consulted as a `calc_damage` fallback, see below),
and nothing at `+0x56` that combat reads. (The `+0x56` byte tested as `&1`
in `check_dodge_counter` and `==2` in `battle_execute_enemy_attack` is the
weapon record's range class, reached via `ClassPtrEntry+0x4`, the same
struct as the `+0x55` element override. It was misfiled here as
`bDodgeCounterFlag` until 2026-09-25; see
[dodge and counter](#on-a-miss-or-a-hit-dodge-and-counter).)

Every classData (`+0xf84`) access site in `main.exe` touches it only via
offset `0`, `0x10`, or `0x1c` (the Stats-struct pointer) — classData itself
is at least `0x20` bytes (offset `0x1c` is a 4-byte pointer, ending at
`0x20`), and nothing else is read directly off its base.

## Continuation chains and death

Decoded and live-validated 2026-09-25. How a basic Attack plays out after
the executor, for every outcome, and what happens when someone dies. The
static simulator is `walk_path()` in `scripts/AttackTimingWalker.py` (CLI:
`--path <hit|crit|miss|counter|cover|all> <attacker> <target> [ally]`).

**Validation.** `scripts/CaptureAttackPaths.lua` logged every combatant's
continuation, busy byte, effect flags, anim target and HP on three setups
(Moravia Elite Soldiers with party SKL pinned low; the same with the party
Defending under Hazy and McDohl at low HP for cover; Seifu Soldier Ants).
`scripts/ComparePathTimings.py` matched all 200 basic Attacks frame for
frame: 148 hits, 5 crits, 35 misses, 11 counters (both directions), 1 cover,
7 of them kills. Chain steps, damage rolls and every busy set/clear agree.
The comparison feeds each actor's live flags at dispatch and stops each
actor's comparison at its next involvement in another attack.

**In Suikoden-RNG-lib.** Every timing here reduces to sums and `max()`es of
per-combatant values, so the lib carries it as per-combatant fields
(`dodgePoint`, `recover`, `dodge`, `counter`, `death`, `missFree` in
`CharacterAttackTimings.js` / `EnemyAttackTimings.js`) plus the formulas and
constants in `AttackTimingConstants.js`. `scripts/DerivePathTimings.py`
derives them from a full `walk_path` sweep (~90k simulations, every party x
enemy pair) and re-verifies every formula against every pair: all exact
except two primed-counter corners (Clive as the countered attacker, which
can't happen in-game since he's Long range; and Assassin countered by a
primed Eikei, Morgan or Pahn, attacker free only).

### The chains

Each step is a `combatant_rec+0x50` callback, run in the round driver's
step 2 (after the turn logic, before the actor pass), so it sees flag bits
(`EnemyData+0x40`) set during the previous frame's pass. Bits: `0x1`
dodge/counter point, `0x2` impact, `0x4` done, `0x10` damage applied.

| Function | Waits for | Then |
|---|---|---|
| `apply_uncovered_attack_damage` `0x800f5960` | atk `0x2` | ★ dmg |
| `critical_hit_apply_damage` `0x800f5abc` | atk `0x2` | ★ dmg ×3 |
| `ordinary_miss_continue` `0x800f5c1c` | atk `0x1` | tgt dodge |
| `counter_attack_reprisal` `0x800f5db4` | atk `0x1` | tgt dodge |
| `counter_attack_reprisal_continue` `0x800f5f98` | tgt `0x2` | strike |
| `counter_attack_apply_damage` `0x800f6030` | tgt `0x2` | ★ dmg on atk |
| `apply_covered_attack_damage` `0x800f5e90` | atk `0x2` | ★ dmg on ally |
| `..._multitarget_continue` `0x800f5cd0` | atk `0x4` | recover |

What each step plays (`slot n` = `pActionScriptTable + n*4`):

- **Hit / crit:** the target runs the attacker's slot 2 (crit: slot 8) on
  its own sprite. A party attacker with Rune_Piece_Type 1 or 4 uses main.exe
  `0x8016c56c` / `0x8016c648` instead. Damage `|= 0x10`.
- **Miss:** the target runs **its own slot 3** (dodge), aimed at the
  attacker. No damage, no RNG.
- **Counter:** step 1 plays the retaliator's own slot 3 (the same dodge)
  and clears the attacker's `+0x50`. Step 2 clears the retaliator's flags
  and plays its own **slot 5** (counter strike). Step 3 rolls
  `calc_damage(retaliator, attacker)`, clears the retaliator's flags, has
  the attacker run the retaliator's slot 2 as its reaction, gives the
  attacker back its recover step and clears the retaliator's `+0x50`. The
  old plate comment on `counter_attack_reprisal_continue` said the original
  attacker is the actor in step 2; it's the retaliator.
- **Cover:** at dispatch, the ally runs `0x8016c270` (aimed at the target)
  and the target runs `0x8016c29c` (aimed at the ally). At the damage frame,
  damage goes to the ally, the ally runs the attacker's slot 2 and the
  target runs `0x8016c2b4`.
- **Recover:** the attacker runs its own slot 4, which clears its busy
  byte. With Double-Beat, `battle_enemy_attack_advance_multitarget` re-runs
  the executor on the next target first (not modelled).

Enemy attacks use the same continuations. Example frames (McDohl `shu.bin`
vs Elite Soldier `vh1.bin`, from dispatch):

| Attack | Path | Roll | Atk free | Tgt free |
|---|---|---|---|---|
| McDohl -> soldier | hit | 72 | 128 | 108 |
| McDohl -> soldier | miss | none | 128 | 120 |
| McDohl -> soldier | countered | 110 | 177 | 148 |
| soldier -> McDohl | hit | 70 | 150 | 115 |
| soldier -> McDohl | miss | none | 150 | 123 |
| soldier -> McDohl | McDohl counters | 103 | 184 | 126 |

A miss never changes the attacker's timing, only the target's. Coverage
over every file: party-attacker miss and countered paths resolve for all
78 characters; enemy-attacker paths for 105-106 of 124 records (the same
native-handler gaps as the hit path, plus Banshee's dodge and Viperman's
miss). The only characters whose counter scripts never finish are the 18
Long-range ones.

### Two ordering rules

- **Index order.** The step-2 callbacks and the actor pass `FUN_800e09bc`
  both walk combatants by index: party, enemies, then sub-actors. When one
  actor's script waits on another's flags, order decides the frame: a party
  member's dodge waits (opcode 28) for the enemy attacker's `0x4`, and sees
  it one frame later than attacker-first order would. This was the
  consistent +1 on every enemy miss before the walker was fixed.
- **Flags persist between actions.** `EnemyData+0x40` is cleared only by
  the combatant's own executor (the attacker's flags go to 0 at dispatch)
  and by the counter steps. A combatant that dodged still has the `0x2` its
  dodge set, so on its next counter `counter_attack_reprisal_continue`
  fires one frame after `counter_attack_reprisal`, not ~16, and the counter
  lands ~15 frames early (seen live with McDohl, whose dodge at F411 left
  `0x2` set for his counter at F536).

Only opcode 26 sets flag bits; 27 clears, 28 / 29 wait for set / clear.

### Death

`FUN_800e09bc`, right after each combatant's own sprite update
(`FUN_800e2a9c`) and script runner (`FUN_800e358c`): if `+0x45 == 0`, HP
(`+0x12`) < 1 and the busy byte (`EnemyData+5`) is 0, the death routine
runs. Damage is committed in step 3 of the tick, before the pass, so HP is
already 0 on the damage frame; the busy check makes death wait for the hit
reaction, which is why the log shows busy going straight from 8 to 1.

- **Enemy, `FUN_800e2dac`:** `+0x45` = 1, ActionTag = 1, plays the enemy's
  own slot 7, decrements `dwUsesAvailableCounter` and marks the slot
  defeated (`DAT_8017aaf8`). Soldier Ant's slot 7: busy 1, opcode 30 phase
  0, opcode 35 shared handler [3] `0x800f1018`, anim 3, delays 1 + 90 + 1,
  opcode 30 phase 99. Handler `0x800f1018` steps phases 0 and 1, fades the
  sprite in phase 2, and in phase 99 clears the actor's active flag (`+3`)
  **and its busy byte**, then uninstalls. It runs in the same runner call
  that set phase 99, so busy drops a frame before the script's own
  opcode 16. A killed Soldier Ant stays busy 93 frames past its reaction.
- **Party, `FUN_800e2c90`:** clears all 9 statuses, `+0x45` = 1, ActionTag
  = 1, plays main.exe `0x8016c068`: busy 1, anim 3, clear busy, halt. So a
  party death adds no busy time. (Decompile only; no plain party death was
  captured.)

Elsewhere in the same pass: a living enemy whose script has ended restarts
its slot 0 (idle); a living party member not busy switches between the
normal and the "tired" pose (HP < 25% or status bits `0x61`). The same
`0x61` mask gates Unite eligibility, but low HP doesn't: a tired-looking
member at HP < 25% with none of those statuses can still Unite.

### Sacrificial Buddha (item 83)

`FUN_800e2c90` checks, before the normal death: if `battle_state+0x3428 ==
4` and the dying member's own inventory (`PersistentStats+0x1f` count; 4-byte
entries from `+0x20`: id, a byte that must be 0 for the u16 match, equipped,
quantity) holds item `0x53`:

1. `FUN_800ca408` -> `FUN_800ca42c` removes that slot: later entries shift
   down, count - 1, and the removed entry is parked just past the end. It
   doesn't decrement the quantity byte first (unlike
   `battle_try_special_attack`'s item use), which only matters if Buddhas
   could stack; they can't.
2. The member plays `0x8016c400` instead of dying, and the function returns
   **without** touching `+0x45`, ActionTag or statuses.

The revive script: busy 1, anim 3, delay 15; opcode 30 phase 0 + shared
handler [6] `0x800f3170`, wait for phase 99; delay 1; opcode 30 phase 0 +
shared handler [7] `0x800f32d4`, wait for phase 99; anim 2, delay 10, anim
0, clear busy. The handlers:

| Handler | Does |
|---|---|
| `0x800f3170` [6] | phase 0: setup (4 clones), counter 60; 1: swap |
| `0x800f1da4` | counts 60 down; at 0: brightness 255, swap, phase 2 |
| `0x800f1fcc` | brightness -4 per call; below 129 (32 calls): phase 99 |
| `0x800f32d4` [7] | phase 0: heal `HPMax / 2`, phase 99 (same call) |

The heal is `apply_hp_damage_display(idx, -(HPMax / 2))` (truncated), so it
goes through the pending accumulator and is committed on the next tick.

Frames from X, the frame the hit reaction clears busy (all live-confirmed,
6 of 6 revives, `scripts/VerifySacrificialBuddha.lua` on `Seifu6Ant.State`
with McDohl at 1 HP and a Buddha added):

| Frame | Event |
|---|---|
| X | revive starts (busy 8 -> 1), 15-frame delay |
| X+15 | phase 0 |
| X+16 | handler [6] runs setup |
| X+17 | countdown handler installed |
| X+77 | fade handler installed |
| X+109 | phase 99 |
| X+112 | heal queued (pending -29 for HPMax 59) |
| X+113 | HP committed (0 -> 29) |
| X+123 | busy clears |

HP stays 0 until X+113, but the member is busy throughout, so no attack
starts on them and the death check can't fire again. `+0x45` stayed 0 the
whole time. **Keeping ActionTag matters:** with McDohl's AGL pinned to 1 he
died before his turn in 5 seeds, stayed ActionTag 0 through the revive and
performed his queued Attack later that round every time. Statuses also
survive the revive.

**Battle phase `battle_state+0x3428`**, written by the battle coroutine
states (values found by decoding each writer):

| Value | Written by |
|---|---|
| 0 | `battle_process_round_end_status_and_formation` |
| 1 | `0x800f6ae8` (after round end) |
| 2 | `battle_bribe_check_and_apply` |
| 3 | round-start reset (`0x800f6dc8`) |
| 4 | round driver `LAB_800f72f0`, at the start of every tick |
| 5 | `0x800f74a8`: recounts living enemies into `+0x2c` |
| 6 | `0x800f78b0`: counts the roll gate down |

The round driver installs the phase-5 state once the turn sub-coroutine
reports the round over, which can't happen while anyone is busy. So every
death a round's actions cause is in phase 4, and so is round-start Poison
(pending damage, committed on the round driver's first tick).

## Formation management: front-row auto-backfill

`battle_process_round_end_status_and_formation` (`0x800f64f0`, a state
within the same turn-advance coroutine as `battle_advance_turn`) runs a
front-row auto-backfill system after status decay: it checks each side's
front row (formation positions `1-3`) for now-invalid combatants (KO'd, or
removed by a status effect like `id3`) and tries to backfill the gap from
the back row (`battle_swap_combatant_positions`). Party members have no
eligibility restriction. Enemies do, via **`monster_record(enemy.Id)+0x11`**,
the *formation footprint*: how many **extra slots to the right** of its own
slot an enemy claims.

Slots are `combatant_rec+0x44` (`bFormationPos`): `1-3` front row, `4-6` back
row.

**Setup never reads the footprint.** `battle_load_enemy_combatants`
(`0x800dee44`) walks the enemy group's 6 slot bytes in order (the same
6-digit strings as `lib/EncounterTable.lua`'s `encounters`, now confirmed:
string position `n` → `+0x44 = n+1`). Each non-zero byte becomes the next
enemy combatant index, so combatant order is slot order with empty slots
skipped. Sprite x/y/z come from the *group's own* slot-position table
(6 bytes per slot, pointer at group record `+0x14`), so each formation can
place its slots anywhere on screen. That's why groups like Neclord's
Castle's `"333102"` (Hell Unicorn, footprint `2`, in slot 4 next to a
Demon Sorcerer in slot 6) are legal even though the footprints overlap —
nothing validates them.

**Occupancy map**: `mark_enemy_formation_slot_occupancy` (`0x800f777c`)
fills `map[1..6]` (at `0x80179ff0`) with enemy combatant indices, skipping
`+0x45` (invalid) enemies:

```
if pos == 3 or pos == 6:  map[pos]                 -- row's rightmost slot:
                                                   --   footprint ignored
elif fp == 0:             map[pos]
elif fp == 1:             map[pos], map[pos+1]
elif fp == 2 or 3:        map[pos], map[pos+1], map[pos+2]
else (fp >= 4):           nothing marked at all
(each extra slot only if <= 6; later enemies overwrite earlier ones)
```

Spill is capped at slot 6, not at the row edge, so a footprint-`2` enemy in
slot 2 also marks slot 4. Nothing downstream reads it that way, so this is
harmless.

**Enemy backfill** (`battle_process_round_end_status_and_formation`, runs
once per round end):

```
for s in 1..3 where map[s] == 0:
    room = 2  if s == 1 and map[2] == 0 and map[3] == 0
           1  elif s == 3 or map[s+1] == 0
           0  otherwise
    c = FIRST valid back-row enemy (pos >= 4, +0x45 == 0), combatant order
    if c.fp > room: stop -- nobody fills slot s this round
    c.pos = s
    if c.fp < 2: move c's sprite to slot s (group slot table) and play the
                 step-forward animation (DAT_8016c094)
    mark map[s .. s+fp] (just map[3] when s == 3)
```

Consequences:

- **Only the first candidate is checked.** The loop `break`s rather than
  moving on to the next enemy, so a wide back-row enemy early in
  combatant order blocks every back-row enemy behind it, even ones that
  would fit.
- **A footprint-`2` enemy can only be pulled forward into slot 1, and
  only once the whole front row is empty.**
- **Footprint `>= 2` enemies aren't moved on screen.** Only `+0x44`
  changes. The sprite-coordinate rewrite and step-forward animation are
  skipped, so the enemy becomes front-row in the game's logic while its
  sprite stays where it was drawn. Found in the decompile, not yet
  checked live.

**Timing, live-confirmed 2026-09-25** (`scripts/VerifyFormationBackfill.lua`,
`Seifu6Ant.State`, 6 seeds, front ants at 1 HP, Pahn at 1 HP in 3 runs):

- Nothing moves mid-round, on either side. The only `+0x44` writers in
  main.exe are battle load, `battle_swap_combatant_positions` and this
  backfill, and the live runs agree: dead ants and a dead Pahn kept their
  slots (only `+0x45` set) until round end.
- Party and enemy backfills land on the same frame, 3 frames after the last
  actor finishes. Enemy example: with ants 6-9 dead, ant 10 (slot 5) took
  slot 1, ant 11 (slot 6) slot 2, and slot 3 stayed empty. Party example:
  Pahn (slot 3) died and swapped with Cleo (slot 4).
- Enemies only *seem* to move up mid-round: a party Attack whose queued
  target is dead retargets to the first valid enemy in combatant order with
  no range or row check (`battle_execute_enemy_attack`). Short-range Pahn,
  front row, retargeted from dead ant 8 to back-row ant 9 and hit it.
- The party attacker then waits (no RNG) until `check_combatant_alive`
  (`0x800f8604`) passes for its target: not busy, not out, and `HP -
  pending > 0`. `check_combatant_valid_target` (`0x800f8680`) only needs
  `>= 0`, so a target about to die from pending damage isn't retargeted
  away from; the attacker waits for it to go out. Gremio retargeted to ant
  9 while Pahn was hitting it, waited 93 frames until it died, retargeted
  to ant 10 the next frame and attacked the frame after.

**Mid-round exception, decompile-only:** `FUN_8012055c` restores the
original party formation: for a party member in actor slots 1-3 now in the
back row, it swaps them (visibly) with the first actor-4+ member now in
front. Yell (id 6) calls it on its target just before clearing `+0x45` (the
revive); Mother Ocean (id 30) and an unidentified effect at `0x8011c730`
(an 800-power loop, probably Water Dragon) call it for every party member.
It doesn't check that the member it moves forward is alive.

Worked example, Neclord's Castle `"333102"`: Larvae in slots 1-3, Hell
Unicorn (fp `2`) in 4, Demon Sorcerer (fp `1`) in 6. Hell Unicorn is the
first back-row combatant, so while it lives it is the only candidate: no
backfill happens until all three Larvae are dead, then Hell Unicorn takes
slot 1 (claiming 1-3, sprite unmoved) and Demon Sorcerer stays in slot 6
for the rest of the fight. If Hell Unicorn dies first, Demon Sorcerer
becomes the candidate and can fill slot 3 (room is always `1` there),
slot 1 if slot 2 is also empty, or slot 2 if slot 3 is also empty.

So `+0x11` is a **formation-slot occupancy footprint**, not a target-scan
restriction, a species/type tag, or an attack-range flag. Across all 124
`outputs/Bestiary.json` records: 94 are `0`, 24 are `1`, 6 are `2` (Queen
Ant ×2, Zombie Dragon, Dragon, Hell Unicorn, Wyvern). `1` includes the
golem/statue types (Golem, Earth Golem, Clay Doll, Colossus, Devil Armor)
plus Roc, Simurgh, Ekidonna and others. Sprite height and footprint width
are different axes: Gigantes is visually one of the tallest sprites in the
game (clips off the top of the screen) but has footprint `0`.

## `calc_damage` — physical attack formula (`0x800f7e90`)

`calc_damage(attacker_idx, target_idx)`:

1. **Base value**: `attacker.ATK(+0x30) - target.DEF(+0x32)`.
2. **Random variance**:
   - If base `< 10`: `base = (base + 1) - (rand() % 4)`.
   - Else: `base = base + (base/2 - rand()%base) / 5` (C truncating division).
3. **Defend**: if the target is a party member and their `ActionType==1`
   (Defend), `base /= 2`.
4. **Elemental weapon bonus** (attacker must be a party member): determine
   an element id 0-4, from one of two sources:
   - **`Rune_Piece_Type`** (`PersistentStats+0x46`), if in range `1-5`:
     maps through `g_abWeaponTypeToElement` (`0x8016c834`, raw bytes
     confirmed `FF 00 01 02 03 04` — type `1..5` → element `0..4`). A
     socketed Rune Piece **overrides** the weapon's own innate element
     whenever one is set (see the "Rune Piece" write-up right after this
     list for the socketing mechanic itself).
   - Otherwise (`Rune_Piece_Type == 0`, the default — no character starts
     the game with a piece socketed): falls back to the equipped weapon's
     own **innate element**, read from `DAT_80165890[bWeaponReachIndex]
     +0x55` (`element+1`, `0`=none) — confirmed live-matching (after a
     `Suikoden-RNG-lib` data correction) against 4 real weapons: Ruisui
     (Wind), Flashing Sword (Lightning), Seeding How (Earth), Moonlight
     (none — not Sonya's Water sword or any other specific character's
     weapon, which weren't individually checked this pass). This
     mechanism is why a character can have a "natural" elemental weapon
     (per Suikosource's Initial Equipment List, e.g. Sonya/Water,
     Grenseal+Quincy/Lightning, Alen/Fire, Blackman/Earth) despite
     `Rune_Piece_Type` starting at `0` for everyone — it's a property of
     the specific weapon item equipped, not of the character or weapon
     category.

   This is the same unified element numbering the magic-side
   `apply_elemental_multiplier` uses (`0` Fire, `1` Water, `2` Earth, `3`
   Lightning, `4` Wind, `5` Resurrection, `7` Dark/Soul-Eater) — both
   weapon and spell damage paths index the identical `attack_data_table`
   compatibility row. If that element's compatibility byte for the
   target's `Id` is `1` (weak), `base += base/2` (+50%, stacking with the
   variance already applied).

   **Rune Piece damage amp** (separate from the above, `Rune_Piece_Type`
   only): when `Rune_Piece_Type == 1` (Fire) or `== 3` (Earth, by the
   numbering above — **live-confirmed by the user, 2026-09-19**: socketing
   type-`3` pieces amps damage, type-`4`/Thunder does not, exactly matching
   this code path), `base += (base/20) * piece_count`, where `piece_count`
   is read from `PersistentStats + Rune_Piece_Type + 0x46` — i.e.
   `+0x47`(Fire)/`+0x49` for types `1`/`3` respectively. Linear, uncapped in
   this formula (piece counts go up to 255). The other 3 `Rune_Piece_Type`
   values (Water `2`, Lightning `4`, Wind `5`) still get the flat weak-bonus
   above if applicable, but no piece-count scaling — confirmed live for
   Lightning/Thunder (`4`).

   **Rune Piece system**: `lib/Characters/Characters.lua`/`Utils.lua` name
   `PersistentStats+0x46` as `Weapon.Rune_Piece_Type` and `+0x47`-`+0x4b` as
   5 elemental piece counts (Fire/Water/Wind/Thunder/Earth, in that struct
   order) — matching Suikoden 1's real "Rune Piece" mechanic
   (`Suikoden-RNG-lib`'s `Items.js`: `WEAPON_RUNE_PIECE` category, ids
   57-61, "socketed into a weapon to add elemental damage"). Per the byte
   value → element mapping above, `+0x49` and `+0x4b`'s current labels
   (`Wind_Piece_Count`/`Earth_Piece_Count`) look swapped relative to the
   canonical numbering (type `3`=Earth should read `+0x49`, type `5`=Wind
   should read `+0x4b`) — but the user confirmed Earth and Wind display
   swapped *names* in the actual game due to a real game bug, and decided
   (2026-09-19) to keep the current Lua labels as-is, matching the
   in-game (bugged) display text rather than the internal/canonical
   element id. Intentional, not an oversight.

   **Stat and regen bonuses.** Three piece types also give a per-piece bonus,
   from that type's own count only. DEF and SKL come from
   `battle_compute_ally_derived_stats` (`0x800d4ec0`); Water's regen comes from
   `battle_refresh_combatant_derived_stats` (`0x800f6ea0`). Both run for each
   party member at round start:

   | Type | In-game name | Count | Attacks as | Stat bonus |
   |---|---|---|---|---|
   | `1` | Fire | `+0x47` | Fire | none (+5% dmg/piece) |
   | `2` | Water | `+0x48` | Water | +5 HP regen/piece |
   | `3` | Wind | `+0x49` | Earth | +3 DEF/piece (+5% dmg/piece) |
   | `4` | Thunder | `+0x4a` | Lightning | none |
   | `5` | Earth | `+0x4b` | Wind | +2 SKL/piece |

   The DEF bonus goes into the base-DEF slot, which feeds final DEF
   (`combatant_rec+0x32`) one-for-one. Water's regen is healed once per
   round, added to the same round-start total as other regen sources (items,
   Sunbeam) and offset by Poison, so a Poisoned character only nets the
   difference. The type/name mapping and Water's +5 HP/piece regen were
   confirmed by the user (2026-09-25). The DEF and SKL bonuses are
   decompile-only, not yet checked live.
5. **Floor**: clamped to a minimum of `1`.

## `check_critical_hit` (`0x800f835c`)

```
chance = (combatant.SKL(+0x26) + combatant.LUK(+0x2e)) >> 3 (floors), clamped to [3, 25] percent
if combatant is a party member and their Rune.Id (persistent stats +0x4c) == 15 (Killer Rune):
    chance *= 2   -- up to 50%
return (rand() % 100) < chance
```

## `apply_elemental_multiplier` (`0x80125b28`)

The magic/rune-attack equivalent of `calc_damage`:

```
base_total = base_power + floor(attacker.MGC_stat / 2)
if target's compatibility byte for element_id == 1 (weak):   damage = base_total * 2
if target's compatibility byte for element_id == 2 (resist): damage = floor(base_total / 2)
if target's compatibility byte for element_id == 3 (immune): damage = 0
otherwise (neutral):                                          damage = base_total
element_id == 7 (Dark/Soul-Eater) bypasses the compatibility check entirely,
always returning base_total unscaled
```

No random variance anywhere — magic damage is fully deterministic given
base_power, caster MGC, and target compatibility. The attacker stat term
reads the same combatant-record offset documented as MGC above. The target
lookup uses `attack_data_table`, indexed by `enemy_data[target]+0x0` (the
`Id` field) — i.e. the target's own `MonsterRecord+0x20+element_id`, the
6-byte elemental affinity table documented in "Monster record layout"
above. The decompiled function itself contains a leftover debug
`printf("ZOKUSEI %d AISYO %d\n", ...)` (Japanese for "Element %d Affinity
%d") that dumps all 6 bytes of that table on every call — this is what
confirmed the table's existence, size, and exact byte offset.

Called from 21 sites spanning `0x800ff174`–`0x80117350`. Each site loops
over a target index, skips it if `combatant_rec(target)+0x45` is set (an
"already resolved/invalid target" flag), otherwise calls
`apply_elemental_multiplier(a0, element_id, target, attacker, base_power)`
with `base_power` as a compile-time constant. `a0` is **spell level (1–5)**
(`apply_elemental_multiplier` itself never reads it, but it fits every
undisputed spell mapping below with one exception).

### The 21 callers

| Address | Lvl | Element | Power | Spell |
|---|---|---|---|---|
| `0x800ff174` | 1 | 0 (Fire) | 100 | Flaming Arrows (single-target) |
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
| `0x8011349c` | 2 | 2 (Earth) | 300 | Voice of Earth † |
| `0x80111ce8` | 4 | 2 (Earth) | 700 | Earthquake |
| `0x801033e8` | 1 | 5 (Resurrection) | 70 | Scolding (double dmg vs undead) |
| `0x80105748` | 4 | 5 (Resurrection) | 500 | Charm Arrow ‡ |
| `0x80114300` | 1 | 7 (Dark) | 2 | Deadly Fingertips § |
| `0x8011519c` | 2 | 7 (Dark) | 300 | Black Shadow |
| `0x80116078` | 3 | 7 (Dark) | 2 | Hell § |
| `0x80117350` | 4 | 7 (Dark) | 1500 | Judgement |

† Excludes flying targets (`+0x26` bit `0x20`) — skipped entirely
during targeting, not just resisted; see "Monster record layout"
above.
‡ ROM value is 500, not the external reference's 400 — a genuine
discrepancy, not a transcription error.
§ Instant-death, except instant-death-immune targets (`+0x26` bit
`0x4000`, see "Monster record layout" above); `power` here is a
non-HP-effect sentinel, not real HP damage.

Spell ids are cross-referenced against
`Suikoden-RNG-lib/lib/Game/Combat/Magic/Spells.js` (every undisputed match
lines up on damage value exactly — no in-binary name strings exist to
confirm against, see `lib/Charmap.lua`). Element `1` (Water) never appears
because every Water-rune spell in the reference data is ally-targeted
(healing/buffs) and never needs this lookup. Element `7` is the Dark/Soul-
Eater element specifically (not a generic "no-element" sentinel) — it
narratively bypasses normal resistances by design
(`apply_elemental_multiplier`'s `param_2 != 7` check implements the
exemption).

Hell (`0x80116078`) is confirmed by behavior: the code right after this
call site is structurally near-identical to Deadly Fingertips' confirmed
instant-death implementation (both check a target-immunity flag, then
decrement an alive-count and clear a status byte), with extra bookkeeping
consistent with hitting multiple targets (AOE) vs. Deadly Fingertips'
single target.

## Enemy elemental attacks: `calc_rune_element_attack_damage` (`0x800f8174`)

A third damage formula, distinct from both `calc_damage` (physical,
`ATK-DEF`, RNG variance, no elemental scaling) and `apply_elemental_
multiplier` (magic, `base_power+MGC/2`, fully deterministic, elemental
scaling). It combines pieces of both: RNG variance like `calc_damage`, but
with the MGC stat substituted in for both sides, and elemental scaling
folded on top via a different, rune-based resistance mechanism:

```
base = attacker.MGC(+0x2c) - target.MGC(+0x2c)   -- NOT target.DEF
variance: identical to calc_damage's RNG-variance step, one rand() call:
  if base < 10:  base = (base + 1) - rand() % 4
  else:          base = base + (base/2 - rand()%base) / 5   -- C truncating division
followed by a rune-category resistance check (see below)
floor at 1
```

This is a genuinely different resistance mechanism from the
species-compatibility table `calc_damage`/`apply_elemental_multiplier`
share. Since party members have no "species" entry in `attack_data_table`,
an enemy attack that wants to respect elemental resistance on a party
member has to key off something else: the target's own equipped Rune.

Reached indirectly: overlay/monster-script code calls this function through
`RngCallbackTable` slot `86` (`+0x158`), rather than a direct `jal` — which
is why a direct xref search on `calc_damage`'s address doesn't find these
call sites.

**Rune-category resistance table**: the target's own equipped `Rune.Id` is
looked up in a switch table mapping to one of several categories:

| Rune.Id | Rune | Category |
|---|---|---|
| `1` | Soul Eater | **7 (universal)** |
| `2` / `0x1b` | Fire / Rage | 1 |
| `3` / `0x1c` | Water / Flowing | 2 |
| `6` / `0x1e` | Earth / Mother Earth | 3 |
| `4` / `0x1d` | Wind / Cyclone | 5 |
| `5` / `0x1f` | Lightning / Thunder | 4 |
| `7` | Resurrection (alone) | 6 |
| `8`-`0x1a`, `0`, `>0x1f` | (Boar..Phero, Nothing, etc.) | — (see bug below) |

Damage is halved if the target's category equals the attack's own
`element` argument, or if the category is `7` — that second check is
unconditional, independent of `element`, making category `7` (Soul Eater
alone) a universal resist rather than an elemental match. Every other
category only protects against an attack passing the matching `element`
value. Clamped to minimum 1. Fire Rune's own category (`1`) does not match
Fire Breath's `element` argument (`6`) — Fire Rune does not resist Fire
Breath, despite the thematic naming.

### A compiled bug: a free "matching slot index" damage reduction

`calc_rune_element_attack_damage`'s only conditional modifier is a halving
(`if match: damage /= 2`) — there is no doubling/weakness branch anywhere
in this function, unlike `apply_elemental_multiplier` (which has real
weak/resist/immune ×2/÷2/×0 branches). This bug can only ever work in the
player's favor — a free damage reduction, never a hidden weakness.

For every `Rune.Id` *not* in the explicit table above (`0`, `8`-`0x1a`,
anything `>0x1f`), the switch statement jumps straight to the halving
comparison **without ever writing the "category" variable**, which lives
specifically in register **`$s1`** — confirmed directly from the function's
own decompilation (Ghidra names it `unaff_s1`, its own auto-detection of a
register read without being written in this function — not a guess about
"some callee-saved register"). Since `$s1` is callee-saved, the comparison
reads whatever the *caller* left there. **This is the one register that
matters — a caller whose own loop/target counter lives in a different
physical register (`$s0`, `$s3`, `$s4`, `$s5`, ...) cannot trigger this
bug at all, no matter what value that other register holds**, because
`calc_rune_element_attack_damage` never reads it. (Earlier passes through
this doc conflated "some callee-saved register happens to be a loop
counter" with "the specific register the function reads," which produced
several wrong "Live" verdicts below — corrected after the user live-tested
the Sonya Shulen row and it failed; see the note after the table.) In the
monsters where the loop counter genuinely is allocated to `$s1`, that
register is being reused as **the loop's own target-party-slot counter**.

So for any character whose Rune doesn't explicitly override the category,
the "resistance" check accidentally becomes **`target's own party slot
index == element`** — a register-reuse bug, not a real elemental check.
Whichever party member currently occupies the slot matching the attack's
own `element` argument gets an accidental 50% reduction, regardless of what
(if anything) they have equipped, as long as it isn't one of the runes with
an explicit case. A character whose equipped rune *does* have an explicit
category masks the bug for that character.

This bug is a general property of the shared formula function combined
with how each monster's own calling loop happens to reuse registers — but
**only for callers whose loop counter is physically `$s1`**. A first pass
found it at 11 call sites across 7 bosses/monsters (all `$s1`); a
follow-up byte-pattern sweep found more call sites, but per-site tracing
showed several of them use a different register entirely and cannot be
vulnerable no matter what value that register holds:

**#/Monster/Overlay/element/Register**:

| # | Monster | Overlay | `element` | Register |
|---|---|---|---|---|
| 1 | Zombie Dragon (Fire Breath) | `enemy_ai_overlay.bin` | 6 | `$s1` (loop) |
| 2 | Zombie Dragon (dup. script) | `vb5g.bin @0x80012568` | 6 | `$s1` (loop) |
| 3 | "Dragon" (mid-boss) | `dragon_overlay.bin` | 8 | `$s1` (loop) |
| 4 | " | " | 1 | `$s1` (loop) |
| 5 | " | " | 4 | `$s0` |
| 6 | Golden Hydra (final boss) | `vzv.bin` | 8 | `$s0` (loop) |
| 7 | " | " | 4 | `$s1` (loop) |
| 8 | " | " | 1 | `$s1` (loop) |
| 9 | Golem | `va4.bin` | 3 | `$s1` (loop) |
| 10 | Earth Golem | `h_data.bin @0x800837a0` | 3 | `$s1` (loop) |
| 11 | Queen Ant's AoE Earth attack | `va7.bin` | 3 | `$s0` (loop) |
| 12 | Gigantes | `vc3.bin` | 1 | `$s0` (loop) |
| 13 | Colossus | `vad.bin` | 5 | `$s4` (fixed single target, not a loop) |
| 14 | Magic Shield | `vf1.bin @0x80013ac0` | 8 | `$s1` (loop) |
| 15 | Ain Gide | `vac.bin @0x800143b4` | 1 | `$s1` (loop) |
| 16 | Clay Doll | `ve2.bin @0x80014e20` | 3 | `$s1` (loop) |
| 17 | Banshee | `ve2.bin @0x800158dc` | 8 | `$s3` (loop) |
| 18 | Unnamed† (`vf2.bin`) | `vf2.bin @0x800154e8` | 3 | `$s1` (loop) |
| 19 | Unnamed† (`vf2.bin`) | `vf2.bin @0x800169e8` | 3 | `$s0` (loop) |
| 20 | Unnamed† (`vf2.bin`) | `vf2.bin @0x80017110` | 5 | `$s1` (loop, inf.) |
| 21 | Unnamed† (`vf2.bin`) | `vf2.bin @0x80017bd8` | 1 | `$s1` (loop) |
| 22 | Unnamed† (`vf2.bin`) | `vf2.bin @0x8001a630` | 8 | `$s0` (loop, inf.) |
| 23 | "Slot man" | `vb3.bin @0x80012584` | 1 | `$s3` (fixed, no loop nearby) |
| 24 | "Slot man" | `vb3.bin @0x80012f28` | 4 | `$s4` (fixed) |
| 25 | "Slot man" | `vb3.bin @0x800140a8` | 3 | not re-checked |
| 26 | Ninja† | `vh1.bin @0x8001122c` | 6 | `$s3` (fixed) |
| 27 | Whip Wolf† | `e_data.bin @0x80080e34` | 6 | `$s3` (fixed) § |
| 28 | Nightmare | `vd5.bin @0x80015d1c` | 1 | `$s1` (fixed) ‖ |
| 29 | Elite Kobold† | `c_data.bin @0x80080cd0` | 1 | `$s5` (fixed) |

**#/Bug status**:

| # | Bug status |
|---|---|
| 1 | **Live — slot 6** ‡ |
| 2 | Live — slot 6 (identical script to the confirmed instance above) |
| 3 | Dormant (`>7`) |
| 4 | Structurally plausible, untested — slot 1 |
| 5 | **Not vulnerable — wrong register** |
| 6 | Dormant (`>7`) — also wrong register, moot |
| 7 | Structurally plausible, untested — slot 4 |
| 8 | Structurally plausible, untested — slot 1 |
| 9 | Structurally plausible, untested — slot 3 |
| 10 | Structurally plausible, untested — slot 3 |
| 11 | **Not vulnerable — wrong register** ¶ |
| 12 | **Not vulnerable — wrong register** |
| 13 | **Not vulnerable — wrong register** |
| 14 | Dormant (`>7`) |
| 15 | Structurally plausible, untested — slot 1 |
| 16 | Structurally plausible, untested — slot 3 |
| 17 | Dormant (`>7`) — also wrong register, moot |
| 18 | Structurally plausible, untested — slot 3 |
| 19 | **Not vulnerable — wrong register** |
| 20 | Structurally plausible, untested — slot 5 |
| 21 | Structurally plausible, untested — slot 1 |
| 22 | Dormant (`>7`) — also wrong register, moot |
| 23 | **Not vulnerable — wrong register** |
| 24 | **Not vulnerable — wrong register** |
| 25 | Unresolved |
| 26 | **Not vulnerable — wrong register** |
| 27 | **Not vulnerable — wrong register** |
| 28 | Structurally plausible, untested — slot 1 ‖ |
| 29 | **Not vulnerable — wrong register** |

‡ Extensively live-confirmed by the user, including a controlled slot-swap test — see the plate comment on `calc_rune_element_attack_damage`.
§ Byte-identical template to Ninja’s site, possibly a shared "wait then strike locked target" script rather than shared identity.
‖ Register match assumes the locked target’s own slot is what feeds `$s1` at this call — matches Nightmare’s documented front-row-only, no-move-choice AI, but not independently confirmed.
¶ Live-confirmed not bugged — see Queen Ant below.

`†` = tentative monster-name attribution (inferred from overlay/address
proximity to other documented AI, not a confirmed function/name match —
treat as a lead, not a settled fact). The `vf2.bin` cluster monster(s)
remain entirely unidentified. **Still unresolved:** Siren (`g_data.bin
@0x80080f44`, `element=8`, register not re-verified) — dormant regardless
of register since `element=8` already kills it, so low priority to chase
further.

**Important caveat on every "Structurally plausible, untested" row**:
outside of Zombie Dragon (both copies), *none* of these have been
live-verified — they're inferred from static disassembly matching the
right register (`$s1`) and an in-range `element`. That inference has
already produced one confirmed-wrong "Live" verdict below (Sonya Shulen),
so treat every "structurally plausible" row as a lead for live testing,
not a settled fact, until someone actually checks it in-game the way
Zombie Dragon's was checked (moving characters into/out of the matching
slot and confirming damage changes only there).

Max real party size is 6, so any `element` value `>6` makes a *slot-index*
match permanently unreachable; max rune category is 7, so any `element`
value `>7` (i.e. just `8` in every case observed) kills *both* mechanisms
at once ("dormant" rows) regardless of register. `element=7` (Soul
Eater — already a universal resist on its own, so redundant as an
`element` argument) never appeared as an `element` argument anywhere in
this sweep.

**Correction, live-tested 2026-09-17 — the Sonya Shulen row was wrong.**
A previous fork traced Sonya Shulen's boss AoE spell (confirmed
**Water**-elemental, `element=2`, via a native sub-actor function reached
through animation-script opcode `32` — the same
`anim_op_spawn_sub_actor_from_table_slot` mechanism documented for Zombie
Dragon's `fire_func` and Gigantes' `aoe_cast_state_machine`,
`MonsterRecord+0x28`'s custom slots — see "Monster record layout" above)
and reported a live register-reuse bug at party slot 2. **The user tested
this against a live savestate (`Sonya.State`) and the reduction was not
present.** Root cause, confirmed directly from `calc_rune_element_attack_
damage`'s own decompilation: the register that fork identified as the
loop counter, `$s0`, is **not** a caller-leftover value at all — the
function immediately recomputes it locally (`attacker.MGC - target.MGC`,
the damage base) before the switch even runs. The only register genuinely
left unwritten on the fallthrough path is `$s1` (see above). In Sonya's
own caller, `$s1` is a fixed sub-actor struct pointer, constant across the
whole loop — unrelated to party position — so the bug cannot fire there
regardless of which slot is being hit. (An actual Water-Rune wearer would
still take halved damage from this spell, but that's the *real*,
intentional elemental-resistance check — category 2 == element 2 by
deliberate design, exactly analogous to Resurrection Rune legitimately
resisting Zombie Dragon's Fire Breath — not the register-reuse bug.)
Sonya's AoE has accordingly been removed from the bug table above; it's
a confirmed real elemental attack, just not a buggy one.

This also means the byte-pattern sweep's method has two independent gaps,
not one: (1) it only searches ordinary compiled functions, so any attack
routed through a sub-actor slot indirection (like Sonya's) is invisible to
it — Sonya's Water spell was found by chasing that pattern manually, not
by the sweep; (2) even when a call site *is* found, assuming its loop
register is automatically "the" vulnerable one (rather than checking it's
specifically `$s1`) produces false positives, as it just did. Neither gap
has been closed for the rest of the table — the "Unnamed, `vf2.bin`
cluster" rows and anything the sweep reported zero hits for have not been
re-checked for hidden sub-actor-slot attacks, and every remaining `$s1`
row above is still just "structurally plausible" pending its own live
test.

This was found via: `calc_rune_element_attack_damage` is only ever reached
indirectly through `RngCallbackTable` slot `86` (never a direct `jal`), so
a plain xref search on the function's own address misses every call site —
the original 11 rows were found one boss at a time. A byte-pattern sweep
(searching for the slot-86 dereference `lw v0,0x158(v0)`, encoded
`58 01 42 8c`) across all 38 currently-loaded overlay/monster programs
found the rest. Several overlays (`va2.bin`, `va3.bin`) are effectively
undisassembled by Ghidra (no recovered function boundaries), so apparent
hits there were confirmed false positives (garbage alignment) and are
excluded above.

**What is `element=8`?** Confirmed live in the disassembly as a hardcoded
immediate at both originally-documented sites: `dragon_overlay.bin @
0x800113c8` (`ori a2,zero,0x8`) and `vzv.bin @ 0x800157b8` (`ori a2,zero,
0x8`) — not a misread or a computed value. The wider sweep found it
recurring at 3 more confirmed genuine-loop sites (Magic Shield, Banshee,
one `vf2.bin` site) plus Siren (register unresolved) — `8` is by far the
most frequently reused out-of-range `element` value, more than any
in-range one.
It is still **not a recognized in-game element ID**: the rune-category
switch in `calc_rune_element_attack_damage` only ever assigns categories
`1`-`7` (all seven real categories — Fire/Water/Earth/Lightning/Wind/
Resurrection/Soul-Eater — are already used), and the codebase's actual
"no element" sentinel elsewhere (`g_abWeaponTypeToElement`) is `0xff`, not
`8`. Because `8` exceeds both the max rune category (`7`) and the max party
slot (`6`), it can never trigger either resistance mechanism — the halving
never fires and the attack always lands at full formula value. Functionally
this makes it behave like an "unresistable" attack, and its recurrence
across ≥6 independent call sites now makes that look more like a
deliberate, reused "always full damage" constant than a one-off accident —
but there's still no evidence the game formally defines `8` as a named
element; it's more likely a convention shared across these scripts' shared
template code — the in-range `element` values otherwise look hand-picked
per-move with no consistent pattern (`6, 1, 4, 3, 5, 1...`), while `8`
alone shows up repeatedly, consistent with it being copy-pasted as an
"always full damage" default rather than assigned per-monster like the
others.

### Multi-target attacks: `battle_enemy_attack_advance_multitarget`

If the attacker's class/equip byte (`class_ptrs[attacker]->+0x1c->+0x4c`)
`== 0x0e` (14, Double-Beat Rune), `battle_execute_enemy_attack`
(`0x800f491c`) sets bit `0x4000` on the attacker's own
`combatant_rec+0x4a`. **`battle_enemy_attack_advance_multitarget`**
(`0x800f7c58`) checks that bit each cycle: if set (and the shared "uses
available" counter at `+0x2c` isn't exhausted), it advances `TargetIdx` to
the next valid combatant and signals "continue."
**`battle_enemy_attack_multitarget_continue`** (`0x800f5cd0`) is the
per-tick driver: it re-invokes `battle_execute_enemy_attack` against the
newly-advanced target, repeating until every living combatant has been
attacked once, and plays the animation using script-table slot `[4]`
(rather than the ordinary attack's slot `[1]`).

`scripts/CaptureEnemyMoveResults.lua` captures (move type, target,
damage-per-combatant) for an enemy's turn across candidate seeds given a
savestate positioned at/before that turn. It reports raw
`ActionType`/`AbilitySlot`/`TargetIdx` and observed HP deltas; it does not
compute a predicted damage value from the formula above.

## Monster record layout (`attack_data_table[Id]`, `MonsterRecord`)

- **`+0x00`** — Name: Charmap-encoded, null/space-padded (same convention as
  the Rune/Unite tables).
- **`+0x10`** — Level (u8)
- **`+0x11`** — Formation-slot occupancy footprint (u8): See "Formation
  management" above.
- **`+0x12`** — HP (u16)
- **`+0x14`** — PWR (u16)
- **`+0x16`** — SKL (u16)
- **`+0x18`** — DEF (u16)
- **`+0x1a`** — SPD (u16)
- **`+0x1c`** — MGC (u16)
- **`+0x1e`** — LUK (u16)
- **`+0x20`–`+0x25`** — **Elemental affinity table (6 bytes, one per
  element)** (Ghidra: `MonsterRecord.aElementalAffinity[6]`;
  `outputs/Bestiary.json`: `elementalAffinity`): Confirmed via a literal
  debug `printf("ZOKUSEI %d AISYO %d\n", i, byte)` (Japanese: "Element %d
  Affinity %d") found inside `apply_elemental_multiplier` itself, looping
  `i` from 0 to 5 over exactly this range. Byte values: `0`=normal, `1`=weak
  (`apply_elemental_multiplier` doubles damage), `2`=resist (halves damage),
  `3`=immune (zeroes damage) — same 0–3 legend
  `apply_elemental_multiplier`'s own doc section already used for the
  "target's compatibility byte." Element-index-to-slot mapping, read off
  that function's own 21-caller table below: `0`=Fire, `2`=Earth,
  `3`=Lightning, `4`=Wind, `5`=Resurrection; index `1` (Water) is inferred
  by elimination — every Water-rune spell in the reference data is ally-
  targeted and never reaches this lookup, so no caller has been observed to
  confirm it directly. Element `7` (Dark/Soul-Eater) bypasses this table
  entirely (see `apply_elemental_multiplier` below) and isn't stored here.
  Every one of the 124 scanned `outputs/Bestiary.json` records has all 6
  bytes in the 0–3 range, confirming this is one packed array rather than
  two independent scalar fields (this straddles the boundary between the
  `outputs/Bestiary.json` scanner's separately-named `unknown20`/`unknown24`
  fields — `unknown20` is bytes 0–3 of this table, `unknown24` is bytes 4–5
  — an artifact of the scanner reading a u32 then a u16 rather than 6 raw
  bytes; both names should be treated as this one table going forward).
- **`+0x26`** — Species capability flags (u16) (Ghidra:
  `MonsterRecord.wSpeciesFlags`; `outputs/Bestiary.json`: `speciesFlags`): A
  multi-bit flags word, bits counted from 0. Bit `0`: a party target may
  counter this monster's missed attack (`check_dodge_counter`). Bit `1`:
  counters a party member's missed attack against it, if the attacker's
  range isn't Long (set on 38 of 122 monsters). Bit `2`: a party member's missed attack against it stays a
  plain miss; with neither bit `1` nor bit `2` the miss is thrown away and
  the attack hits. Bit `15`: as a target, skips the hit roll and forces the
  miss branch (only both Neclord fights). Bit `3`, read on the *attacker's
  own* species, turns its failed hit roll into a hit. All in "On a miss or
  a hit: dodge and counter" above. `0x4000` (bit 14): **instant-death immune** —
  a 94-of-94 exact match against Suikoden-RNG-lib's `instantDeathImmune`
  field, and directly in the disassembly, both Soul Eater instant-death
  spells (`Deadly Fingertips`, rune level 1, `0x80114300`, immunity check at
  `0x80114328`; `Hell`, rune level 3, `0x80116078`, immunity check at
  `0x801160b0`) contain the byte-identical sequence `lhu MonsterRecord+0x26;
  andi 0x4000; bne (skip effect if set)`. Set on Zombie Dragon, Gigantes,
  Dragon, Leonardo, Kanak, Crystal Core, Shell Venus, Sonya Shulen, Ain
  Gide, Assassin, Anji, both Neclord fights, and all 3 Golden Hydra heads.
  `0x20` (bit 5): **flying** — `Voice of Earth` (Earth rune level 2,
  `0x8011349c`) reads this bit and, if set, skips the candidate entirely
  (bypassing both the busy-flag check and the
  `apply_elemental_multiplier`/damage call — never even considered valid,
  not merely resisted). Set on 15 of 124 scanned monsters: Black Elemental,
  Demon Sorcerer, Devil Armor, Eagle man, Ghost Armor, Gigantes, Hawk Man,
  Holly Fairy, Holly Spirit, Larvae, Mosquito, Roc, Simurgh, Sorcerer,
  Sunshine King — casters, fairies, and levitating constructs, not just
  winged animals (Flying Squirrel, Crow, and Wyvern do *not* have this bit).
  `Earthquake` (the other Earth-element spell, rune level 4, `0x80111ce8`)
  has no such exclusion and hits flying monsters normally.
- **`+0x28`** — Pointer to a 9-entry pointer table (Ghidra:
  `MonsterRecord.pAttackScriptTable`; `outputs/Bestiary.json`:
  `actionScriptTableAddress`): Catalog of this monster's own
  attack/animation scripts (bytecode for the `play_attack_animation` opcode
  interpreter); every monster's 9 entries are unique. 6 slots have a fixed,
  universal role, found by tracing every caller of `play_attack_animation`
  (`battle_execute_player_attack`, `battle_execute_enemy_attack`,
  `battle_check_counter_attack`,
  `counter_attack_reprisal`/`_continue`/`_apply_damage`,
  `battle_check_crit_and_branch`, `critical_hit_apply_damage`,
  `ordinary_miss_continue`, `apply_covered_attack_damage`,
  `apply_uncovered_attack_damage`,
  `battle_enemy_attack_multitarget_continue`): `+0x04` primary action
  script; `+0x08` hit script; `+0xc` evade/miss-reaction script (shared by
  the counter-attack windup and an ordinary no-consequence miss, not
  counter-specific); `+0x10` return-to-idle/end-of-multi-target-sequence
  script; `+0x14` counter-attack hit-reaction script; `+0x20` critical-hit
  hit-reaction script, played instead of `+0x08` when `check_critical_hit`
  succeeds (found via `critical_hit_apply_damage`, which also confirms
  critical hits deal exactly **3× normal physical damage**, no other
  scaling). The remaining 3 slots (`+0x00`, `+0x18`, `+0x1c`) are a
  **monster-custom pool of auxiliary sub-effect scripts**: animation-script
  opcode 32 (`anim_op_spawn_sub_actor_from_table_slot`, `0x800e5328`) reads
  a script-embedded, arbitrary slot index out of the invoking monster's own
  bytecode, looks up `pActionScriptTable[thatIndex]`, allocates a free "sub-
  actor" VFX slot (`find_free_sub_actor_slot`, 19 slots independent of the
  normal combatant roster), and installs the resolved pointer as that sub-
  actor's own script cursor. A resolved slot can hold real bytecode or a
  native compiled function pointer — e.g. Zombie Dragon's slot 6 (`+0x18`)
  is `zombie_dragon_fire_func_state_machine` (`enemy_ai_overlay.bin
  0x80011cdc`) and Gigantes' own slot 6 is `gigantes_aoe_cast_state_machine`
  (`vc3.bin 0x800116f0`) — both native functions, not bytecode. There's no
  universal "slot 0 always means X" — each monster's own table contents
  (`outputs/Bestiary.json`'s `actionScriptTableAddress`) is the only way to
  know what a specific monster keeps in these 3 slots.
- **`+0x2c`** — Pointer to the monster's **battle sprite resource table**
  (`spriteResourceTableAddress` in `outputs/Bestiary.json`, renamed from
  `secondaryTableAddress`; Ghidra field
  `MonsterRecord.pSpriteResourceTable`, renamed from `pSecondScriptTable`):
  Consumer: `battle_load_enemy_combatants` (`0x800dee44`), called once from
  `battle_init_sequence` (`0x800de7a0`) at battle setup only, never during
  round resolution. For each enemy slot, passes `+0x2c` directly into
  `build_sprite_poly_resource` (`0x800e1e3c`) — allocates `POLY_FT4` (PSX
  GPU flat-textured-quad, the standard 2D-sprite rendering primitive;
  Suikoden 1's enemies are pre-rendered sprites, not 3D models) primitive
  arrays sized from a per-entry frame count read via the table's 4th pointer
  (a 16-entry pointer array) — then into `apply_sprite_texture_coords`
  (`0x800e7468`), which fills in each primitive's real `tpage`/`clut`/UV
  coordinates from that same pointer array. Both results cache into
  `EnemyData+0x84`/`+0x88` (`pAnimResource`/`pAnimResource2`) and are never
  referenced by address again. Layout: 32-byte header (2 counts, packed
  flags `u32`, 4 pointers, a scale-like `u32`, a per-monster `u16`, constant
  sentinel `u16` `0x7fbc`) — a per-monster sprite-sheet/frame descriptor,
  not VFX/particle data. `queue_texture_clut_upload` (`0x800c3500`) uploads
  each distinct monster ID's CLUT/texture pages once per encounter (a dedup
  guard skips repeats) ahead of the per-instance polygon setup above.
- **`+0x30`** — AI function pointer: The enemy AI action-selection function.
- **`+0x34`** — `wGoldDrop` (u16): Money ("bits") dropped, summed across
  living enemies at the end of an enemy turn; doubled by Prosperity Rune
  (see above). Has a bit-0 "compressed large value" branch (`(raw/10)*100`
  when the low bit is set).
- **`+0x36`–`+0x3b`** — **3 item-drop slots** (Ghidra: `bDropItemId1`/`bDrop
  Chance1`/`bDropItemId2`/`bDropChance2`/`bDropItemId3`/`bDropChance3`;
  `outputs/Bestiary.json`: `itemDrops[]`): Each pair is one byte item ID +
  one byte drop chance — 3 independent drop slots per monster, matching this
  project's own `lib/Battle.lua:readEnemyTable`'s existing `Drops` loop
  (`enemyRawData[53 + j*2]`/`[53 + j*2 + 1]` for `j=1..3`). Confirmed via
  `lib/Battle.lua:getItemName`: all 104 distinct item IDs used across all
  124 records' drop slots resolve cleanly to real items — Zombie Dragon →
  Lightning crystal, Simurgh → Thunder crystal, Death Machine → Steel
  shield, Crow → Bandanna, Holly Fairy's 3 slots → Nameless urn / Magic robe
  / Needle, and IDs `94`/`98` → Sound setting 3 / Window setting 3 (genuine
  menu-config items, not noise). `itemId=0` means no drop configured there —
  only 95/124 records have at least one populated slot, the same "not every
  monster has one" pattern `wGoldDrop` also shows.
  `spriteOffsetX`/`spriteOffsetY` (`+0x3c`/`+0x3e`) are the per-monster 2D
  battle-sprite pixel-offset nudge — see the live `EnemyData` section below.
  **Consumer**: `battle_process_enemy_turns` (`0x800e9940`). For each enemy
  actually killed (not fled): sums `MonsterRecord+0x34` gold (with the bit-0
  compression convention) into a running total; separately, picks a
  **uniformly random slot** (`rand()%3`) from that enemy's
  `+0x36`/`+0x38`/`+0x3a` triplet, and if that slot's item ID is nonzero,
  rolls `rand()%100 < chance` — the chance byte is a direct percentage
  (0–100). **At most one item drops per entire battle**, not one per monster
  — the moment any enemy's roll succeeds, every subsequent enemy is skipped.
  The same function implements Prosperity Rune: for each party member whose
  class data has a specific flag byte set, total gold is left-shifted by 1
  (doubled), stacking multiplicatively across multiple holders.

Neither `+0x28` nor `+0x2c` (nor `+0x20`–`+0x25`'s elemental affinity table,
nor `+0x26`'s species capability flags) encode which "shape" of
target-scan/move-gate logic a monster's AI uses — that information only
exists in the AI function's own compiled instructions.

## EXP award formula: `battle_calc_party_exp_award` (`0x800e9744`)

Renamed from a wrong earlier identification (`battle_calc_enemy_aggro`, believed to compute an
enemy-targeting threat score). It's actually the EXP formula: `DAT_80179fd0`, its own output buffer,
is allocated only once, at battle end inside `battle_results_init_and_process_enemy_turns` — it
doesn't exist during normal rounds, and `battle_select_enemy_target` (the function this was claimed
to feed) never references it anywhere. Verified byte-for-byte against a known community-derived
formula/table.

**Formula**, computed once per living party member at battle end:
1. For every enemy present in the encounter, look up `g_anExpByLevelDiffTable[clamp(enemyLevel −
   partyMemberLevel, −14, +15)]` (`0x8016bdc8`, 30 `int` entries) and sum the results.
2. Divide the sum by the (living) party member count.
3. Clamp the result to a minimum of 5.
4. Double it if the party member has Fortune Rune equipped (`Rune.Id == 0x16`).

**The table, confirmed byte-for-byte via a raw memory read** (index 0 = level-diff −14 ... index 29 =
level-diff +15, i.e. reversed from how it's usually presented in strategy guides, high-diff-first):

| Enemy Lv. vs character | EXP |
|---|---|
| `>+14` | 10000 |
| `+14` | 9700 |
| `+13` | 9300 |
| `+12` | 9000 |
| `+11` | 8500 |
| `+10` | 8000 |
| `+9` | 7500 |
| `+8` | 6900 |
| `+7` | 6000 |
| `+6` | 5100 |
| `+5` | 3900 |
| `+4` | 2600 |
| `+3` | 1600 |
| `+2` | 900 |
| `+1` | 400 |
| `±0` | 200 |
| `−1` | 160 |
| `−2` | 120 |
| `−3` | 90 |
| `−4` | 70 |
| `−5` | 50 |
| `−6` | 30 |
| `−7` | 20 |
| `−8` | 15 |
| `−9` | 10 |
| `−10` | 7 |
| `−11` | 5 |
| `−12` | 3 |
| `−13` | 2 |
| `<−13` | 1 |

The result is staged per party member into `DAT_80179fd0+0x10+idx*4`, later consumed by
`battle_results_award_exp_and_levelup` (`0x800e8914`), which applies it in a visually-animated
"counting up" fashion (16 EXP per tick) against each character's own EXP total (`classData+0x1c+0xe`),
carrying over past 1000 into a level-up (`level_up_stat_growth`) exactly once per 1000 crossed.

## Live `EnemyData` fields: idle sway animation and special-move cast phase (`+0x10`–`+0x5b`)

None of the three battle-init functions (`battle_load_enemy_combatants`,
`battle_load_party_combatants`, `FUN_800df144`) write into this range — it's
populated by per-frame logic instead.

- `+0x10` (`bIdleSwayTimer`, u8): decrements every frame, resets alternating
  `59`/`60` (a ~1s idle loop at 60fps), flipping the sign of every field
  below on each reset.
- `+0x1d` (`bIdleSwayDirFlag`, s8): flips between `+96`/`-96` in lockstep.
- `+0x1e` (`nSIdleSwayFlagA`, s16): flips between `0`/`-1`, same timing.
- `+0x34` (`nSIdleSwayZStep`, s16): flips between `+1365`/`-1365`; confirmed
  added into `nRefPosZ` (`+0x70`) every frame, producing a smooth ping-pong
  Z-axis sway between `±40960` (`±10.0` in this game's fixed-point scale) —
  Gigantes' idle forward/backward rocking motion.
- `+0x36` (`nSIdleSwayFlagB`, s16): flips `0`/`-1` in the same lockstep as
  `+0x1e`; no direct consumer confirmed.
- `+0x13`, `+0x16`–`+0x17` (s16, `-8` for Gigantes): static across the
  traced window — likely per-monster sway config (amplitude/axis/baseline).
- `+0x11`–`+0x12`, `+0x14`–`+0x15`, `+0x18`–`+0x1c`, `+0x1f`–`+0x33`,
  `+0x37`–`+0x3f`: stayed `0` throughout an idle trace — likely only used
  in other animation states (attacking, hit-reaction, death).

`+0x42`–`+0x5b` is a **special/AOE-attack cast-progress block**, confirmed
live against Gigantes' own AOE attack across 6 independent occurrences:

- **`bSpecialMoveCastPhase`** (`+0x42`, u8): `0` at rest; ticks `1→2→3`
  across the windup (~20 frames apart), jumps straight to `0x64` (100, an
  impact/resolved sentinel) the exact frame AOE damage lands on multiple
  party members simultaneously, resets to `0` for the next cycle.
- **`pVfxEffectHandler`** (`+0x54`, a genuine function pointer, not raw
  data): populates when the cast phase leaves `0`, clears back to `0` on
  the frame the phase jumps to `100`. The same struct offset is confirmed
  elsewhere to hold a function pointer: `anim_op_spawn_sub_actor_from_
  table_slot` (animation-script opcode 32, `0x800e5328`) sets a
  freshly-spawned sub-actor's own `pVfxEffectHandler` from a 14-entry
  function-pointer table (`DAT_8016bb70`, every entry in `0x800f0000`–
  `0x800f4000`) indexed by a script-embedded argument.

**Gigantes' own AOE cast chain, fully decoded.** Her own `MonsterRecord+0x28`
table (`0x80048958` in `vc3.bin`) has 9 slots; slot 6 (`+0x18`, one of the 3
"monster-custom" slots) is a **native compiled function**, `0x800116f0` —
not bytecode, the same pattern as Zombie Dragon's own fire state machine:

- `gigantes_aoe_cast_state_machine` (`0x800116f0`) drives
  `bSpecialMoveCastPhase` directly: phase 0 allocates a 20-byte scratch
  context (stashed at `EnemyData+0x58`), phase 1 counts a fixed 20-frame
  windup down to 0, phase 2 arms a self-rearming per-frame callback
  pointer at `ctx+0x10` and advances to phase 3, phase 3 calls whatever's
  at `ctx+0x10` every frame until it goes NULL (→ phase 99 cleanup → phase
  100, which clears `pVfxEffectHandler`).
- The `ctx+0x10` chain, each tick rearming itself to the next:
  `gigantes_aoe_init_and_arm_impact` (`0x80011a58`, allocates the real
  144-byte effect struct at `ctx+0xc`, fires 4 unidentified sound/VFX-cue
  subsystem calls) → `gigantes_aoe_wait_for_cue` (`0x80011b34`, polls
  until the cue finishes playing) → `gigantes_aoe_spawn_particle_ring`
  (`0x80011bbc`, one-shot: seeds a 24-particle explosion ring's
  angle/position from Gigantes' own `nRefPosX/Y/Z`) →
  `gigantes_aoe_particle_tick_and_apply_damage` (`0x80011d70`, the
  repeating per-frame driver: expands the ring for 64 frames, then **at
  tick 20 calls `BattleState+0x1258` vtable slot `+4` once per living
  party member — the actual AOE damage-application call**, passing
  `(targetSlot, attackerEnemyIndex, &DAT_80041d98)` where the last
  argument is presumably the move's own damage/element data block (not
  yet decoded); an unidentified per-target follow-up fires at tick 63;
  then it tears the ring down and clears `ctx+0x10`, letting the state
  machine detect completion and advance to phase 99/100).

**`bUnk_0x43` and `aUnk_0x44` (16 bytes): very likely genuinely unused
padding.** Traced every function in Gigantes' entire AOE cast chain (5
functions) and Zombie Dragon's independent Fire Breath chain
(`zombie_dragon_fire_func_state_machine` and its own 4-function tick chain,
`enemy_ai_overlay.bin`) end-to-end: neither writes `EnemyData+0x43` or
`+0x44`..`+0x53` at all — both chains keep 100% of their own scratch state
in heap-allocated buffers off `EnemyData+0x58` (a 20-byte context and, for
Gigantes, a further 144-byte effect struct hanging off it; 90 particle
records + a head-model buffer for Zombie Dragon). Two structurally
independent monsters' own elaborate special-move chains both avoiding these
bytes is strong (though not exhaustive — the other 122 monsters' own custom
slots weren't checked) evidence they're simply unused padding in this
build, not a live per-monster special-move field. `aUnk_0x58` itself
remains otherwise unconfirmed. Confirmed via the same trace that ordinary
physical attacks, ordinary hits, and (with party SKL rigged to a real,
in-spec low value of 5 to maximize miss chance against the documented
`calc_hit_chance` 60% floor) misses/evades **do not** touch this block at
all — it's specific to whatever "special move" mechanism the
`MonsterRecord+0x28` script table's opcode-driven sub-effects trigger, not
ordinary combat.

## AI/enemy move selection

The AI function pointer at `attack_data_table[Id]+0x30` is invoked from
`battle_dispatch_current_actor_action`. Story-boss and many regular-enemy
AI functions live outside `main.exe`, in each monster's own small overlay,
rather than in a shared generic routine — every boss and regular enemy
traced has its own hand-written AI function, though several reuse the same
target-scan/move-gate templates (see below).

### Target-selection template (used by most monsters)

```
for each party member idx in formation order (1..PARTY_COUNT):
  if formationPos(combatant_rec[idx]+0x44) < 4          -- front 3 slots only
     and combatant_rec[idx]+0x45 == 0                    -- alive/valid
     and not busy(enemy_data[idx]+5):                    -- not mid-reaction
    roll = RNG2()                                        -- advances the shared LCG
    if roll % 100 > 50:                                  -- ~49% accept chance
      target = idx; break
if no target accepted this pass: retry next tick (fresh rolls, nothing carried over)
```

Only the front 3 formation slots are targetable by this template. Dead or
back-row members are skipped at zero RNG cost — no `rand()` call happens
for them. A front-row member who's merely busy is also skipped at zero
cost. Retrying costs extra frames but never extra unaccounted RNG advances.
The formation always keeps at least one living member in the front row
(characters automatically move up from the back row when a front-row
member dies), so this scan can never permanently stall while anyone in the
party is alive.

### Zombie Dragon (`enemy_ai_overlay.bin` / `vb5g.bin`, `0x80012968`)

```
-- Target selection: the shared template above.

-- Move selection, once target is locked:
if roundCounter (battle_base+0x4) == 1:
  move = FireBreath                                      -- guaranteed on round 1
else:
  roll2 = RNG2()
  move = Attack     if (roll2 * 100) // 32767 < 0x47      -- ~71% chance
  move = FireBreath otherwise                             -- ~29% chance
```

`RNG2()` means: advance `Address.RNG` one LCG step, then take `getRNG2` of
the new value — the same shared RNG stream every other system in this game
uses, reached via an indirect cross-overlay call back into `main.exe`
(`*(battle_base+0x1258)` for the target-roll, `+4` for the move-choice
dispatch). Ghidra addresses (in `enemy_ai_overlay.bin`):
`zombie_dragon_ai_select_target_and_move` = `0x80012968`,
`zombie_dragon_ai_await_target_then_fire_breath` = `0x80012b64`.

Ported to `lib/Enemies/ZombieDragon.lua`'s `simulateMoveSelection(seed,
numCandidates, roundCounter)`. The seed to hand it is the RNG state at the
exact frame Zombie Dragon becomes the active actor (not the raw
battle-start seed) — matching every `simulate<X>` function's own convention
of starting right at the decision's first roll.

Zombie Dragon has exactly two attacks: a single-target physical attack,
and Fire Breath, which hits every living party member. The single-target
Attack path goes through the ordinary multi-target mechanism described
above; Fire Breath's actual damage is computed by a separate mechanism —
Zombie Dragon's own `fire_func` subsystem (catalog slot 6 of her 9-entry
attack/script table, distinct from slot 1 = normal attack and slot 4 =
per-hit continuation animation), which calls `calc_rune_element_attack_
damage` directly (see above) rather than going through `calc_damage`. This
subsystem's own tick counter, once past 249 (~4 seconds into the effect),
loops every living party member and applies the MGC-based formula per
target.

#### Fire Breath timing (live-measured 2026-09-26)

`scripts/CaptureFireBreath.lua`, `ZombieDragonStart.State` (round 1, so
Fire Breath is guaranteed), 3 seeds, no memory edits. The chain:

1. `zombie_dragon_ai_await_target_then_fire_breath` (`0x80012b64`) waits
   until no living party member is busy (no RNG), then plays script
   `0x80050414` on Zombie Dragon itself. Call that tick **T0**.
2. The script: busy 1, anim 7 (31 frames), flag 0x1, anim 8, opcode 35
   installs table slot 6 = `zombie_dragon_fire_func_state_machine`
   (`0x80011cdc`), then waits (opcode 31) for its phase 99; then anim 9,
   flag 0x4 and the busy clear.
3. The handler's phase 2 runs a sub-callback kept in its working buffer
   (`EnemyData+0x58 -> +4`): `vfx_setup` (`0x80011e38`) -> `wait_for_cue`
   (`0x80011f14`) -> `particle_spawn` (`0x80011f9c`) -> `tick_state_machine`
   (`0x800121a8`).

| T0+ | Event |
|---|---|
| 0 | Fire Breath script starts, busy set |
| 30 | flag 0x1 (miss / counter point) |
| 39 | `fire_func` installed (phase 0, then 1) |
| 40 | `vfx_setup` |
| 41 | `wait_for_cue` starts |
| 52-55 | cue done; `particle_spawn` (one call) |
| S = 53-56 | `tick_state_machine` starts |

`wait_for_cue` polls an async cue (`*(battle+0x1258)+0x9c`, most likely a
sound / CD stream) and is the only step whose length isn't fixed: 14, 12
and 11 ticks across the three runs. Everything after it is a fixed offset
from S:

| S+ | Event |
|---|---|
| 94 -> 128 | wave 1 busy (reaction script, position group) |
| 134 -> 168 | wave 2 busy |
| 166 -> 200 | wave 3 busy |
| 250 | damage rolled for every living party member, same tick |
| 251 | HP committed (damage applied in the animation pass) |
| 317 | tick machine done, `fire_func` phase 99 |
| 338 | Zombie Dragon's busy clears |

| Run | Cue wait | S | Damage roll | Zombie Dragon free |
|---|---|---|---|---|
| 1 | 14 | T0+56 | T0+306 | T0+394 |
| 2 | 12 | T0+54 | T0+304 | T0+392 |
| 3 | 11 | T0+53 | T0+303 | T0+391 |

- **Waves.** `particle_spawn` sorts each party member into a group by
  their position relative to Zombie Dragon (`EnemyData+0x6c >> 12`: below
  -30, below 30, else), and the tick machine plays the cosmetic hit
  reaction (`0x8004fea0`) on each group in turn. In this fight wave 1 was
  McDohl, wave 2 Gremio / Camille / Tai Ho, wave 3 Viktor / Cleo. Each
  member is busy only during their own wave, all well before the damage,
  so the party is idle when it lands.
- **Damage.** One `calc_rune_element_attack_damage` `rand()` per living
  party member, all on S+250, through the pending accumulator (committed
  on S+251). See the Dragon / Fire Breath formula sections for the damage
  itself.
- **Before T0** the AI's wait for a non-busy party costs no RNG (23 ticks
  in run 1).
- **For a sim:** Fire Breath isn't in Suikoden-RNG-lib's
  `ENEMY_ATTACK_TIMINGS` (that table is the basic Attack). Model it as
  S = T0 + 42 + cue wait (11-14 observed), damage at S+250, Zombie Dragon
  free at S+338, and each wave's busy window as above.

### Story boss AI roster

**Boss / file / address / target scan**:

| Boss | File | Address | Target scan |
|---|---|---|---|
| Zombie Dragon | `vb5g.bin` | `0x80012968` | front-row only |
| Golem | `va4.bin` | `0x80010ea4` | front-row only |
| Gigantes | `vc3.bin` | `0x8001186c` | front-row only |
| Shell Venus | `vs1.bin` | `0x800178e4` | front-row only |
| Sonya Shulen | `vs1.bin` | `0x80018788` | front-row only |
| Ain Gide | `vac.bin` | `0x80013b1c` | front-row only |
| Varkas | `va7.bin` | `0x800103b0` | front-row only |
| Pirates [1] | `vb8.bin` | `0x80010004` | front-row only |
| Neclord [2] | `ve1.bin` | `0x80013d18` | front-row only |
| Assassin | `vb5a2.bin` | `0x8001789c` | front-row only |
| Sydonia | `va7.bin` | `0x8001234c` | **all 6**, not just front row |
| Queen Ant [3] | `va7.bin` | `0x80010ae0` | none (self/AOE) |
| Crystal Core | `vf2.bin` | `0x800199c8` | front-row only [5] |
| "Dragon" [4] | `vc61.bin` | `0x80012594` | front-row only |

**Boss / move**:

| Boss | Move |
|---|---|
| Zombie Dragon | round-dependent [6] |
| Golem | ~71% Attack / ~29% special |
| Gigantes | ~51% Attack / ~49% special |
| Shell Venus | ~51% / ~49% |
| Sonya Shulen | Attack / Water AoE special [13] |
| Ain Gide | ~51% / ~49% |
| Varkas | always plain Attack (no special move) |
| Pirates [1] | always plain Attack |
| Neclord [2] | 3-move mix [9] |
| Assassin | round-dependent [8] |
| Sydonia | row-dependent [7] |
| Queen Ant [3] | HP-reset + 2-move mix [10] |
| Crystal Core | Attack / unidentified special [11] |
| "Dragon" [4] | Lightning / Fire Breath override [12] |

1. Anji, Kanak, and Leonardo all share this same AI address.
2. 2 appearances, same logic, different compiled addresses:
   `ve1.bin`/`0x80013d18` and `ve3.bin`/`0x8001675c`.
3. Mt. Seifu's scripted fight, lvl15 HP7000 — distinct from Seek Valley's
   random-encounter Queen Ant.
4. HP 6000, distinct from Zombie Dragon and from Golden Hydra, the true final
   boss. File is a data section; code read from the live overlay dump
   `dragon_overlay.bin`.
5. Front-row only, unless a global flag is set, in which case no scan at all.
6. Round 1: Fire Breath guaranteed; else ~71% Attack / ~29% Fire Breath.
7. Fully determined by the chosen target's row: front row → always special
   (`calc_damage × 4 / 3`, can't miss; see "Sydonia's special move"),
   back row → always plain Attack.
8. Round > 2: always special; else ~51% Attack / ~49% special.
9. 3 moves: AoE Wind (~49.00%), single-target physical Bats (~26.01%,
   guaranteed Poison), AoE Lightning (~24.99%) — see below.
10. Resets own HP to full every turn, then ~51.0% her own AoE Earth attack
   (hits every living party member) / ~49.0% attempts to command every other
   living enemy to attack — see below.
11. Always plain Attack on the scanned branch; unidentified special state on
   the flagged branch.
12. 2 moves: Lightning (single-target) normally; a per-frame callback rolls
   ~51%/~49% once a target locks, overriding to Fire Breath (AOE) — see below.
13. ~51% Attack (her plain physical) / ~49% special (her Water AoE spell,
   `element=2`, see the bug table above) — live-validated 2026-09-17, see
   below.

**Golden Hydra** — Level 75, HP 10000, PWR 570, SKL 105, DEF 55, SPD 75,
MGC 420, LUK 80, gold 3392 — is the true final boss (file `vzv.bin`,
`data/15_area.z`), distinct from and much larger than "Dragon" (HP 6000)
and Zombie Dragon (HP 3700). Her overlay has 3 `calc_rune_element_attack_
damage` call sites — more than her 2 known moves, so at least one move
likely has 2 damage phases.

`vc3.bin` hosts multiple monsters: CrimsonDwarf (`0x80010034`) and Gigantes
(`gigantes_ai_select_target_and_move`, `0x8001186c`). Cross-referencing
against `lib/EncounterTable.lua`'s `DWARVES_VAULT` roster ("Death Machine,
Crimson Dwarf, Death Boar, Death Machine") and charmap-searching `vc3.bin`
for those names confirms both Death Machine variants also live in
`vc3.bin` (`0x800420e0`, `0x80043618`).

### Sydonia's special move

Corrected 2026-09-27 from the `va7.bin` decompile and the static walker.
Earlier notes called the special's follow-up an unreachable
"counterattack". It isn't: it's where the special deals its damage.

**Live-confirmed the same day** (`scripts/VerifySydoniaSpecial.lua`,
`VarkasSydoniaUniteTest.State`, 4 seeds × 3 rounds):

- All 11 special hits (front-row targets) matched
  `floor(calc_damage × 4 / 3)` using the first `rand()` of the damage
  frame. None matched plain `calc_damage`.
- The impact bit was set 79 frames after her `ActionTag` flipped, and the
  damage landed on the next frame, as the walker predicts.
- The one back-row hit was a plain Attack: impact at +39 (the walker's
  slot 1 value), damage = plain `calc_damage`.
- Every target she hit was Defending, so the halving-before-×4/3 order is
  confirmed, but a non-Defending special hit wasn't captured.

`sydonia_ai_select_target_and_move` (`0x8001234c`):

```
target scan: every party member (all 6 rows), in formation order:
    alive and not busy -> ★ roll; accept if roll % 100 > 50
    nobody accepted -> return 0 (scan again next tick)
TargetIdx = target
target in the back row (formationPos > 3): return -1   -- plain Attack
★ roll; if roll % 100 < 121 (always true):
    ActionTag = 1, clear own +0x40
    play special script 0x800700c0 (target busy 8 from f0)
    own +0x50 = sydonia_special_apply_damage
    return 1
```

`sydonia_special_apply_damage` (`0x8001258c`), polled each tick as her
`+0x50` step. Her script sets her impact bit (`+0x40 & 0x2`) at f79, so it
fires on f80:

```
dmg = ★calc_damage(Sydonia, target)           -- service slot 3
apply_hp_damage_display(target, (dmg * 4) / 3)  -- service slot 4, truncating
target plays reaction 0x80064880                -- busy 8, clears 45 frames later
own +0x50 = 0
```

So the special does `floor(calc_damage × 4 / 3)`, with **no hit roll and
no crit**. It can't miss. Defend halving happens inside `calc_damage`,
before the ×4/3. The special's RNG is: the scan rolls, the one
always-passing roll, and the `calc_damage` roll at f80. Her script's
native VFX handler (`0x80011e34`) and the reaction script don't reach
`rand()`. Her script ends and clears her busy at f180.

Against a back-row target the AI returns -1, and the dispatcher runs the
enemy basic attack (`battle_execute_player_attack`): hit roll, no crit,
normal damage.

**Who she targets, and so which move she uses.** The scan walks party
members in combatant index order and takes the first one that accepts, so
earlier slots are strongly favoured. With *n* eligible members (alive, not
busy), the *k*-th is picked with probability
`0.49 × 0.51^(k−1) / (1 − 0.51^n)`; the divisor covers failed scans, which
retry next tick with fresh rolls. For the 5-member test party (back row in
slots 4 and 5):

| Slot | Chance | Move |
|---|---|---|
| #1 | 50.8% | special |
| #2 | 25.9% | special |
| #3 | 13.2% | special |
| #4 | 6.7% | plain Attack |
| #5 | 3.4% | plain Attack |

About 10% of her actions go to the back row, matching the live run (1 of
12). Front-row members who are dead or busy when she scans are skipped
without a roll, which moves the back row up the order. Nothing else
(HP, stats, Defend) affects the pick. The scan follows combatant index
while the row check reads `formationPos`; the two matched in the test
party, and a party where they differ wasn't checked.

The Bandit attack Unite (slot 18, Varkas + Sydonia on the party side) is
unrelated: its handler (`DAT_8016d2d0[18]` = `0x800fcd1c`, `main.exe`)
uses neither of these scripts.

### Dragon's move selection

Dragon has exactly two moves — Lightning (single-target) and Fire Breath
(AOE, hits every living party member):

```
loop:
  for slot in eligible front-row candidates (formation order):
    roll = rand()
    if roll % 100 > 50: target = slot; break        -- ~49% per candidate accepts
  if no candidate accepted: continue loop             -- retry the WHOLE scan fresh, new rolls
  else: break                                          -- target locked
roll = rand()
quotient = (roll * 100) / 32767
if quotient < 51:  Lightning, using `target`            -- ~51% chance
else:              Fire Breath (AOE), target ignored     -- ~49% chance
```

**Target-selection eligibility** (`dragon_ai_select_target_and_move`,
`dragon_overlay.bin @ 0x80012594`): the loop walks every party member in
formation order; only a member that is alive (`combatant_rec+0x45 == 0`)
and in the front row (`formationPos < 4`) and not busy (`enemy_data+5 ==
0`) gets a roll.

**The move-choice roll** happens in **`dragon_special_move_real_frame_
callback`** (`dragon_overlay.bin @ 0x800123b8`) — Dragon's own per-frame
animation callback, installed at `enemy_data[Dragon]+0x54` and invoked
every frame by `main.exe`'s `FUN_800e358c` once the windup completes. It's
a small state machine keyed on `enemy_data[self]+0x42`:

```
state 0:  allocate an 8-byte scratch block, zero it, advance to state 1
state 1:  THE ROLL - rand(), (raw*100)/32767 < 51 -> store dragon_lightning_path (0x80013264);
          else -> store dragon_firebreath_path (0x80012808); advance to state 2
state 2:  call whichever continuation was stored
state 99: cleanup (free the scratch block, clear the callback slot)
```

Same formula shape and divisor (`0x7fff`) as Zombie Dragon's own
Attack-vs-Fire-Breath roll, with a different threshold (51 here vs. Zombie
Dragon's 71). `dragon_lightning_path` allocates a 244-byte VFX buffer;
`dragon_firebreath_path` allocates 300 bytes. The 3 `calc_rune_element_
attack_damage` call sites in this overlay
(`dragon_special1_damage_call_element8_dormant` at `0x800113bc`,
`dragon_special2_damage_call_element1_LIVE` at `0x80012eec`, both
loop-shaped, consistent with Fire Breath's AOE hit pattern;
`dragon_special3_damage_call_element4_uncertain` at `0x800139e8`,
single-hit-shaped, consistent with Lightning) are reached further
downstream of `dragon_lightning_path`/`dragon_firebreath_path`.
Elemental-resistance "slot bug" status: `element=8` is permanently dormant
(can never match a 1-6 party index); `element=1` is live (slot 1 is always
populated, so an unhandled Rune there takes half damage from Fire Breath).

`lib/Enemies/Dragon.lua` models this as two functions matching the two
real phases: `simulateMoveSelection` (target-scan-with-retry + move-choice
roll) and `simulateLightning` (the VFX/particle phase below, taking the
seed `simulateMoveSelection` returns once resolved to Lightning).

#### Lightning's RNG cost

After the target-selection and move-choice rolls resolve to Lightning, the
attack proceeds through three phases:

1. **A 128-tick particle-spawn phase.** 30 independent "spark" line-segment
   particles each respawn (5 `rand()` calls each — X-offset, Y-offset, an
   unused point-B Z-offset, a Z-velocity, and a lifetime) whenever
   inactive, via `vfx_spawn_random_arc_particle` (`main.exe @ 0x80124040`,
   `RngCallbackTable` slot `0xe8`). A particle deactivates when either its
   random lifetime (`rand() % 0x46`, i.e. 0-69 ticks) expires, or its
   position — integrated every active tick by a random negative Z-velocity
   (`-(rand() % 5 + 5) * 4096`) inside the otherwise-RNG-free render
   function (slot `0xec`) — crosses below a fixed `-300` threshold,
   whichever comes first. The total varies because this is a real
   stochastic process (each particle's own random lifetime/velocity
   determines how many times it gets to respawn across the 128 ticks).
2. **A 124-tick phase with no further particle RNG.**
3. **Exactly one final `calc_rune_element_attack_damage` variance roll**,
   ending the attack.

Observed totals (VFX-phase calls only) range from 651 to 759 across a
16-seed sample — roughly an order of magnitude higher than naive
per-frame-polling would suggest, because many `rand()` calls can land
within a single frame's CPU execution and get collapsed into "one change"
by naive polling; the reliable method is to let the RNG **settle**
(unchanged for 30 consecutive frames) after the attack fully resolves, then
recover the exact call count by forward-simulating (LCG-step-counting)
from the start seed until it reaches that settled value.

`lib/Enemies/Dragon.lua`/`dragon_lightning_tick_state_machine`'s plate
comment (`dragon_overlay.bin @ 0x80013690`) has the full derivation;
`tests/test_Dragon.lua` for the test vectors (50 seeds for move-selection,
16 for the Lightning VFX).

#### Dragon's move timing

Live-measured 2026-09-28 (`scripts/TraceDragonTiming.lua`,
`Dragon.State`, two runs of 5 seeds × 3 rounds: 15 Fire Breaths, 15
Lightnings). In the second run Gremio's AGL was pinned to 1 so he acted
after her every time. Party Defending and idle when her turn starts. T0 = the first frame she's the
current actor; M = the move-choice roll.

Both moves start the same way:

| What | Frame |
|---|---|
| AI runs, scan rolls, `ActionTag` 1 | T+1 |
| Dragon busy 0→1 | T+2 |
| her `+0x40` bit `0x1` | T+31 |
| callback `0x800123b8` installed | T+36 |
| move roll (M) | T+37 |

In one run the AI ran a frame late (T+2), and everything after it
shifted by one.

**Fire Breath.** The damage frame drifts: the damage rolls (one per
party member, all on one frame) came at M+264 to M+268, HP committed the
next frame. Everything else is fixed relative to the damage-roll frame D:

| What | Frame |
|---|---|
| hit reaction, slot 3 (busy 8, 34 frames) | D−154 |
| hit reaction, slots 2, 5, 6 | D−127 |
| hit reaction, slots 1, 4 | D−96 |
| damage rolls / HP committed | D / D+1 |
| her `+0x42` = 99, callback cleared | D+2 / D+3 |
| Dragon busy clears | D+21 |

The reaction waves follow formation position, and all end before the
damage lands.

**Lightning.** The particle phase starts at M+15 to M+19 (the drift),
then everything is fixed relative to its first frame P:

| What | Frame |
|---|---|
| particle phase (128 frames) | P to P+127 |
| target hit reaction (busy 8, 70 frames) | P+144 to P+214 |
| damage roll (D) / HP committed | P+251 / P+252 |
| her `+0x42` = 99 | D+3 |
| Dragon busy clears | D+22 |

The last particle roll can fall a few frames before P+127: a tick where
no particle is inactive makes no rolls. Particle-phase `rand()` totals in
these runs were 680 to 760, one more than the earlier 651–759 range.

**End of her turn.** Her turn ends when her busy clears (B, about T+322
to T+329 for either move). On B+1 the roll gate is set to **30**, so the
next turn-order roll comes at B+31 and the next actor starts at B+32.
Measured on all 15 rounds of the second run. (The first run misread that
B+1 gate write as the round-end reset, since she always acted last.) If
the party is still busy when her turn starts, her AI waits before
scanning (no RNG), which pushes everything later.

#### Dragon's damage formula

Both Lightning and Fire Breath call the shared `calc_rune_element_attack_
damage` (`main.exe @ 0x800f8174`, `RngCallbackTable` slot 86) documented
above — not a separate formula. Both moves are MGC-based, not ATK-based
(Dragon's own `CombatantRec` has distinct `ATK=250` / `MGC=150`).

**Lightning** (`dragon_lightning_tick_state_machine`'s own inline call, the
final roll in the RNG-cost section above) passes `element=4`, no further
scaling beyond the shared formula's own rune-category halving.

**Fire Breath** (`dragon_special2_damage_call_element1_LIVE`,
`0x80012eec`) passes `element=1`, looping over all 6 party members, and
additionally halves the result unconditionally afterward (`iVar2/2`) — a
second, deliberate AOE-damage-reduction step on top of any elemental
halving, not present in Lightning's single-target path. Fire Breath also
carries the register-reuse resistance bug documented above: Dragon's Fire
Breath loop starts at 1 and passes `element=1`, so the bug hits slot 1 —
whichever party member occupies the first position in the hit order gets
an extra accidental 50% reduction if their rune isn't one of the explicit
cases, on top of the unconditional AOE halving.

**Fire Breath's RNG cost** (user-confirmed 2026-09-27): nothing beyond
the move selection (target scan rolls plus the move-choice roll) and one
damage roll per party member hit, in hit-loop order. Unlike Lightning,
it has no VFX particle RNG, so a sim needs no Fire Breath equivalent of
`simulateLightning`.

`lib/Enemies/Dragon.lua`'s `calculateLightningDamage` /
`calculateFireBreathDamage` reuse `lib/EnemyElementalAttack.lua`'s existing
`calculateDamage`/variance primitives.

### Neclord (`ve1.bin`/`ve3.bin`)

Neclord's Castle fight (`ve3.bin`, HP 7500): monster record at
`0x8009ddc8` (`+0x30` = the AI function pointer, `0x8001675c`) — HP 7500,
PWR 450, DEF 80, MGC 275, SPD 75, SKL 100, LUK 30, level 55.
Target-selection (`neclord_ai_select_target_and_move`, `0x8001675c`) uses
the same template as every other monster (front-row scan, `roll%100>50`
accept, retry fresh on total reject).

Move choice, in the continuation `neclord_special_move_windup`
(`0x800168dc`): after a busy-wait gate, two sequential
`(roll*100)/32767 < 0x33` (~51%) rolls pick one of three attack scripts.
RNG2 is uniform over 32768 values; `quotient < 51` iff `roll ≤ 16711`
(16712/32768 values): `p = P(roll < 51%) = 16712/32768 = 0.510010`, `q =
P(roll ≥ 51%) = 16056/32768 = 0.489990`. Wind is picked outright on the
first roll's `q` branch; only the `p` branch spends a second roll to split
Bats vs. Lightning:

- **Wind** (`DAT_8009e078`) = `q` = **48.999% ≈ 49.00%**
- **Bats** (`DAT_8009e128`) = `p × p` = 279,290,944/1,073,741,824 = **26.011%**
- **Lightning** (`DAT_8009e0cc`) = `p × q` = 268,327,872/1,073,741,824 = **24.990%**

(sums to exactly 1 algebraically: `q + p² + pq = q + p(p+q) = q + p = 1`.)

Three genuinely different attacks:

- `DAT_8009e078` (~49%) → `neclord_wind_tick_state_machine` (`0x80016d14`):
  a 4-state tick handler (windup with knockback + sound cue `0x813`, then a
  hit-reaction script dispatch on every living party member followed by
  `calc_rune_element_attack_damage`, `element=5` (Wind/Cyclone) +
  `apply_hp_damage_display` per living target) — AOE, loops all 6
  combatant slots.
- `DAT_8009e0cc` (~25.5%) → its own tick machine (damage call site
  confirmed at `0x800177c0`): the same `calc_rune_element_attack_damage`
  call, `element=4` (Lightning/Thunder) — also AOE, same loop shape as
  Wind.
- `DAT_8009e128` (~25.5%) → `neclord_bats_tick_state_machine`
  (`0x80017f88`): a 7-state handler managing 20 spawned bat particles
  (`RngCallbackTable` slot `0xA4`, particle allocation) converging on the
  target, ending in a call to `RngCallbackTable` slot `0xC` = `0x800f7e90`
  = `calc_damage`, the ordinary physical ATK-DEF formula — single-target,
  using the locked `TargetIdx` directly rather than looping all 6.

**Bats' RNG advancement and poison**: total 86 `rand()` calls for a Bats
attack, broken down as 2 target-scan + 2 move-choice + 60 + 20 + 1 + 1:
- **Bat spawn setup** (`0x80017cd0`): for each of 20 spawned bat
  particles, (a) `RngCallbackTable` slot `0x120`
  (`main.exe @ 0x80123054`): a "random point in a sphere" position
  generator using exactly 3 `rand()` calls per bat = 60 calls total; (b)
  one direct `rand() % 60` "animation phase-offset" roll per bat = 20
  calls total.
- **Damage**: `calc_damage`'s own 1 internal variance roll.
- **Poison**: `neclord_bats_tick_state_machine`'s state 1, once its own
  63-tick converge timer elapses, dispatches a second script
  (`0x8009e1b8`) onto the target via `play_attack_animation` — a repeated
  red-flash + pad-rumble + wobble "bat bite" sequence, then calls opcode 40
  (`anim_op_roll_status_effect_chance`) with `status_id=0` (Poison) and
  `chance_arg=100` — a guaranteed application. The roll still consumes 1
  `rand()` call even at `chance_arg=100`.

Ported to `lib/Enemies/Neclord.lua`'s `simulateMoveSelection`/
`simulateWind`/`simulateLightning`/`simulateBats`, and
`calculateWindDamage`/`calculateLightningDamage` (reusing
`lib/EnemyElementalAttack.lua`'s primitives) /
`calculateBatsDamage` (the ordinary physical ATK-DEF formula, pre-Defend-
halving — callers apply that check themselves).

### Regular (non-boss) enemy AI

Ordinary field encounters use the same hand-scripted-per-monster AI shape
as story bosses, not a shared generic routine, though many reuse the same
templates. **CrimsonDwarf** (`vc3.bin` @ `0x80010034`), **Colossus**
(`vad.bin` @ `0x80010918`), **DevilArmor** (`vc6.bin` @ `0x80011638`),
**DevilShield** (`vc6.bin` @ `0x80010a78`), **GiantSnail** (`va8.bin` @
`0x8001115c`) all use the front-row-only target-scan template, differing
only in the post-selection move: CrimsonDwarf/Colossus/GiantSnail always
plain Attack; DevilShield uses the same `0x33`-threshold move-gate template
as several bosses; DevilArmor counts eligible targets and unconditionally
jumps to a "special" path if any exist. None of these read `+0x11`.

Per-area data files (`NN_area.X`/`X_data.bin`, e.g. `b_data.bin`,
`h_data.bin`, `g_data.bin`) load at runtime base `0x80080000`, not
`0x80010000` like the boss-specific `vXX.bin` overlays.

**Killer Rabbit** (`b_data.bin`, area B, `Id=1`, Level=10, `+0x11=0`) has
genuine long-range targeting: `killer_rabbit_ai_select_target_and_move`
(`b_data.bin @ 0x80080664`) rolls RNG2, and if `>50%`, picks `target =
RNG2 % partyCount + 1` — a raw index into all party members with no
formation-row check at all (every other monster's scan gates on
`combatant_rec+0x44<4`). Validates the pick via two callbacks (one of
which, `killer_rabbit_ai_prepare_leap_special` @ `0x80080988`, duplicates
sprite/animation data, consistent with a leaping/jumping special move),
then commits to it as a "can hit the back row" special attack. Otherwise
falls through to the ordinary front-row-only scan + plain Attack. This
back-row reach is hardcoded directly into the compiled branch logic
(skipping the formation check outright for the special move), not driven
by any per-monster data byte — `+0x11` is not read anywhere in
`b_data.bin`.

**Slasher Rabbit** (`va8.bin` @ `0x800108c0`
`slasher_rabbit_ai_select_target_and_move`, plus `0x80010be4`
`slasher_rabbit_ai_spawn_leap_clone`; record at file offset `0x3a5c4`,
stats HP=60 PWR=65 SKL=30 DEF=10 SPD=29 MGC=6 LUK=6, gold=70): shares
Killer Rabbit's exact leap-clone template — `>50%` RNG2 roll picks a raw
party index (no formation-row check) and spawns a duplicate enemy-slot
"clone" to execute the leap hit; otherwise falls back to the standard
front-row-only scan + plain Attack.

**Rabbit Bird** (`h_data.bin` @ `0x80080038`
`rabbit_bird_ai_select_target_and_move`; record at file offset `0x1f6d4`;
stats HP=300 PWR=305 SKL=110 DEF=50 SPD=60 MGC=160 LUK=110, gold=2200):
plain front-row-only scan template, but normalizes its RNG roll as `roll %
100` directly rather than the `(roll*100)/0x7fff` scaling seen elsewhere.

**Dagon** (`g_data.bin` @ `0x80080338` `dagon_ai_select_target_and_move`,
plus `0x80080254` `dagon_ai_await_animation_then_special`; record at file
offset `0x1e420`): front-row scan plus a second independent roll gate for
a special move, matching DevilShield's `0x33`-threshold move-gate
template.

### Full regular-enemy AI sweep

A systematic pass decompiling every remaining untraced monster's AI
function (statically — no live capture; see each row's own confidence
note), tracking whether the shared target-scan template's `formationPos<4`
front-row restriction is present, and what move logic follows target
selection. Exceptions to the front-row-only norm get their own prose
writeup above/below this table; everything else is one row.

- **FurFur, BonBon, Mosquito (identical shared function)** (`a_data.bin`,
  `0x80080004`) — target scan: front-row only; move: always plain Attack (AI
  declines to act specially once target is locked). **Mosquito's Attack
  poisons**, but the AI isn't what does it. Its hit reaction (slot 2,
  `0x800a0f4c`, which runs on the victim) has opcode 40 with
  `status_id=0, chance_arg=20`. The victim is a party member, so Poison
  lands on `roll < 20`: 20%. That's one extra `rand()` on the damage
  frame, right after `calc_damage`'s. It still rolls on a cover (on the
  covering ally), and it rolls but doesn't reapply on an already-poisoned
  member. FurFur's and BonBon's reaction (`0x8009e988`) has no roll.
  Live-verified 2026-09-30 (`3Mosquito1Ant.State`): 96/96 damage frames
  took 2 `rand()`s, and the replayed rolls predicted every round-start
  Poison tick (24/24 round starts; the tick lands on frame 2 after
  confirm).
- **Crow** (`a_data.bin`, `0x80080604`) — target scan: front-row only; move:
  always plain Attack
- **Wild Boar** (`a_data.bin`, `0x80080760`) — target scan: front-row only;
  move: always plain Attack
- **Red Solider Ant [sic — the ROM's own name field has this typo]**
  (`a_data.bin`, `0x80080adc`) — target scan: front-row only; move: ~77%
  Attack / ~23% DoubleStrike — shares Soldier Ant's exact move-choice
  formula and threshold (`((roll*100)/32767)%100 < 0x4d`, see below).
  DoubleStrike (**live-verified** 2026-09-30, see below): the AI plays
  script `0x800a5460` (table slot 8) itself and sets the roll gate to
  20; continuation
  `red_soldier_ant_special_double_strike` (`0x80080950`) waits for the
  attacker's `+0x40 & 0x2`, then does `calc_damage << 1` with **no hit
  roll and no crit** (always hits) and plays reaction `0x800a5550` on the
  target. Walker: impact f28, damage f29, target free f63 (reaction 34),
  attacker's script clears its own busy at f145 (no slot-4 return).
  Live check (`3Mosquito1Ant.State`, 8 seeds × 4 rounds, party
  Defending; `scripts/VerifyMosquitoRedAnt.lua` +
  `VerifyMosquitoRedAntCompare.py`): all 128 enemy turns matched — 96
  Mosquito, 20 Red Ant Attack, 12 DoubleStrike. Target and move replay
  exactly from the LCG, and so does the per-tick `rand()` count: basic
  Attack = scan rolls (+ the ant's move roll) + 1 hit roll; DoubleStrike
  has no hit roll. Every frame matched the tables, including the counter, cover
  and kill paths. Unclamped DoubleStrike damage was always even
  (18–22 vs 9–11 for Attack).
- **Empire Captain, Empire Soldier (×4, all sharing this function)**
  (`va2.bin`, `0x80010004`) — target scan: front-row only; move: always
  plain Attack
- **Empire Soldier (×5, separate area file, byte-identical AI shape/behavior
  to va2.bin's copy but a distinct function instance)** (`va3.bin`,
  `0x80010004`) — target scan: front-row only; move: always plain Attack
- **Soldier Ant** (`va7.bin`, `0x800106b0`) — target scan: front-row only;
  move: ~77% Attack / ~23% DoubleStrike — already fully documented and
  **live-validated** (see the Soldier Ant/Queen Ant sections above this
  table); listed here only for sweep completeness
- **Bandit** (`va7.bin`, `0x800103b0`) — target scan: front-row only
  (unrestricted-row, no formationPos gate — same as Varkas); move: always
  plain Attack — Bandit's AI record literally shares Varkas's already-
  documented function (`varkas_ai_select_target_and_move`), not just an
  identical-looking one
- **Holly Boy** (`va4.bin`, `0x80010a7c`) — target scan: front-row only;
  move: Not a flat threshold: once a target locks, first reads a byte at the
  *target's* `PersistentStats+0xd` (an unidentified field, not one of this
  doc's already-catalogued PersistentStats offsets); if `<4`, declines
  (plain Attack). Otherwise rolls again — `>0x19(25)` (~74%) commits to a
  special move (script `0x800766e8`, 30-tick counter), `<=0x19` (~26%)
  declines instead. First monster found this sweep whose move choice depends
  on a property of the *target*, not just a self-roll.
- **Black Wild Boar** (`va7.bin`, `0x800108f0`) — target scan: front-row
  only; move: always plain Attack
- **Killer Slime** (`va8.bin`, `0x80010028`) — target scan: front-row only;
  move: always plain Attack
- **Flying Squirrel, Roc (identical shared function)** (`b_data.bin`,
  `0x8008006c`) — target scan: front-row only; move: always plain Attack
- **Beast Commander** (`b_data.bin`, `0x80080f00`) — target scan: **not
  front-row-restricted at all** (party-target loop only checks `enemy_
  data[i]+0x5==0`/not-busy and `combatant_rec[i]+0x45==0`/alive — no
  `formationPos<4` check anywhere in it, live-confirmed 2026-09-19: hit
  Cleo at `formationPos=4`, i.e. back row, via `BeastCommander.State`);
  move: **"Commander" mechanic — now decompiled and live-confirmed, see
  the dedicated write-up below the table.** First checks whether *any
  other enemy* is alive, not busy, and in the front row — this only gates
  whether Beast Commander activates its command move this tick (that
  check, unlike the party-target scan above, DOES have a `formationPos<4`
  condition — it's a separate loop over enemy slots, not the party-attack
  target scan). If Beast Commander is itself in the front row, or no such
  ally exists, it falls back to the any-row party-target scan above +
  always-plain-Attack (with some extra debug-print calls, e.g. a
  `"KOGEKI_MOKUHYO"` — Japanese romaji for "attack target" — string
  argument, not gameplay-relevant). **That "plain Attack" isn't purely
  plain**: Beast Commander's own hit-reaction script (`pAttackScriptTable
  +0x08`, `0x800a229c`) embeds `anim_op_roll_status_effect_chance(
  status_id=5, chance_arg=30)` — a flat 30% chance per landed hit to also
  inflict status `id5` (**Sleep** — see the status-effects section above
  for the naming/full mechanism) on the victim, fully traced live via
  `BeastCommander.State` — see that same section for the engine bug behind
  why it never expires on a party member. **Because this attack can target
  any row, Sleep can land on back-row party members too** — this was the
  user's own original observation that prompted re-checking the
  "front-row only" claim in the first place. If Beast Commander is in the **back
  row** with an eligible front-row ally, it plays a self-targeted command
  animation (script `0x800a2268`) and hands off to a continuation function
  (`LAB_800811b0`, decompiled as `beast_commander_command_continuation`)
  that is byte-for-byte identical to Viperman's, Whip Wolf's, and Whip
  Master's own continuations — see below.
- **Empire Soldier (×2, separate area file, same generic-template
  shape/behavior, distinct function)** (`vb1.bin`, `0x80010004`) — target
  scan: front-row only; move: always plain Attack
- **Robot Soldier (×2 records, each with its OWN separate function — same
  shape/behavior, just two distinct compiled instances)** (`vb3.bin`,
  `0x8001037c` and `0x80010d28`) — target scan: front-row only; move: always
  plain Attack
- **Empire Soldier (separate area file, same generic-template
  shape/behavior, distinct function)** (`vb3.bin`, `0x80010050`) — target
  scan: front-row only; move: always plain Attack
- **Slot man** (`vb3.bin`, `0x8001151c`) — target scan: front-row only;
  move: **No move-choice roll at all** — once a target locks,
  unconditionally commits to its special move every single time (arms
  `LAB_8001169c`, returns `1`). Unlike every other monster traced so far
  (either "always plain Attack" or "roll for Attack vs. special"), Slot man
  never uses a plain Attack once it has a target.
- **Ghost Armor** (`vb5.bin`, `0x80010178`) — target scan: **no row
  restriction, no RNG accept-roll at all** — see note; move: **Structural
  exception**, and a new kind: this function doesn't scan-and-roll per
  candidate the way every other monster in this sweep does. It just counts
  how many party members are alive and not busy (no `formationPos<4` front-
  row gate — same unrestricted scope as Sydonia, but even simpler: no per-
  candidate ~49% accept roll either). If at least one qualifies, it
  unconditionally arms `LAB_80010224` and commits (returns `1`) — actual
  target selection must happen inside that continuation, not here. If nobody
  qualifies, it marks itself busy and returns `0`. A 4th confirmed back-row-
  reaching exception (alongside Killer Rabbit, Slasher Rabbit, Sydonia).
- **Oannes** (`vb5.bin`, `0x800110a8`) — target scan: front-row only; move:
  ~76% Attack / ~24% special move (script `0x8005fde0`) — same "roll again
  after target locks" shape as the ant-family DoubleStrike monsters, just
  its own threshold (`roll%100 < 0x4c(76)` → Attack).
- **Giant Slug** (`vb5.bin`, `0x8001131c`) — target scan: front-row only;
  move: always plain Attack
- **Kobold (×2 records here, each its own identical-shape function)**
  (`vb6.bin`, `0x80010048` and `0x800101bc`) — target scan: front-row only;
  move: always plain Attack
- **Veteran Soldier (this record shares Kobold's own `0x80010048` function
  above — literally the same compiled AI, not just an identical shape)**
  (`vb6.bin`, `0x80010048`) — target scan: front-row only; move: always
  plain Attack
- **Holly Spirit** (`vb6.bin`, `0x80010330`) — target scan: front-row only,
  but only in the front-row branch — see note; move: **Structural exception:
  checks its OWN row FIRST**, before doing anything else. Front row →
  ordinary scan-and-lock, always plain Attack. Back row → plays a self-
  targeted animation (script `0x8006f554`) and hands off to a continuation
  (`LAB_800104dc`, decompiled as `holly_spirit_continuation`) that scans
  other enemies for one alive/not-busy, then **literally invokes that ally's
  own AI decision function** (reading the ally's own species AI-function
  pointer from its MonsterRecord and calling it with "self" temporarily
  swapped to be that ally), reacting to whatever the ally's own function
  decides. Because the ally runs its *own* AI unmodified, this does NOT
  bypass whatever row restriction that ally's AI already has — unlike the
  commander pattern below, which does. See the dedicated write-up below the
  table.
- **Holly Boy (2nd record, separate area file)** (`vb6.bin`, `0x80010f54`) —
  target scan: front-row only; move: Same target-property-gated special move
  as the `va4.bin` Holly Boy (Batch 4): checks locked target's
  `PersistentStats+0xd`, `<4` declines, otherwise ~74% special move (script
  `0x80071840` here — different script address, same shape) / ~26% decline.
  Two independent compiled instances agreeing on this exact mechanic
  strengthens the case that `PersistentStats+0xd` is a real, meaningful
  field worth identifying.
- **Kobold (3rd record, level 20 "elite" stat block — HP 50/PWR 100/MGC 130,
  a story/mini-boss-tier Kobold, not the regular random-encounter one)**
  (`c_data.bin`, `0x80080490`) — target scan: front-row only; move: ~51%
  Attack / ~49% special move (`(roll*100)/0x7fff < 0x33(51)` → Attack).
  **Notable cross-reference**: this is the exact same function already
  documented (and named) as `dragon_move_confirm_or_override_to_fire_breath`
  in this doc's Dragon section — there, it was proven to be dead code
  (Dragon's real move-confirm happens elsewhere, in
  `dragon_special_move_real_frame_callback`) and that section's own plate
  comment speculated the code was "possibly for a different monster sharing
  this same c_data.bin." This Kobold record confirms that speculation: the
  function is genuinely live, active AI for this Kobold, just dead for
  Dragon specifically. The `dragon_fire_breath_windup` continuation name is
  a leftover from that original context, not a claim that this Kobold's
  special move animates as literal fire breath.
- **Veteran Soldier (separate area file, same generic-template
  shape/behavior, distinct function)** (`vc6.bin`, `0x800107ac`) — target
  scan: front-row only; move: always plain Attack
- **Strong Arm** (`c_data.bin`, `0x80080018`) — target scan: front-row only;
  move: always plain Attack
- **Eagle man, Dwarf (identical shared function)** (`vc1.bin`, `0x80010004`)
  — target scan: front-row only; move: always plain Attack
- **Death boar** (`vc1.bin`, `0x80010178`) — target scan: front-row only;
  move: always plain Attack
- **Death Machine (×2 records, each its own identical-shape function)**
  (`vc3.bin`, `0x80010360` and `0x80010d0c`) — target scan: front-row only;
  move: always plain Attack
- **Holly Fairy** (`d_data.bin`, `0x800801ac`) — target scan: front-row
  only, but only in the front-row branch — see note; move: **Same structural
  pattern as Holly Spirit** (checks its OWN row first): front row → ordinary
  scan-and-lock, always plain Attack; back row → self-targeted animation
  (script `0x800a0938`) then hands off to a continuation (`LAB_80080358`,
  decompiled as `holly_fairy_continuation`) that is byte-for-byte identical
  to Holly Spirit's own — the "delegate to the ally's own AI function"
  pattern, not the commander direct-assignment mechanic. See the dedicated
  write-up below the table.
- **Mad Ivy** (`d_data.bin`, `0x80080038`) — target scan: front-row only;
  move: always plain Attack
- **Creeper** (`d_data.bin`, `0x80081fa8`) — target scan: front-row only;
  move: ~51% Attack / ~49% special move (`(roll*100)/0x7fff < 0x33(51)` →
  Attack; script `0x800a447c`, 20-tick counter, next micro-state
  `LAB_80081d50`) — same formula shape as the Dragon/elite-Kobold shared
  function, but its own distinct, genuinely-live compiled function.
- **Ivy** (`k_data.bin`, `0x80080038`) — target scan: front-row only; move:
  always plain Attack (same address as Mad Ivy's function in `d_data.bin`,
  but a separate file/compiled instance — coincidence, not a cross-file
  share)
- **Red Slime, Delf (identical shared function)** (`vd5.bin`, `0x80012ebc`)
  — target scan: front-row only; move: always plain Attack
- **Viperman** (`vd5.bin`, `0x800132d0`) — target scan: n/a — see note;
  move: **2nd instance of the "commander" pattern** — see the dedicated
  write-up below the table. Scans other enemy slots for an eligible (alive,
  not busy, front-row) ally first, purely to decide whether to activate the
  command branch this tick. If Viperman is in the **back row** with an
  eligible front-row ally, it plays a self-targeted command animation
  (script `0x800716d0`) and hands off to `viperman_command_continuation`
  (`LAB_8001352c`) — byte-for-byte identical to Beast Commander's/Whip
  Wolf's/Whip Master's own continuations.
- **Nightmare** (`vd5.bin`, `0x80014338`) — target scan: front-row only;
  move: **No move-choice roll at all** — same pattern as Slot man: once a
  target locks, unconditionally commits to its special move every time (arms
  `LAB_800144b8`, returns `1`). A 2nd confirmed instance of "never uses a
  plain Attack once it has a target."
- **Whip Wolf** (`e_data.bin`, `0x80080194`) — target scan: front-row only,
  but only in the front-row branch — see note; move: **3rd instance of the
  "commander" pattern** (Beast Commander, Viperman). Front row → ordinary
  scan-and-lock (using a slightly different RNG-scaling variant of the same
  ~50% accept check), always plain Attack. Back row → plays a self-targeted
  command animation (script `0x8009ed74`) and hands off to
  `whip_wolf_command_continuation` (`LAB_80080338`) — byte-for-byte
  identical to Beast Commander's/Viperman's/Whip Master's own continuations.
  See the dedicated write-up below the table.
- **Hell Hound, Grave Master (identical shared function)** (`e_data.bin`,
  `0x80080020`) — target scan: front-row only; move: always plain Attack
- **Sorcerer** (`e_data.bin`, `0x800812b4`) — target scan: front-row only;
  move: ~51% Attack / ~49% special move (`(roll*100)/0x7fff < 0x33(51)` →
  Attack; next micro-state `LAB_800814a0`) — same formula shape as
  Creeper/the elite Kobold.
- **Clay Doll** (`ve2.bin`, `0x80014298`) — target scan: front-row only;
  move: ~71% Attack / ~29% special move (`(roll*100)/0x7fff < 0x47(71)` →
  Attack; next micro-state `LAB_800150ac`) — same formula shape as the ant-
  family/Creeper/Sorcerer split, its own threshold.
- **Banshee** (`ve2.bin`, `0x80015328`) — target scan: front-row only; move:
  **No move-choice roll at all** — 3rd confirmed instance of "always commits
  to its special move once a target locks" (alongside Slot man, Nightmare);
  next micro-state `LAB_800154a8`.
- **Red Elemental** (`ve2.bin`, `0x80015cfc`) — target scan: **no row
  restriction — no `formationPos<4` gate at all**; move: always plain
  Attack. A 7th confirmed back-row-reaching exception — but unlike the
  others (Sydonia/Ghost Armor/rabbits/support-types), Red Elemental's
  unrestricted scope doesn't unlock a special move; it's just an
  unrestricted target-scan that always ends in a plain Attack.
- **Hell Unicorn** (`ve3.bin`, `0x8001320c`) — target scan: front-row only;
  move: ~51% Attack / ~49% special move (`(roll*100)/0x7fff < 0x33(51)` →
  Attack; next micro-state `LAB_800133f8`) — same formula shape as
  Creeper/Sorcerer/the elite Kobold.
- **Demon Sorcerer** (`ve3.bin`, `0x80014ce8`) — target scan: front-row
  only; move: ~51% Attack / ~49% special move (`(roll*100)/0x7fff <
  0x33(51)` → Attack; next micro-state `LAB_80014ed4`) — same formula shape
  as Hell Unicorn/Creeper/Sorcerer.
- **Larvae** (`ve3.bin`, `0x80012f10`) — target scan: front-row only; move:
  always plain Attack
- **Shadow Man** (`f_data.bin`, `0x800823d8`) — target scan: front-row only;
  move: **No move-choice roll at all** — a 4th confirmed instance of "always
  commits to its special move once a target locks" (script `0x800a2b40`,
  next micro-state `LAB_80082280`). Also does extra bookkeeping the other 3
  don't: clears a 2-byte field on itself (`selfIdx*0x8c+0x90`) and sets a
  flag on the shared AI struct itself (`param_1+0x44=1`, not per-actor) —
  meaning not yet identified.
- **Mirage** (`f_data.bin`, `0x80084294`) — target scan: **no row
  restriction on the scan itself** — see note; move: **2nd confirmed
  instance of the Sydonia-style pattern**: scans ALL party members with no
  front-row gate (like Sydonia/Ghost Armor/Red Elemental), but after a
  target locks, branches on the *locked target's own row* — mirrored from
  Sydonia's version: if the target is in the **front row**, declines (plain
  Attack); if the target is in the **back row**, commits to a special move
  against that same target (clears the same `+0x90` field as Shadow Man,
  script `0x800a4c40`, next micro-state `LAB_80083848`). Sydonia does the
  opposite (front-row target → special, back-row target → decline) — same
  structural template, opposite row trigger.
- **Magic Shield** (`vf1.bin`, `0x8001317c`) — target scan: front-row only;
  move: ~51% Attack / ~49% special move (`(roll*100)/0x7fff < 0x33(51)` →
  Attack; next micro-state `LAB_80013368`) — same formula shape as the
  Creeper/Sorcerer family.
- **Sunshine King** (`vf1.bin`, `0x80013e80`) — target scan: front-row only;
  move: **No move-choice roll at all** — a 5th confirmed instance of "always
  commits to its special move once a target locks" (next micro-state
  `LAB_80014000`).
- **Black Elemental** (`vf1.bin`, `0x800149d8`) — target scan: **no row
  restriction — no `formationPos<4` gate at all**; move: always plain
  Attack. A 3rd confirmed "elemental family" instance of the unrestricted-
  scan exception (alongside Red Elemental) — an 8th confirmed back-row-
  reaching exception overall.
- **Rock Buster** (`vf2.bin`, `0x80014960`) — target scan: front-row only;
  move: ~71% Attack / ~29% special move (`(roll*100)/0x7fff < 0x47(71)` →
  Attack; next micro-state `LAB_80015774`) — same threshold shape as Clay
  Doll.
- **Wyvern** (`vf2.bin`, `0x80017358`) — target scan: front-row only; move:
  **No move-choice roll at all** — a 6th confirmed instance of "always
  commits to its special move once a target locks" (next micro-state
  `LAB_800174d8`).
- **Siren (this record)** (`g_data.bin`, `0x800807b0`) — target scan: front-
  row only; move: ~51% Attack / ~49% special move (`(roll*100)/0x7fff <
  0x33(51)` → Attack; next micro-state `LAB_8008099c`) — same formula shape
  as the Creeper/Sorcerer family. (NOTE: a separate Siren record exists in
  `vs1.bin` — tracked in a later batch.)
- **Grizzly Bear** (`g_data.bin`, `0x80080014`) — target scan: front-row
  only; move: always plain Attack
- **Hawk Man, Demon Hound (identical shared function)** (`vg2.bin`,
  `0x8001301c`) — target scan: front-row only; move: always plain Attack
- **Shadow** (`vg2.bin`, `0x80013b80`) — target scan: front-row only; move:
  **No move-choice roll at all** — a 7th confirmed instance of "always
  commits to its special move once a target locks" (script `0x8003c018`,
  next micro-state `LAB_80013a28`). Shares Shadow Man's exact extra
  bookkeeping (clears the same `+0x90` field, sets the same shared-struct
  `param_1+0x44=1` flag) — good cross-validation that this bookkeeping is a
  real, intentional mechanic and not coincidental.
- **Earth Golem** (`h_data.bin`, `0x80082c18`) — target scan: front-row
  only; move: ~71% Attack / ~29% special move (`(roll*100)/0x7fff <
  0x47(71)` → Attack; next micro-state `LAB_80083a2c`) — same threshold
  shape as Clay Doll/Rock Buster.
- **Whip Master** (`vh1.bin`, `0x80010194`) — target scan: front-row only,
  but only in the front-row branch — see note; move: **LIVE-CONFIRMED
  "commander" mechanic — 4th instance, and the one directly verified against
  a real savestate** — see the dedicated write-up below the table for the
  full mechanism and live capture results. Front row → ordinary scan-and-
  lock, always plain Attack. Back row → plays a self-targeted command
  animation (script `0x8006f9dc`) and hands off to
  `whip_master_command_continuation` (`LAB_80010338`), which directly
  commands every eligible ally (e.g. Hell Hounds), bypassing each ally's own
  AI and row restriction entirely.
- **Hell Hound (this record), Elite Soldier (identical shared function)**
  (`vh1.bin`, `0x80010020`) — target scan: front-row only; move: always
  plain Attack
- **Ninja** (`vh1.bin`, `0x8001067c`) — target scan: front-row only; move:
  ~51% Attack / ~49% special move (`(roll*100)/0x7fff < 0x33(51)` → Attack;
  next micro-state `LAB_80010868`) — same formula shape as the
  Creeper/Sorcerer family.
- **Magus** (`vh1.bin`, `0x800116ac`) — target scan: front-row only; move:
  ~51% Attack / ~49% special move (`(roll*100)/0x7fff < 0x33(51)` → Attack;
  next micro-state `LAB_80011898`) — same formula shape as the
  Creeper/Sorcerer family.
- **Elite Soldier (2nd record, separate area file)** (`vs1.bin`,
  `0x80016498`) — target scan: front-row only; move: always plain Attack
- **Kerberos (shares Elite Soldier's own `0x80016498` function above —
  literally the same compiled AI)** (`vs1.bin`, `0x80016498`) — target scan:
  front-row only; move: always plain Attack
- **Siren (2nd record, separate area file)** (`vs1.bin`, `0x80016810`) —
  target scan: front-row only; move: ~51% Attack / ~49% special move
  (`(roll*100)/0x7fff < 0x33(51)` → Attack; next micro-state `LAB_800169fc`)
  — same formula shape as the Creeper/Sorcerer family.
- **Imperial Guards (×2 records, identical shared function)** (`vad.bin`,
  `0x80010918`) — target scan: front-row only; move: always plain Attack
- **Phantom** (`vad.bin`, `0x80012770`) — target scan: **no row restriction
  on the scan itself** — see note; move: **3rd confirmed instance of the
  Sydonia-style pattern** (Sydonia, Mirage, now Phantom): scans ALL party
  members with no front-row gate, then branches on the LOCKED TARGET's own
  row — matching Mirage's exact logic byte-for-byte: front-row target →
  decline (plain Attack); back-row target → commits to a special move
  against that same target (clears the same `+0x90` field as Mirage/Shadow
  Man/Shadow, script `0x8007cf6c`, next micro-state `LAB_80011d24`).
- **Ekidonna** (`vad.bin`, `0x8001331c`) — target scan: front-row only;
  move: ~51% Attack / ~49% special move (`(roll*100)/0x7fff < 0x33(51)` →
  Attack) — same formula shape as the Creeper/Sorcerer family.
- **Golden Hydra (×3 records — presumably its 3 heads, all sharing this
  function)** (`vzv.bin`, `0x800102fc`) — target scan: front-row only; move:
  always plain Attack
- **Ninja Master** (`z_data.bin`, `0x80080178`) — target scan: front-row
  only; move: ~51% Attack / ~49% special move (`(roll*100)/0x7fff <
  0x33(51)` → Attack; next micro-state `LAB_80080364`) — same formula shape
  as the Creeper/Sorcerer family.
- **Simurgh, Orc (identical shared function)** (`z_data.bin`, `0x80080004`)
  — target scan: front-row only; move: always plain Attack

### The "commander" AI pattern, decompiled and live-confirmed (Beast Commander, Viperman, Whip Wolf, Whip Master)

Beast Commander/Viperman's back-row branch plays a self-targeted command script; Whip
Wolf/Whip Master's structurally-identical back-row branch does the same. Live-confirmed
against a savestate with Hell Hounds accompanied by a Whip Master
(`WhipMasterHellhounds.State`: 5 Hell Hounds + 1 Whip Master).

**The mechanism.** Each of these four monsters' own `select_target_and_move` function has an
initial gate: it scans other enemy slots for one that is alive, not busy, and in the front
row. If the monster itself is in the front row, or no such ally exists, it falls back to the
ordinary scan-and-lock template and always attacks normally. If the monster is in the **back
row** *and* an eligible front-row ally exists, it plays a self-targeted command animation and
writes a continuation function pointer into `param_1+0xc` — the *shared* AI-struct's own
"next tick" slot, not the per-actor micro-state slot at `combatant_rec+0x50` that an ordinary
self-move continuation would use. That distinction (shared-struct slot vs. per-actor slot) is
what should have been the tell during the original sweep.

All four continuation functions — `beast_commander_command_continuation` (`b_data.bin`
`0x800811b0`), `viperman_command_continuation` (`vd5.bin` `0x8001352c`),
`whip_wolf_command_continuation` (`e_data.bin` `0x80080338`), and
`whip_master_command_continuation` (`vh1.bin` `0x80010338`) — are **byte-for-byte identical**
(452 bytes, decompiling to the same logic; only the final per-file continuation label
differs). Decompiled, the shape is:

1. Check a per-actor bitmask on the commander's own extended record
   (`enemyDataAddr+0x40` — this is `EnemyData.wEffectFlags`, a general-purpose 16-bit flags
   field already documented elsewhere in this file for two other, unrelated purposes: bit
   `0x1` arms `counter_attack_reprisal`, and Cleo's own basic-Attack script separately sets bit
   `0x4` on her target — see the "On a miss or a hit" section above), specifically bit `0x2` —
   if unset, decline (`-1`).

   This bit is set by the command animation's own script — a C-level animation call isn't
   the whole story, the script's own opcodes matter. Whip Master's command-trigger script
   (`DAT_8006f9dc`, `vh1.bin`), walked through the animation-opcode interpreter
   (`play_attack_animation`, `0x800e3820`, `PTR_FUN_8016babc`'s 45-entry table in `main.exe`):

   | # | Opcode | Args | Effect |
   |---|---|---|---|
   | 1 | 15 `set_busy_flags` | target=self, mask=1 | marks itself busy |
   | 2–3 | 4, 5 | arg=7 | animation-resource step + wait |
   | 4 | 34 `pad_command_dispatch` | arg=0x050c | rumble/sound cue |
   | 5–6 | 4, 5 | arg=8 | animation-resource step + wait |
   | 7 | **26 `anim_op_set_effect_flags`** | **target=self, mask=`0x2`** | **← the exact bit `whip_master_command_continuation` checks** |
   | 8–9 | 4, 5 | arg=9 | animation-resource step + wait |
   | 10 | 3 (delay) | 120 frames | ~2s pose hold |
   | 11–12 | 4, 5 | arg=0 | return to idle |
   | 13 | 16 `clear_busy_flags` | target=self, mask=1 | clears its own busy bit |
   | 14 | 9 `set_sync_signal` | slot=0 | signals completion |
   | 15 | 0 | — | script terminator |

   This lines up exactly with the live trace below: Whip Master's busy flag goes up at frame
   48 (opcode 15), the gate bit flips at frame 68 (opcode 26, two animation/wait steps later),
   and the commander continuation visibly fires on the very next frame (69).
2. Loop over every OTHER enemy slot (`party_count+1 .. party_count+enemy_count`) — **with no
   row restriction on the ally this time** (the front-row-ally check only gated whether the
   commander activates the branch at all, not who ends up commanded). For each ally that is
   alive and not already busy:
   - Find the PARTY member whose `formationPos` **exactly equals this ally's own 1-based
     position in the enemy loop** (1st eligible-loop-index checked against `formationPos==1`,
     2nd against `formationPos==2`, etc.) — **with no `formationPos<4` front-row gate at all.**
   - If a match exists, mark the ally busy, clear a bookkeeping field on it, and directly call
     `play_attack_animation(attacker=ally, target=thatPartyMember, script=ally's own attack
     script)` — **bypassing the ally's own AI decision function entirely.** The ally's own
     `combatant_rec+0x49` (targetIdx) field is never written; the target is passed as a raw
     parameter to the animation call instead, so this activity is invisible to anything reading
     that field.
3. After the loop, arm a cooldown counter and return `0`.

Because the party-formation-slot match is a **direct index equality against the enemy's own
loop position**, not a target *scan* at all, there is no front-row/back-row distinction
anywhere in this logic — any ally, commanded via this mechanism, can end up attacking any
party member, front row or back row, purely as a function of where that ally happens to sit
in the enemy turn order. This is a **structurally different, and stronger, way of reaching
the back row than any of the 8 "back-row-targeting exceptions" listed below** — those all
still involve a target *scan* (just an unrestricted one); this is direct assignment with no
scan and no roll at all.

**Live confirmation** (`WhipMasterHellhounds.State`, run via
`scripts/TraceWhipMasterHellHoundCommand.lua`): the savestate's enemy side is 3 Hell Hounds in
formation slots 1–3, Whip Master in slot 4, and 2 more Hell Hounds in slots 5–6 (so Whip
Master itself sits at back-row-adjacent position 4, and the party occupies formation slots
1–6, one per party member). Confirming the round with Free Will (letting the AI decide every
action):

- Frame 48: Whip Master's own action commits (`busy=1`).
- Frame 68: the per-actor bit-2 gate flips on for Whip Master.
- Frame 69 (the very next frame): **all 5 Hell Hounds become busy simultaneously** — strong
  evidence they were all processed by one call to `whip_master_command_continuation` in a
  single tick, not by five independent per-actor AI ticks (which would be staggered by
  turn-order/speed).
- Frame 126: five party members take damage **in the same frame**:

  | Party slot | formationPos | HP before → after | Back row? |
  |---|---|---|---|
  | 1 | 1 | 508 → 310 | no |
  | 2 | 2 | 59 → 0 (killed) | no |
  | 3 | 3 | 397 → 176 | no |
  | 4 | 4 | 129 → 129 (untouched) | yes |
  | 5 | 5 | 535 → 432 | **yes** |
  | 6 | 6 | 355 → 135 | **yes** |

  Party slot 4 is the one gap — exactly as the mechanism predicts: Whip Master is the enemy
  occupying loop-position 4 (3 Hell Hounds ahead of it in the enemy ordering, itself 4th), and
  its own slot fails the continuation's "not already busy" ally-eligibility check (it's busy
  with its own command action), so loop-index 4 is skipped entirely and no ally ever gets
  assigned to attack party formation slot 4 this round. This is not a "back row is protected"
  rule — it's a coincidental side effect of Whip Master's own position in the enemy turn
  order for this specific formation. A different enemy ordering would leave a different party
  slot untouched.

This live-validates the user's original report exactly: Hell Hounds' own AI
(`hell_hound_elite_soldier_ai_select_target_and_move`) is front-row-restricted and cannot
select a back-row party member on its own — but when a Whip Master (or, by the identical
mechanism, a Beast Commander or Viperman with their respective allies, or a Whip Wolf) is
present and commands them, the commanding monster's continuation picks the target directly,
skipping the ally's own AI and its restriction altogether.

**The other, genuinely different pattern (Holly Spirit, Holly Fairy)**: these two monsters'
back-row branches also hand off to a continuation via the same `param_1+0xc` shared-struct
slot, but their continuations (`holly_spirit_continuation` and `holly_fairy_continuation`,
byte-for-byte identical to each other, 552 bytes — a different size and shape from the
452-byte commander template) do something different again: they scan for an eligible ally,
read that ally's own species id, resolve its own MonsterRecord and AI-function pointer, and
then **literally call that ally's own `select_target_and_move` function**, with the shared
struct's `param_1+8` ("current actor") temporarily overwritten to the ally's own index. In
other words, Holly Spirit/Fairy vicariously trigger the ally's *own* decision-making, rather
than assigning a target directly. Since the ally's own AI runs unmodified, whatever row
restriction that ally's own AI has is preserved — this does NOT bypass the front-row
restriction the way the commander pattern does, so Holly Spirit/Fairy do not enable back-row
attacks by their allies (unless the specific ally they trigger happens to have its own
unrestricted-scan AI, which hasn't been checked for whatever monsters accompany a Holly
Spirit/Fairy in practice).

### Full sweep results: back-row-targeting exceptions and other findings

The sweep above covers all 97 previously-untraced monster records (72 distinct AI
functions) not already documented elsewhere in this file, completing full AI coverage
of all 124 records in `outputs/Bestiary.json`. This answers the original question
("which enemies can attack the back row?") definitively, and also corrects an
over-claim made partway through the sweep (see the note below the list).

**Confirmed back-row-*targeting* exceptions** — monsters whose AI can actually select
a back-row party member as the target of an attack (special move or plain Attack),
bypassing the generic template's `formationPos<4` front-row restriction on the scan
itself:

1. **Killer Rabbit** — leap-special branch does an unrestricted `RNG2 % partyCount + 1`
   pick (any row); already documented pre-sweep.
2. **Slasher Rabbit** — same leap-special mechanic as Killer Rabbit; already documented
   pre-sweep.
3. **Sydonia** — unrestricted 6-slot scan; if the locked target is in the *front* row,
   commits her special move against it; if *back* row, falls back to a plain Attack
   against that same back-row target. Already documented pre-sweep.
4. **Ghost Armor** (`vb5.bin`) — no `formationPos<4` gate and no per-candidate accept
   roll at all; commits to its special move whenever any party member is alive/not
   busy, including if only back-row members qualify.
5. **Red Elemental** (`ve2.bin`) — unrestricted scan, always plain Attack against
   whichever target (front or back row) gets accepted.
6. **Black Elemental** (`vf1.bin`) — same as Red Elemental; a 2nd "elemental family"
   instance.
7. **Mirage** (`f_data.bin`) — unrestricted scan; if the locked target is in the
   *back* row, commits a special move against it; if *front* row, plain Attack instead.
   The mirror image of Sydonia's row-trigger direction.
8. **Phantom** (`vad.bin`) — byte-for-byte the same logic as Mirage; a 2nd instance of
   that mirrored pattern.

That's **8 confirmed back-row-targeting monsters** total (where the monster itself
directly selects a back-row party member via an unrestricted scan), up from the 3
known before this sweep (Killer Rabbit, Slasher Rabbit, Sydonia). This does not count
the "commander" pattern below, which is a *stronger, indirect* way of reaching the
back row — via commanded allies rather than the commanding monster's own attack.

**Beast Commander, Viperman, Whip Wolf, and Whip Master** all share one mechanism (see
"The 'commander' AI pattern" write-up above): all four back-row-branch continuation
functions are byte-for-byte identical, and — live-confirmed against a savestate for
Whip Master/Hell Hound — implement a genuine **direct-target-assignment command
mechanic** that lets each commanded ally attack any party member (front or back row)
with no row restriction at all, entirely bypassing that ally's own AI. Holly Spirit and
Holly Fairy use a third, different pattern (invoking the ally's own AI function
vicariously) that does *not* bypass the ally's row restriction — see the same write-up
above for the distinction.

**Other notable AI exception patterns found this sweep**:

- **"Commander" direct-assignment pattern** (Beast Commander, Viperman, Whip Wolf,
  Whip Master — 4 confirmed instances, one live-validated): see the dedicated
  write-up above the table. Lets commanded allies bypass their own AI's row
  restriction entirely — a stronger mechanism than any of the 8 back-row-targeting
  exceptions above, since it isn't even a scan.
- **"Delegate to the ally's own AI" pattern** (Holly Spirit, Holly Fairy — 2 confirmed
  instances): a related but genuinely different command variant — see the same
  write-up above. Does not bypass the commanded ally's own row restriction.
- **"Always special move, no roll"** (Slot man, Nightmare, Banshee, Shadow Man,
  Sunshine King, Wyvern, Shadow — 7 confirmed instances): once a target locks, these
  monsters never fall back to a plain Attack; they unconditionally commit to their
  special move every time. Shadow Man and Shadow additionally share an unidentified
  bookkeeping step (clearing a 2-byte per-actor field, setting a flag on the shared AI
  struct itself) not seen anywhere else.
- **Attack-vs-special-move roll, generalized**: beyond the already-documented ant
  DoubleStrike split (~77/23), the sweep found the same "roll again after target
  locks" shape recurring with several different thresholds: ~71/29 (Clay Doll, Rock
  Buster, Earth Golem) and ~51/49 (Oannes' own ~76/24 aside, most others — Creeper,
  Sorcerer, Magic Shield, Hell Unicorn, Demon Sorcerer, Ninja, Magus, Siren ×2,
  Ekidonna, Ninja Master). One of the ~51/49 functions (an "elite" level-20 Kobold in
  `c_data.bin`) turned out to be the exact same compiled function already documented
  as dead code for Dragon (`dragon_move_confirm_or_override_to_fire_breath`) — a
  useful confirmation that the code is a shared template reused across that area
  file, genuinely live for one monster and dead for another sharing the same file.
- **Target-property-gated special move** (Holly Boy, both compiled instances in
  `va4.bin` and `vb6.bin`): move choice depends on a still-unidentified byte at the
  *locked target's* `PersistentStats+0xd`, not just a self-roll — worth a live capture
  to identify that field.
- The overwhelming majority of monsters (around two-thirds of the 72 distinct
  functions traced) are the plain generic template: front-row-only scan, always a
  plain physical Attack, no special move at all.

All of the above is static-only (Ghidra decompilation, no live capture) per this
project's established convention for monsters without an available savestate — see
each monster's own `scripts/Check<Name>AI.lua` for the ready-to-run live-validation
script.

## Queen Ant (Mt. Seifu, `va7.bin`)

Queen Ant (`va7.bin`) is the boss of a scripted fight accompanied by 3
Soldier Ants (distinct from Seek Valley's separate random-encounter Queen
Ant). Her own per-tick function, `queen_ant_ai_self_heal_and_select_move`
(`0x80010ae0`), does three things every turn, unconditionally: dispatches a
script onto herself, resets her own roll-gate countdown, and resets her own
current HP to max. Then one roll, `(roll*100)/32767 < 0x33`, splits into
two branches — brute-forced over the full RNG2 output range (0-32767, not a
modulo/hash that could bias the split): **AoE Earth = 2089/4096 =
51.0010%**, **CommandAnts = 2007/4096 = 48.9990%**.

- **AoE Earth** (`queen_ant_own_attack_windup` → `_wait_and_arm` →
  `_finish` drive the busy-wait/animation-sync scaffolding; the actual
  damage call is in a separate coroutine,
  `queen_ant_aoe_earth_cast`/`queen_ant_aoe_earth_damage_loop`
  (`0x80011900`/`0x80011c60`), reached via a raw callback install) — loops
  every living party member, calling `calc_rune_element_attack_damage
  (Queen Ant, target, element=3/Earth)` + `apply_hp_damage_display` for
  each; every target gets an independent roll off their own MGC/DEF/RuneId
  (not one shared value copied to everyone). No slot-based register-reuse
  bug is present in this loop — targets take the plain neutral formula
  result (matching Soldier Ant's own already-known stats). Queen Ant's own
  MGC is read at `+0x1c` in this fight's combined combatant array (this
  encounter's enemy-side records use a distinct layout from the party
  layout's `+0x2c`).
- **CommandAnts** (`queen_ant_command_all_ants_attack`, `0x80010edc`,
  reached through a small counter gate): fully deterministic, zero
  `rand()` calls in any code path — loops every enemy slot, commands every
  idle (`ActionTag==0`), non-busy one; for each, walks every party slot
  1..N keeping the last (highest-numbered) candidate satisfying alive +
  not-busy + state code `<4` as the target. In practice this branch is a
  no-op: turn order (see [Turn_Order.md](./Turn_Order.md)) picks the next
  actor by `weight = SPD*10 - 5 + rand()%10` among everyone who hasn't yet
  acted. Soldier Ant's SPD=22 gives weight range `[215,224]`; Queen Ant's
  SPD=20 gives `[195,204]` — these ranges never overlap, so every living
  ant is guaranteed to take its own independent turn before Queen Ant's
  turn ever comes up. By the time she rolls CommandAnts, every
  still-living ant already has `ActionTag=1` from its own turn, failing
  this function's own eligibility check for all of them —
  `queen_ant_command_all_ants_attack`/`ant_commanded_attack_damage`
  (`va7.bin 0x800110d8`) has never been observed to actually fire.

**Soldier Ant** (`va7.bin @ 0x800106b0`
`soldier_ant_ai_select_target_and_move`; monster record at `0x8006500c`:
level 4, HP 28, PWR 48, SKL 18, DEF 10, SPD 22, MGC 0, LUK 6; also part of
Mt. Seifu's random-encounter roster) is what actually produces every ant
attack in this fight: the standard target-scan template, then one
move-choice roll — brute-forced exactly: **Attack = 1577/2048 = 77.0020%**,
**DoubleStrike = 471/2048 = 22.9980%**. Attack falls back to the generic
`apply_uncovered_attack_damage`/`battle_execute_player_attack` resolver (a
single `calc_damage` roll, no elemental scaling).
`soldier_ant_special_double_strike` (`0x80010524`) is a single `calc_damage`
roll, physical, with the result simply doubled (`damage << 1`) before
applying — the doubled roll can exceed a target's own max HP.
`lib/Enemies/SoldierAnt.lua` models both branches;
`lib/Enemies/QueenAnt.lua` models `calculateAoeEarthDamage` (no slot-bug
logic) and the move-selection formula above.

Formation for this fight: exactly 5 party members + 3 Soldier Ants + Queen
Ant (9 combatants total).

### Queen Ant's round-3 battle-end and ant-respawn mechanic

`BattleState+0x1330`/`+0x1334` (the scripted-turn-override hook) is armed
for this encounter, pointing at **`queen_ant_end_of_round_callback`**
(`va7.bin @ 0x8001139c`), which does two things:

1. **Wait-for-everyone gate**: scans every combatant (party + enemies) for
   anyone who hasn't acted this round yet (`ActionTag == 0`) — returns
   immediately (no-op) if so, so the rest of the function only runs once,
   right as a round finishes.
2. **The 3rd-turn battle-end trigger**: once everyone's acted,
   `if (dwRoundNumber > 2) { SyncSignals+4 (BattleState+0x34) = 1; }`.
   `SyncSignals+4` is the same flag `battle_process_round_end_status_and_
   formation`'s own phase-4→5 cleanup sequence checks to trigger its
   larger reset/wrap-up sequence. It is better understood as a general
   "force a full round-state resync now" signal rather than literally "end
   the battle" by itself (see the Ted-vs-Queen-Ant encounter below, which
   sets the same flag for an unrelated purpose) — it plausibly leads to the
   battle ending here, via a generic coroutine-state write not itself
   traced further.
3. **Ant-respawn**: unconditionally (every call, any round), the same
   function also scans every enemy slot for one that's dead/removed and
   not busy, and fully revives it — HP restored to max, marked valid
   again, a spawn animation played. This is Queen Ant's "keeps spawning
   more ant adds during the fight" behavior.

### The scripted Ted-vs-Queen-Ant "forced Hell cast" fight

A separate scripted 1v1 encounter (`dwPartyCount=1`, `dwTotalCombatants=2`:
Ted at `55/55` HP, Queen Ant at `7000/7000` HP) also uses the
`+0x1330`/`+0x1334` scripted-turn-override hook, for a different purpose:
forcing Ted's own action (`ActionType=2`/Rune, `AbilitySlot=3`,
`TargetIdx=2`/Queen Ant — a forced Rune-level-3 cast, Hell, at Queen Ant)
with zero player input, via a 3-stage callback chain in `va7.bin`:

1. **`scripted_forced_turn_delay_arm`** (`0x800101c8`): sets a fixed
   countdown (`0x800716b8 = 0x3c`, 60 ticks ≈ 1 second, a dramatic pause
   before the forced cast plays), schedules the next stage.
2. **`scripted_forced_turn_delay_tick`** (`0x800101e8`): decrements the
   countdown each tick, returning nonzero (a no-op "keep waiting" signal to
   `battle_advance_turn`) until it reaches 0, then schedules the final
   stage.
3. **`scripted_forced_turn_commit`** (`0x80010220`): forces
   `g_nPendingIndex(+0x3420) = 1` (Ted, bypassing the normal weighted-RNG
   roll entirely), disarms the hook (`+0x1330=0`, `+0x1334=0`), sets
   `SyncSignals+4(+0x34) = 1` (a general resync signal in this context,
   not an "end battle" flag), and marks every other combatant's
   `ActionTag = 1` ("already acted") so the very next roll trivially
   resolves to Ted.

None of these 3 functions write Ted's `ActionType`/`AbilitySlot`/
`TargetIdx` themselves — those are set by this encounter's own initial
setup data before this chain even runs (analogous to how Queen Ant's own
encounter setup populates `EnemyData` via `battle_init_apply_scripted_
encounter_callback`/`FUN_800dee44` in `main.exe`, but for a different
per-encounter table).

Together, the two Queen-Ant-adjacent encounters show the
`+0x1330`/`+0x1334` hook is a general-purpose scripted-turn-override
mechanism reused for at least two distinct narrative purposes: ending a
fight on a round threshold, and forcing a specific character's specific
action with no input.

## How spells call RNG: the cast state machine

`apply_elemental_multiplier` itself has no RNG — but a spell *cast* is not
just that one call. Each spell's `DAT_8016d33c[id]+0x1c` field is a code
pointer into a per-spell entry function that schedules a multi-phase,
per-tick state machine (a heap-allocated context struct, phase counter
driving a `switch`) — the same tick-resumable-coroutine pattern used
elsewhere in this codebase (e.g. `battle_advance_turn`). Every spell traced
so far follows the same 3-function shape
(`spell_<name>_cast_entry` → `_vfx_setup` → `_tick_state_machine`), and in
every one, the phase that actually applies damage
(`apply_elemental_multiplier(level, element, target, attacker, base_power)`)
has zero RNG calls — the entire `rand()` cost of a cast is VFX/audio
polish (particle scatter, impact sound variety, screen shake), unrelated to
the damage number itself. See
[Spell_RNG_Tracing_Methodology.md](../../notes/Spell_RNG_Tracing_Methodology.md) for
the repeatable tracing process; this section only records the per-spell
results.

The "Phase ticks" and "Total ticks" columns below are static: each phase's
hardcoded tick-count immediate, summed. They are **not** frame counts. Several
spells run phases at other than one tick per frame (Shining Wind, Final
Flame, Explosion, Hell), and Hell's and Black Shadow's last phases were never
resolved, so their sums were lower bounds. The live-measured frame count for
every spell is in "Measured cast durations" below and supersedes this table
wherever the two differ.

| Spell | id | Element | Base power | Phase ticks |
|---|---|---|---|---|
| Explosion | `4` | Fire (Lv4) | 700 | 64+32+128+96 |
| Earthquake | `24` | Earth (Lv4) | 700 | 64+64+128+64 |
| Charm Arrow | `8` | Resurrection (Lv4) | 500 | 64+32+64+64 |
| Flaming Arrow | `1` | Fire (Lv1) | 100 | 64+96+74+60 |
| Dancing Flames | `3` | Fire (Lv3) | 400 | 64+32+64+77+192+64 |
| Final Flame | `29` | Fire (Rage Lv4) | 900 | 64+128+296+96 |
| Shining Wind | `31` | Wind (Lv5) | 500 | 64+32+64+160+64 |
| Storm Fang | `35` | Earth+Wind combo | — | n/a [2] |
| Hell | `27` | Dark (Lv3, corrected) [3] | 2 (instant-death) | 64+32+128+? |
| Black Shadow | `26` | Dark (Lv2) | 300 | 64+32+80+? |
| Judgment | `28` | Dark (Lv4) | 1500 | 64+32+64+64+64+96+60+60 |
| Drops of Kindness | `9` | Water (Lv1) | heal | 64+32+90+60+60 |
| Fog of Deception | `10` | Water (Lv2) | status | 9 cases, see below |
| Rain of Kindness | `12` | Water (Lv4) | heal 300 | 64+32+90+90+60+60 |
| Water of Kindness | `11` | Water (Lv3) | heal 300 | 64+32+90+60+60 |
| Mother Ocean | `30` | Flowing (Lv4) | full heal | 64+32+90+60+60+60+64, see below |
| Wind of Sleep | `13` | Wind (Lv1) | Sleep 70% | 64+64+64+64+96+64 |

| Spell | Total ticks (≈s @60fps) | RNG-call total |
|---|---|---|
| Explosion | 320 static; 831 live [1] | 1220 (native seed), 1271 (fresh seed) [5] |
| Earthquake | 320 (~5.3s) | seed-dep., 1519–1786 (mean 1649) |
| Charm Arrow | 224 static; 226 live | 24436 (validated seed, core 64-tick phase) |
| Flaming Arrow | 294 (~4.9s) | 512 for the validated seed |
| Dancing Flames | 493 (~8.2s) | fixed 150, always |
| Firestorm | 433 (live) [6] | 0, always (live) |
| Final Flame | 584 (681 frames) [7] | seed-dep., 530-538 |
| Shining Wind | 384 raw; 535-539 live [1] | 1302 for the validated seed |
| Storm Fang | ~360 real frames | fixed 38, always |
| Hell | 843 live (static sum unresolved) [4] | seed-dep., ~10320–12220 (20 seeds) |
| Black Shadow | 463 live (static sum unresolved) | seed/state-dependent — see below |
| Judgment | 504 (static sum = live) | seed-dep., 152-176 (23 seeds) |
| Drops of Kindness | 306 (static sum = live) | fixed 18, always |
| Fog of Deception | 411 (live) | 0, always (live) |
| Rain of Kindness | 419-429 live (static 396) | seed-dep., 1515-1572 (40 seeds) |
| Water of Kindness | 306 (static sum = live) | 12 x party size (72 for 6) |
| Mother Ocean | 557 live (static 430) | 12 x party size, static only |
| Wind of Sleep | 416 (static sum = live) | 300 + 4/zero roll + 1/enemy, 305-317 |

1. case3 phase runs at half framerate, so the real-time span (~9s) is longer
   than the raw tick count implies.
2. Not decompiled past setup — provably zero RNG.
3. Corrected from an earlier "Dark (Lv4*)" uncertainty marker — see [the full
   spell table](#the-full-spell-table-dat_8016d33c).
4. The 260-318 frame variation applies to Hell's RNG-heavy phase only, not to
   the whole spell (843 frames, measured 2026-10-06).
5. Fully modeled and validated exact per-tick against two independently-seeded live
   captures - see `simulateExplosion`'s comment in `lib/Magic.lua` for the confirmed
   mechanism (Pool A/B each re-fire once, at a fixed 55/60-tick cycle after their first
   activation).
6. Measured live, not summed from phase immediates; see "Cast timing" below.
7. Case 2's ticks 201-295 each take two frames (the spell machine only; see
   [Final Flame](#final-flame-seed-dependent-pool-d-respawns)).

### Cast timing (live-measured 2026-09-26)

`scripts/CaptureCleoSpells.lua` (slots 1 and 2) and
`scripts/CaptureDancingFlames.lua` (slot 3): `ZombieDragonStart.State`
(round 1), Cleo (Fire Rune, MP 5/3/2/0, so every cast is legal) set to
Rune / that slot on Zombie Dragon, everyone else on Free Will's pick, 3
seeds each, no other memory edits. All three spells gave identical frames
in every run.

**How a Rune cast starts.** `battle_select_special_ability` returns
"wait" (0) until `battle_check_all_combatants_idle` passes, which checks
**every** combatant, enemies included. In these runs Cleo's turn came up
at F44 but the cast waited until F162: the last busy clear (McDohl's
return from his attack) was F161, and the cast started the next tick.
Call the last busy clear **F** and the cast tick **T0 = F + 1**. On T0 the
caster plays the cast pose `0x8016c194`, its ActionTag is set and the
spell's cast entry goes into `battle+0x14`. The spell then runs inside the
dispatch coroutine, so **no turn roll happens and nobody else acts until
its tick machine finishes**.

| T0+ | Every Fire Rune cast |
|---|---|
| 0 | cast entry, caster busy (cast pose) |
| 1 -> 15 | intro state `0x80120660` |
| 15 | setup (`_vfx_setup`) |
| 16 | tick state machine starts |
| 108 | caster's busy clears (the cast pose) |

| | Flaming Arrows | Firestorm | Dancing Flames |
|---|---|---|---|
| Tick machine | +16 -> +310 | +16 -> +449 | +16 -> +509 |
| Machine length | 294 | 433 | 493 |
| Target busy | +241 -> +275 | +353 -> +387 | 6 x 34, +254 -> +468 |
| **Damage** | **+310** | **+385** | **+509** |
| Next actor picked | +313 | +452 | +512 |
| `rand()` in the cast | 513-525 | 0 | 150 |

From everyone free (F), the damage lands at F + 311 (Flaming Arrows),
F + 386 (Firestorm) and F + 510 (Dancing Flames).

**Rage Rune spells** (`scripts/CaptureCleoSpells.lua` with `SET_RUNE = 27`,
`SET_MP4 = 1`; same save and setup, 3 seeds each). The game's own Rage
ability set (`DAT_8016a0e0[27]` `+0x1a..+0x1e`) is slot 1 Firestorm, 2
Dancing Flames, 3 **Explosion** (spell 4), 4 **Final Flame** (spell 29).

| | Explosion | Final Flame |
|---|---|---|
| Cast entry | `0x80101130` | `0x80101e88` |
| Tick machine | +16 -> +847 | +16 -> +697 |
| Machine length (frames) | 831 | 681 |
| Caster free | **+200** | +108 |
| Target busy | +529 -> +598, +601 -> +670 | 8 windows, +245 -> +627 |
| **Damage** | **+847** | **+696** |
| Next actor picked | +850 | +700 |
| `rand()` | 1238-1282 [a] | 530-538 [b] |

[a] Counted over [T0, next actor). [b] The spell's own calls; see
[Final Flame](#final-flame-seed-dependent-pool-d-respawns).

From everyone free, the damage lands at F + 848 (Explosion) and F + 697
(Final Flame). Explosion's cast pose is the one that differs: 200 ticks, not
108. Its 831 frames are much longer than the 320 summed from its phase
immediates above; the measured figure is what the game takes.

- **Damage vs. turn release.** Flaming Arrows and Dancing Flames apply
  their damage as the tick machine ends. Firestorm applies it at +385,
  mid-machine, and keeps running (and holding the turn) until +449.
- **Damage is committed the same tick** it's applied (HP drops on that
  tick in the log): the cast machine runs in the turn coroutine, before the
  pending-damage commit.
- **The target is idle when the damage lands.** Its busy windows (the hit
  reaction, or Dancing Flames' six flare-ups) all end before or around the
  damage tick (Firestorm: damage at +385, reaction ends +387).
- **RNG.** Flaming Arrows' count is seed-dependent (513, 517, 525 here;
  512 recorded for its validated seed, first 80 calls at +81). Firestorm
  makes **no `rand()` calls at all**: the first call after the cast is the
  next turn roll at +451. Dancing Flames' 150 all fall in [+16, +509]: 30
  at +16, the rest across the flare waves.
- **Caster.** The cast pose is 108 ticks for all three, so the caster is
  free long before the spell ends, but the turn is still held.


`DAT_8016d33c`'s charmap name for id `1` decodes to "**Flaming Arrows**"
(plural) — this table's "Flaming Arrow" predates that decode and is kept
here for continuity with earlier trace notes; the plural is the
authoritative in-game name.

### Measured cast durations, every spell (live, 2026-10-06)

`scripts/MeasureSpellTiming.lua`; `SpellDuration.State` (McDohl, roster id 8,
formation slot 1; rune swapped per case; all four MP pools set to 9), one
Zombie Dragon (enemy id 1, not flying), 3 seeds per spell. The five Fire
spells are the Cleo captures above, re-run through the same script as a
regression (identical numbers, including damage frame and `rand()` count).

**Markers.** `battle+0x14` is a general handler pointer and never returns to
0, so it can't mark the end. A cast is the handler sequence:

| Frame | `battle+0x14` |
|---|---|
| T0 | the spell's cast entry (`+0x1c` of its definition) |
| T0+1 | intro state `0x80120660` |
| T0+15 | the spell's setup handler |
| T0+16 | the tick machine |
| end | an end handler (not every spell, see below) |

T0 is the frame before `0x80120660` appears, which doesn't depend on how
long the game waited for everyone to go idle (32 to 118 frames across runs).
**The machine ends 3 frames before `battle+0x8` moves off the caster** (the
next actor is picked): that held for 30 of the 31 spells, and a handler
change lands exactly there in all of them but Voice of Earth. Machine
length = end - (T0+16). Not usable as the end marker:

- *Mid-machine handler hops.* Charm Arrow's machine moves from `0x80105130`
  to `0x801052f8` at T0+18 and to its end handler `0x80105858` at T0+242.
  Counting handler changes ends it at +18.
- *No end handler.* Voice of Earth stays on `0x80112ca8` until the next
  spell: the end is inferred (damage +336, next actor +340, so about 321).
- Charm Arrow's lag to the next actor is 4 frames, not 3 (226 by the
  handler, 227 by the rule).

`machine` is the tick machine's length in frames; `dmg` and `next` count
from T0. `-` means no HP change was seen (heals at full HP, buffs, status
spells, and instant-death spells on a target that resists them).

| Spell | id | machine | dmg | next |
|---|---|---|---|---|
| Flaming Arrows | 1 | 294 | 310 | 313 |
| Firestorm | 2 | 433 | 385 | 452 |
| Dancing Flames | 3 | 493 | 509 | 512 |
| Explosion | 4 | 831 | 847 | 850 |
| Final Flame | 29 | 681 | 696 | 700 |
| Scolding | 5 | 256 | 272 | 275 |
| Yell | 6 | 368 | - | 387 |
| Scream | 7 | 364-366 | 380-382 | 383-385 |
| Charm Arrow | 8 | 226 | 242 | 246 |
| Drops of Kindness | 9 | 306 | - | 325 |
| Fog of Deception | 10 | 411 | - | 430 |
| Water of Kindness | 11 | 306 | 262 | 325 |
| Rain of Kindness | 12 | 419-429 | 435-445 | 438-448 |
| Mother Ocean | 30 | 557 | 509 | 576 |
| Wind of Sleep | 13 | 416 | - | 435 |
| The Shredding | 14 | 264 | 224 | 283 |
| Healing Wind | 15 | 288 | - | 307 |
| Storm | 16 | 280 | 240 | 299 |
| Shining Wind | 31 | 535-539 | 551-555 | 554-558 |
| Angry Blow | 17 | 304 | 256 | 323 |
| Rainstorm | 18 | 408 | 361 | 427 |
| Raging Blow | 19 | 400 | 353 | 419 |
| Ball of Lightning | 20 | 384 | 400 | 403 |
| Thunder God | 32 | 484 | 500 | 503 |
| Clay Guardian | 21 | 336 | - | 355 |
| Voice of Earth | 22 | ~321 | 336 | 340 |
| Copper Flesh | 23 | 504 | - | 523 |
| Earthquake | 24 | 320 | 273 | 339 |
| Guardian of Earth | 33 | 474-480 | - | 493-499 |
| Deadly Fingertips | 25 | 575 | - | 594 |
| Black Shadow | 26 | 463 | 479 | 482 |
| Hell | 27 | 843 | - | 862 |
| Judgment | 28 | 504 | 520 | 523 |
| Scorched Earth | 34 | 562 | 515 | 581 |
| Storm Fang | 35 | 387 | 340 | 406 |
| Blazing Camp | 36 | 374 | 390 | 393 |
| Thor | 37 | 571 | 587 | 590 |
| Water Dragon | 38 | 671-681 | 592 | 690-700 |

**Unites (ids 34-38).** Measured with McDohl and Luc (roster id 26) both
queueing Rune slot 4 on the enemy, everyone else Defending. Rune cycle
Fire > Lightning > Water > Wind > Earth, each case shifting both one step:
Fire+Lightning is Blazing Camp, Lightning+Water Thor, Water+Wind Water
Dragon, Wind+Earth Storm Fang, Earth+Fire Scorched Earth. The cast-entry
handler in each run is the combo's own `+0x1c` pointer, not either solo
Lv4 spell. McDohl triggered all five on all seeds. A Unite is one cast on
the triggering caster's turn, and its length is the combo's own. Scorched
Earth, Storm Fang and Water Dragon deal damage before the machine ends
(+515, +340 and +592).

Hell is 859 frames from T0 (~14.3 s) and Black Shadow 479 (~8 s). The
earlier "260 vs 318" Hell figure is only its RNG phase. Four spells vary by
a few frames between seeds (Scream, Rain of Kindness, Shining Wind,
Guardian of Earth, and Water Dragon); they don't share a target type, and
the cause is not known.
Everything else is identical on every seed. Earthquake's static sum (320)
and Charm Arrow's (224) were right; Explosion, Final Flame and Shining Wind
were not.

**Target flags by spell.** The spell definition's `+0x16` word, read from
all 38 definitions in memory (2026-10-06), decoded in "`+0x16` flags word"
below: bit `0x8` = ally audience, low 2 bits = how
`battle_select_special_ability` validates `TargetIdx`. No other value, and
no bit above `0xA`, occurs in ids 1-38.

| `+0x16` | Validation | Spell ids |
|---|---|---|
| `0` | none, party effect | 33 |
| `1` | any living enemy, AOE | 2 3 4 8 10 13 16 18 22 24 |
| `1` | (continued) | 26 27 29 31 32 34 35 36 38 |
| `2` | one ally, as given | 21 23 |
| `3` | one enemy, reselect | 1 5 14 17 19 20 25 28 37 |
| `8` | ally audience, none (whole party) | 7 11 12 30 |
| `0xA` | one ally, as given | 6 9 15 |

For a scripted cast, `TargetIdx` is the caster's own index for `2` and
`0xA`, the first enemy for `3`, and `0` for the rest
(`scripts/MeasureSpellTiming.lua`). These runs had one enemy and six allies,
so a spell that scales with the number of targets would not show it here.

### Explosion

Setup (`spell_explosion_vfx_setup`) costs exactly 70 `rand()` calls, in an order that
matters since two of its three particle pools get their entire case3 firing schedule from
these same calls (no captured/baked table needed, unlike Hell's or Black Shadow's): 20
iterations (Pool B, 2 calls each — first call `% 0x48` becomes that object's firing tick,
second is an unused position roll) → 30 iterations (Pool C, 0 calls — fixed-arg
constructor) → 15 iterations (Pool A, 2 calls each — first call `% 0x60` becomes its firing
tick).

Phase 0 (64 ticks) and phase 1 (32 ticks): no RNG. Phase 2/case2 (128 ticks): Pool C, 30
particles sharing `spell_flamingarrow_spawn_particle` directly with Flaming Arrow (radius
150, not 100) — confirmed live, exact per-tick match across two independent seeds, that the
spawn gate is OFF only on tick-index 0 despite every particle starting inactive (all 30
burst-spawn together on tick 1 instead), and ON through every remaining tick including the
last; decay/despawn runs unconditionally all 128 ticks. Phase 3/case3 (96 ticks): a flat 1
`rand()`/tick camera-shake roll, plus Pool A (15 objects, cost 2 via
`vfx_activate_and_position_particle`) and Pool B (20 objects, cost 3 — one sound-variant
roll plus the same activate call) each firing at their setup-assigned schedule tick, PLUS a
confirmed **re-fire**: each particle's nested sprite-animation state (a generic,
non-spell-specific subsystem — `FUN_800e2a9c`/`FUN_800e2044`/`FUN_801238e0`) finishes its
animation a fixed number of ticks after activation, clears the particle's "flag" field for
exactly one tick, and — since its "schedule" field is already 0 from the first fire — the
decompile's idle-refill branch (loop2 for Pool A, loop4 for Pool B) immediately re-fires it,
if that re-fire tick still falls within the 96-tick window. Confirmed exact live, zero
mismatches on every tick across two independently-seeded captures: Pool A's cycle is exactly
55 ticks (re-fire costs 3 — the same 2 activation calls plus one extra fractional-write
roll); Pool B's cycle is exactly 60 ticks (re-fire costs 3, identical to its fresh-fire
cost). Neither pool can re-fire a second time within the window (max schedule + 2×cycle
always exceeds 95 for both). Damage (case5): `apply_elemental_multiplier(4, 0, target,
attacker, 700)`, zero RNG, same pattern as every other spell traced.

This model is fully resolved and validated exact per-tick (not just matching totals)
against two independently-seeded live captures: native seed `0x1b65fc6a` → 1220 total (70
setup + 916 phase2 + 234 phase3); fresh seed `0x11111111` → 1271 total (70 + 952 + 249).
`simulateExplosion` implements this exactly, including both pools' re-fire.

### Earthquake

Setup (`spell_earthquake_vfx_setup`) costs ~100 fixed `rand()` calls (20
particles × 4 for position/velocity, + 20 × 1 for a second pass). The
128-tick phase's shared per-tick epilogue costs one `rand()` per currently-
active particle (of 20), jittering its velocity/drift; a particle only goes
inactive once its X-position crosses a fixed threshold. Particles activate
via `vfx_activate_and_position_particle` (`FUN_80122eb4`, shared with
several other spells below) at a staggered spawn tick (`i*2`), costing 2
more `rand()` calls each — one of which sets the particle's random spawn
X-position, which drives the variable *lifetime* (and therefore the
variable total call count) per seed, since velocity itself is a fixed
decay constant. Damage: `apply_elemental_multiplier(4, 2, ..., 700)`.

### Charm Arrow

Uses a different mechanic entirely: a 16384-byte pre-baked gradient/"charm
heart" grid (`lib/CharmArrowGrid.lua`, a fixed template, not randomized).
Only the 64-tick final phase touches RNG: each tick repeatedly draws
`idx = rand() % 16384` and decays `grid[idx]` on a hit (zeroing a
nonzero-and-<16 cell, or masking a ≥16 cell to its low nibble; an
already-zero cell is a wasted retry) until exactly 160 successes land that
tick. Since successes remove occupancy over time, later ticks need more
retries — call count ramps from 286 (tick 1) to 608 (tick 64) for the
validated seed. Damage: `apply_elemental_multiplier(4, 5, ..., 500)`. The
observed "tail" after the cast (~12–16 calls) is two things: a fixed
10-call block (`battle_select_enemy_target` rerolling once per still-
eligible combatant as 4 Defending party members drop out one by one) plus a
variable 2–6 calls (whoever's action wins the next roll) — neither is Charm
Arrow's own cost.

### Flaming Arrow

20 particles, all starting inactive. Phase 1 (96 ticks, fixed) respawns any
inactive particle every tick via `spell_flamingarrow_spawn_particle`
(4 `rand()` calls: spawn position, an unused Z roll, a randomized velocity
scale `(rand()%64)+128`, a `rand()%100` lifetime). Despawns on lifetime<1
or `|trail_x>>12|<5`. `trail_x` is written as `trail_x & 0xfff |
(new_high_bits<<12)` — preserving whatever was already in the low 12
bits (baked into the simulator as `FlamingArrowResidualLow12`: 17 zeros,
then 78/2868/99 for slots 17–19). This *looks* like reused per-savestate
VFX-pool garbage (same partial-word-write pattern as Black Shadow's
genuine residue — see "Hell and Black Shadow" below), and was originally
documented as such from a single savestate dump.

`DAT_8017a030` (Flaming Arrow's own context pointer) is a genuinely
dynamic `heap_alloc`/`heap_free` arena, not a permanently-static buffer —
`spell_flamingarrow_cleanup` explicitly frees all 20 particle structs plus
the context every cast, the same lifecycle as the Soul Eater family. It's
also a **shared** arena: `spell_explosion_vfx_setup` and
`spell_dancingflames_vfx_setup` both `heap_alloc` into this exact slot,
and a previously-undocumented spell, **`spell_firestorm_cast_entry`**,
shares it too. Despite that genuine reuse, four real savestates all found
these low-12 bits byte-identical: `FlamingArrow.State` (fresh battle),
`FlamingArrow2ndCast.State` (a repeat Flaming Arrow cast — doesn't disturb
its own untouched field, so not a real test), `FlamingArrowAfterDeadlyFingertips.State`
(a different attack, but on the *other* arena — `SOUL_EATER_CTX`/`DAT_8017a060` —
so also not a same-arena test), and `FlamingArrowAfterFirestorm.State`
(the actually decisive test, since Firestorm shares this exact arena —
and still identical). So it's a fixed, spell-wide constant in practice
(same category as Hell's `HellSlotScale`), consistent with a simple
stack/arena allocator that returns to the same state once the prior
occupant fully frees before the next cast — Flaming Arrow's RNG cost does
**not** actually depend on prior VFX/battle activity, even though the
underlying memory is genuinely reused. `spell_flamingarrow_spawn_particle`
is also called directly by `spell_explosion_tick_state_machine` — the
same spawn helper shared across both spells. No damage-side RNG (no
elemental scaling call site is listed for this one at Lv1 — see the
21-caller table).

### Final Flame (seed-dependent: pool D respawns)

Decoded 2026-09-26 (`spell_finalflame_cast_entry` `0x80101e88`,
`spell_finalflame_vfx_setup` `0x80101eb0`,
`spell_finalflame_tick_state_machine` `0x80102280`, all created in Ghidra
this pass). Validated against 30 live seeds, **every tick exact**
(`scripts/CaptureFinalFlame.lua` 10 seeds, `CaptureFinalFlameSeeds.lua` 20
fresh ones; Cleo with the Rage Rune vs Zombie Dragon).
`simulateFinalFlame(seed)` in `lib/Magic.lua` takes the RNG state the frame
before setup runs.

Four particle pools, all activated through
`vfx_activate_and_position_particle` (always exactly 2 `rand()` calls):

| Source | When | `rand()` |
|---|---|---|
| setup | pool B/C scale, pool D start tick + scale | 120 |
| pool A (20) | case 1, start ticks 0, 3, ..., 57 | 20 x 3 = 60 |
| pool B (29) | case 2, start tick `floor(200k / 30)` | 29 x 2 = 58 |
| pool B's 30th | case 2 tick 180, activated by hand | 2 |
| pool D (30) | case 2, see below | 2 per fire |

Pool A's 3 per fire is an extra `rand() % 40` height on top of the 2.
Pool C spawns where a pool B particle crosses height 299, with no RNG.

**Pool D** is the only seed-dependent part. Each particle's start tick is
`rand() % 64 + 20` (drawn in setup), and its sprite (shared sheet
`DAT_800aa004`, seq 13) is non-looping: 11 frames x 5 = 55 updates. It
fires at its start tick; `FUN_801238e0` in the epilogue deactivates it when
the sprite ends; the next tick's case body re-activates any pool D particle
that has already fired and is inactive. So each fires every 55 ticks from
its start tick through case 2's last tick (295):

```
fires(s) = floor((295 - s) / 55) + 1
total    = 240 + 2 * sum(fires(s_k) for the 30 pool D particles)
```

Positions never change a count (pool B's height crossing only spawns pool
C, pool A's only deactivates it), so the total depends only on the seed:
no per-savestate residue to track. 530-538 across the 30 seeds.

**Phases** (own tick counter `ctx[0x7e]`, phase `ctx[0x7f]`): case 0, 64
ticks (flash, no RNG); case 1, 128; case 2, 296 (every 36th tick after 15,
each living enemy plays reaction script `0x8016f0d0`; extra effects from
tick 200); case 3, 96, then the damage
`apply_elemental_multiplier(5, Fire, target, caster, 900)` for every enemy
not out (no RNG); case 4 hands off to `LAB_80102c7c`.

**Ticks vs frames.** Cases 0, 1 and 3 run one tick per frame, but case 2's
ticks 201-295 each take two frames, identical in all 30 runs. It's only
the spell machine: Zombie Dragon's sprite animation kept counting down on
the stall frames, so the actor pass (and every busy window it times) runs
every frame. The IGT counter (`SESSION_FRAMECOUNT`) also advances every
frame. So Final Flame's 600 machine ticks take frames T0+16 to T0+696, and
the frame numbers in "Cast timing" above are the ones a sim should use. The
stretch starts exactly when the extra effects do (tick 200), so it's
probably draw-load related and could differ in a busier scene; it's only
been measured in this fight.

### Dancing Flames / Storm Fang (fixed constants, no seed dependence)

Dancing Flames: 15 embers, 2 `rand()` calls each at setup (30), then 4 more
identical 30-call reactivation waves in its 192-tick phase (a rhythmic
"flare up, die down" cycle) — 150 total, always.
`simulateDancingFlames()` returns the constant `150`.

Storm Fang (one of the 5 Magic Unite combo spells, Earth+Wind): 76
particles created at setup, the first 38 each cost 1 `rand()` (random
initial height), the rest are deterministic — 38 total, always, and the
entire tick-phase machine afterward has zero RNG.
`simulateStormFang()` returns the constant `38`.

### Shining Wind

Four particle pools (A/B/C/D, 20/20/30/20 objects), 120 `rand()` calls at
setup (all frame 0). Case 2: pools C+D activate together (all start
inactive) for a one-time 300-call burst. Case 3 (160 ticks) is the complex
part: Pool B fires once per object on a staggered schedule, checked in the
phase body (before the tick counter increments). Pool A uses the same
staggered schedule but is checked in the shared epilogue (after the
increment — a one-tick offset from B) and does not gate on "already
active" — it can numerically re-cross its own decaying countdown against
the ever-increasing tick counter and refire an already-active object,
producing a chaotic-looking but fully deterministic re-trigger pattern.
Pools C/D simply reactivate whenever inactive (6 `rand()` calls each). A
boundary quirk: case 3's own final tick (159) clears all pool-enable flags
before the shared epilogue runs, so nothing new can activate that exact
tick even though decay/process steps for already-active objects still
apply. Case 3 also runs at roughly half real framerate (a rendering quirk,
not an RNG-mechanism difference), which is why its real-frame duration
doesn't match its raw tick count. Damage: `apply_elemental_multiplier(5, 4,
..., 500)`.

### Hell and Black Shadow (Soul Eater family)

Both reuse the same 40-slot particle-vortex spawn function,
`spell_hell_spawn_particle` (`0x801137dc`, 4 `rand()` calls per respawn:
X circle-point, an unused Z roll, velocity scale `(rand()%64)+128`,
lifetime `rand()%120`), and both have a fixed-length RNG-consuming phase
(Hell: 128 ticks; Black Shadow: 80 ticks) — seed only affects *where*
particles spawn and how long they survive, never the tick count itself.
Each tick, a global `scaleAccum` value advances by a fixed step (a
deterministic vortex-rotation accumulator) and gets frozen into a
particle's `scale` field the moment that particle survives a tick — so a
particle's *first-ever* spawn uses whatever was already in its slot's
`scale` field, but every respawn after that uses the frozen `scaleAccum`.

**Hell's** 40-slot `scale` constant table is genuine spell-wide static
data, byte-identical across savestates — so Hell's total is a pure
function of the starting seed (~10320–12220 across 20 seeds). **Black
Shadow's** same field is uninitialized, stale VFX-pool memory that differs
per savestate — Black Shadow's RNG cost is not a pure function of seed
alone; it needs a one-time live capture of the per-savestate residual
table, which is exactly what
[Black_Shadow_Simulation_Workflow.md](../../notes/Black_Shadow_Simulation_Workflow.md)'s
tooling automates. `simulateBlackShadow` takes that table plus the
starting `scaleAccum` as explicit parameters; `simulateBlackShadowWind`/
`simulateBlackShadowBats` wrap two known captures.

Damage: Hell `apply_elemental_multiplier(4, 7, ..., 2)` (instant-death,
power is a non-HP sentinel); Black Shadow `apply_elemental_multiplier(2, 7,
..., 300)`.

`simulateHell`/`simulateBlackShadow` in `lib/Magic.lua`,
`TestHell`/`TestBlackShadow` in `tests/test_Magic.lua`.

### Judgment (Soul Eater Lv4)

`spell_judgment_cast_entry` (`0x80116638`) schedules
`spell_judgment_vfx_setup` (`0x80116660`), which hands off to
`spell_judgment_tick_state_machine` (`0x80116b7c`); the context is the shared
Soul Eater-family struct at `DAT_8017a060`. The eight phases run 64+32+64+64+
64+96+60+60 = 504 ticks, one tick per frame, which equals the measured
machine length. Damage is `apply_elemental_multiplier(4, 7, ..., 1500)` at
the end of the last phase, with no RNG.

`rand()` calls:

- **Setup, 30 calls in one frame.** For each of 15 bolt particles, a
  `rand()%48` (the bolt's first-spawn tick) and a scale roll.
- **Phase 5 only (96 ticks).** Four pool heads spawn at ticks 0/6/12/18 and
  respawn the tick after dying; a head's z starts at -300 and gains 20 per
  tick, so it lives 15 ticks and spawns every 15 (2 calls each, 50 in all).
  Bolts 4-14 spawn at their setup-rolled tick and respawn once their
  non-looping sprite ends (33 active frames, a spawn every 34 ticks), at 3
  calls each (`rand()%100` plus the shared helper's 2).
- **Total** = 80 + 3 x (22 + k), where k is the number of bolts 4-14 whose
  first tick is 27 or less, so 152-176.

Validated against 3 per-frame captures (`scripts/CaptureJudgment.lua`) and 20
injected seeds (`scripts/CaptureJudgmentSeeds.lua`), 0 mismatches.
`simulateJudgment` in `lib/Magic.lua`, `TestJudgment` in
`tests/test_Magic.lua` (expected values are the in-game counts, not simulator
output). The 6 `rand()` calls a few frames after the machine ends belong to
the next actor, not the spell.

### Drops of Kindness (Water Lv1)

`spell_drops_of_kindness_cast_entry` (`0x801058ac`) schedules
`spell_drops_of_kindness_vfx_setup` (`0x801058d4`), then
`spell_drops_of_kindness_tick_state_machine` (`0x80105bc8`), context
`DAT_8017a040`. Phases 64+32+90+60+60 = 306 ticks, equal to the measured
machine length. Setup rolls 3 values for each of 6 droplets (scale,
`rand()%100` depth, rotation) = 18 calls in one frame; the tick machine
has no `rand()`. Fixed 18 on all 20 live seeds
(`scripts/CaptureDropsSeeds.lua`). `simulateDropsOfKindness`,
`TestDropsOfKindness`.

### Fog of Deception (Water Lv2)

`spell_fog_of_deception_cast_entry` (`0x80106178`) schedules
`spell_fog_of_deception_vfx_setup` (`0x801061a0`), then
`spell_fog_of_deception_tick_state_machine` (`0x801062f0`), context
`DAT_8017a040`; the machine hands off to `0x80106844` when done. Nine
cases, 411 frames live. Neither setup, the machine nor its helpers call
`rand()`, and the effect itself is applied inside the machine (case 6:
`play_attack_animation` on each living enemy, and one enemy field scaled
by 4/5), so it has no roll of its own either.

Live, 20 injected seeds (`scripts/CaptureFogSeeds.lua`, Water Lv2 on
`SpellDuration.State`): 0 `rand()` calls from setup to the end handler,
always. The 6 calls in the 3 frames after it come just before the next actor
is picked (Judgment shows the same 6, and the following actors show 5 and
4), so they belong to the turn order, not the spell. I could not pin down
which byte the 4/5 scale lands on from the combatant-record diff
(`scripts/CaptureFogDiff.lua`), so the effect landing is not verified, only
that no `rand()` happens around it. `simulateFogOfDeception`,
`TestFogOfDeception`.

### Rain of Kindness (Water Lv4)

Water slot 3 is Water of Kindness (id 11); Rain of Kindness (id 12) is
slot 4. `spell_rain_of_kindness_cast_entry` (`0x8010726c`) schedules
`spell_rain_of_kindness_vfx_setup` (`0x80107294`), then
`spell_rain_of_kindness_tick_state_machine` (`0x80107630`), context
`DAT_8017a040`; the end handler is `0x80107ea4`. Six cases: 64+32+90+90+60+60
ticks. Case 5 heals every living party member for 300 (no rand).

Not flat: setup alone is a fixed 72 for a party of 6, but the rain adds
about 1450-1500 more.

- **Setup, 12 x party size calls.** 4 droplet particles per party member,
  3 `rand()` each (72 for 6, 60 for 5, both confirmed live).
- **Rain, 239 ticks.** Case 2 sets `ctx[0x55]` on its first tick and case 4
  clears it on its last, so the epilogue's spawn loop runs on 90 + 90 + 59
  ticks. Every inactive one of the 32 rain lines respawns via
  `FUN_80123e2c` (5 calls: x, a second axis, depth, speed, life). The speed
  is `rand()%5 + 10` units per tick; a line starts at z = -300, gains its
  speed every tick (the spawn tick included), and deactivates the tick it
  is seen with z > 0, respawning the tick after. Its period is therefore
  `300 // speed + 2` ticks (32/29/27/25/23). The life roll is stored in
  field `+0x5c` and never read.

Validated on 20 injected seeds with a party of 6
(`scripts/CaptureRainSeeds.lua`, 1527-1572) and 20 with a party of 5
(`RainOfKindness.State`, `scripts/CaptureRainSeeds5.lua`, 1515-1570), exact
totals, 0 mismatches. The check is total-only; no per-tick capture was
made. `simulateRainOfKindness(startSeed, partyCount)`,
`TestRainOfKindness`.

### Water of Kindness (Water Lv3)

`spell_water_of_kindness_cast_entry` (`0x801068cc`) schedules
`spell_water_of_kindness_vfx_setup` (`0x801068f4`), then
`spell_water_of_kindness_tick_state_machine` (`0x80106be4`), context
`DAT_8017a040`; the end handler is `0x801071b4`. Phases 64+32+90+60+60 =
306 ticks, equal to the measured machine length. Case 3 heals every living
party member for 300 (no rand).

Setup rolls 3 values for each of 4 droplets per party member (scale,
`rand()%200` depth, rotation) = 12 x party size. The tick machine and its
helpers call no `rand()`: unlike Rain of Kindness it has no rain-line
spawn, and every function it calls is one Rain's machine also calls. A
party of 6 gives a flat 72 on all 20 live seeds
(`scripts/CaptureWaterOfKindnessSeeds.lua`); a party of 5 gave 60 (observed
in-game by the user), confirming the 12-per-member scaling. `simulateWaterOfKindness(partyCount)`, `TestWaterOfKindness`.

### Mother Ocean (Flowing Lv4)

`spell_mother_ocean_cast_entry` (`0x80107fb4`) schedules
`spell_mother_ocean_vfx_setup` (`0x80107fdc`), then
`spell_mother_ocean_tick_state_machine` (`0x801082ec`), context
`DAT_8017a040`; the end handler is `0x80108a6c`. Seven cases. Case 5 restores
every party member to full HP and zeroes one byte of their combatant
record (meaning not identified); case 6 runs
`FUN_8012055c` per member, a formation swap.

**Static analysis only; no live capture yet.** Setup rolls 3 values for each
of 4 droplets per party member (scale, `rand()%60` depth, rotation) = 12 x
party size, the same as Water of Kindness. Neither the tick machine nor any
function it calls has `rand()`: the callees new to it are `FUN_80121ed8`
(GPU/GTE math) and `FUN_8012055c` -> `battle_swap_combatant_positions` ->
`play_attack_animation`, and the rest also appear in spells whose live totals
had no other source. So 72 for a party of 6, 60 for 5. `simulateMotherOcean`
has no test yet, since test values here come from the game.

Note: the phase sum (430) is well short of the live 557-frame machine
(damage at +509), so the machine does not run one tick per frame
throughout. This does not affect the rand count and was not investigated.

### Wind of Sleep (Wind Lv1)

`spell_wind_of_sleep_cast_entry` (`0x80108b58`) schedules
`spell_wind_of_sleep_vfx_setup` (`0x80108b80`), then
`spell_wind_of_sleep_tick_state_machine` (`0x80108d54`), context `DAT_8017a048`;
the end handler is `spell_wind_of_sleep_end_handler` (`0x80109358`, teardown only).
Six cases, 64+64+64+64+96+64 = 416 ticks, equal to the measured machine length.

- **Setup, 100 calls.** 50 particles, 2 `rand()` each.
- **Spawn loop, 200 + 4 per zero roll.** Case 2's first tick (machine tick
  128) sets `ctx[0x43]`; case 4's last tick clears it, so the shared
  epilogue's loop runs on ticks 128-350. Every inactive particle gets
  `vfx_randomize_sphere_particle(p, 200)` (3 calls) and a life roll
  `rand()%180` (1 call): 50 x 4 = 200 on tick 128. The next loop deactivates
  a particle whose life is below 1, and nothing else counts it down, so a
  particle respawns (4 more calls, the next tick) only after a life roll of
  exactly 0, a 1-in-180 chance per spawn. The native-seed run had two
  (8 calls in the frame after the 200).
- **Effect, 1 call per enemy.** Case 3 runs the hit-reaction script
  `DAT_8016de9c` on each eligible enemy (record byte `0`, attack data
  `+0x26 & 0x4000` clear). Its opcode 40 (`anim_op_roll_status_effect_chance`,
  status 5 = Sleep, chance 30) rolls once per enemy; the roll is >= 30, so
  it lands 70% of the time (enemy branch). The animation only reaches the
  opcode at machine tick ~360, after the spawn flag is cleared, so these
  draws never interleave with the particle ones: all 5 came in one frame.

So total = 300 + 4 x (zero life rolls) + (eligible enemies): 305-317 across
the 20 seeds with 5 enemies, 313 for the native seed. Validated by a per-frame
capture and 20 injected seeds on `WindOfSleep.State`
(`scripts/CaptureWindOfSleep.lua`; McDohl's rune was set to Wind, MP to 9),
0 mismatches.

**Eligibility.** The case-3 loop skips an enemy whose attack data
(`battle+0x1344` table, enemy id x 4) has `u16 +0x26 & 0x4000` set, which is
the immune-to-Sleep flag. Ain Gide, the lone enemy of `SpellDuration.State`,
has `+0x26 = 0x4003`, so he gets no hit script and no roll: that state gave
100 + 200 = 300 on the native seed and 300-304 across the same 20 seeds
(`scripts/CaptureWindOfSleepAinGide.lua`), exactly `simulateWindOfSleep(seed,
0)`. So both 5 eligible and 0 eligible are validated; a mix of the two was
not tested, nor were other enemy counts.

**Roll order and Sleep behavior (user-confirmed, not captured).** The rolls
go to enemies in enemy-index order. Sleep on an enemy has a 50% chance to
wear off at the start of each round, and a still-sleeping enemy skips its
turn.

The 6-10 calls after the end handler are the next actor's pick, not the spell.
`simulateWindOfSleep(startSeed, eligibleEnemies)`, `TestWindOfSleep`. The
simulator returns the call count only, not which enemy falls asleep.
