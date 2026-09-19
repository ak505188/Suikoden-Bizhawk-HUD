# Battle Damage Formula — investigation history

This is the history behind
[docs/game_mechanics/Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md):
corrections, dead ends, live-testing sessions, and open questions that
shaped the current clean write-up. Section headers below correspond to
sections in that doc.

## The central battle-state struct

`class_ptrs` offset was cited ambiguously as either `+0xF84` or `+0xF90` in
earlier session notes — resolved in favor of `+0xF84`, confirmed directly
from Ghidra's own decompiled pointer arithmetic once the struct was
formally typed.

Formalized as real Ghidra struct types (`BattleState`, `CombatantRec`,
`EnemyData`, `MonsterRecord`, `ClassPtrEntry`): the global pointer
(`DAT_8017be3c`, renamed `g_pBattleState`) is now typed `BattleState *`, and
every touching function decompiles with real field names instead of raw
offset arithmetic — verified across `calc_hit_chance`, `calc_damage`,
`apply_status_effect`, `apply_elemental_multiplier`, and `mark_enemy_
formation_slot_occupancy`. Large regions known to hold fields not yet
pinned down are left as explicit `undefined1[]` padding rather than guessed
at.

Still worth reconciling against the independently-derived RAM-side enemy
struct in
[Battles_and_Encounters.md](../docs/game_mechanics/Battles_and_Encounters.md#enemy-struct-60-bytes-per-enemy-libbattlelua-readenemytable)
(found via live memory reads, not disassembly).

## `calc_hit_chance`

The halving condition (Bucket-status for party members, Hazy-Rune check for
enemies) wasn't independently confirmed when this section was first
written — resolved later via the status-effects and passive-rune-effects
investigations below.

## Dodge and counter: from "does an enemy-side mechanic even exist" to fully confirmed

Prompted by the user asking directly whether an enemy can counter a party member's miss.
First pass traced `battle_execute_player_attack`/`check_dodge_counter` and correctly ruled
out that path for enemy-side counters (its eligibility guard structurally requires an enemy
attacker). Found a second mechanism in `battle_execute_enemy_attack`, keyed on the *target's*
`MonsterRecord+0x26` bit 1 — first write-up wrongly said this fires "on a hit"; re-reading the
decompile showed it's nested inside the same branch as `calc_hit_chance`'s failure, i.e. a
miss only, same shape as the party's own mechanic.

**Wrongly concluded the whole path was dead code.** A first static scan found bit 1 set on 47
of 96 unique monsters — common enough that, reasoning the user would have already noticed such
a mechanic, this was written up as "very likely dead code." **The user pushed back with real
game knowledge**: "I know for a fact that Sonya Shulen and Ain Gide can counter" — both were
already on the list, falsifying the conclusion outright, and flagged the disc scan itself was
undercounting (user: "I know there's over 100 enemies in the game," vs. the scan's 96).
Root-caused: the scanner only validated AI pointers against base `0x80010000` (boss-overlay
convention); per-area `*_data.bin` files load at `0x80080000` instead. Fixing this found 122
monsters and 38 with bit 1 set.

Closed the loop by confirming the exact opcode (26 = `anim_op_set_effect_flags`) and reading
all 6 living party members' own basic-Attack scripts live (`ZombieDragonStart.State`,
resolved via each combatant's live `EnemyData+8` `pActionScriptTable`, *not*
`pAttackDataTable[bId]`, which holds no valid rows for party roster IDs — a separate minor
gotcha worth remembering). Every script contained opcode 26; 5 of 6 set the checked bit on
themselves, Cleo sets it on her target instead. The user's own guess — "long range characters
can't be countered" — checked out exactly: Cleo is the only one of the 6 with weapon-reach
category 2 (ranged/any-row); the other five are melee/normal reach.

**Lesson**: two real corrections in one thread — a plain "hit" vs "miss" re-reading error, then
a much bigger "probably dead" conclusion drawn from data that was silently incomplete due to an
already-known-but-unapplied scanning quirk. A "this is rare" argument for "probably unused" is
only as good as the underlying survey — sanity-check a completeness claim against a number the
user might already know.

## Magic Unite spells

Not yet done: confirming the MGC/2 bonus and resistance-priority rules against the actual
consumer code (the `+0x14` handler isn't traced past `battle_check_magic_unite` itself); naming
Earth's/Water's Lv4/Lv5 spells (handler addresses known, not cross-referenced yet).

## The unique-rune ability table (`DAT_8016a630`)

Originally thought to be a simple two-value flag on an enemy/monster table; reading all 34
entries showed it's three-valued and `DAT_8016a630` is actually a separate special-ability
table for the 6 unique/single-character runes. Not yet determined: what flag-value-`2` entries
(unconditionally rejected) represent, or whether they're reachable some other way.

## Status effects

Found while investigating what looked like an unexplored counterattack gate
(`anim_op_roll_status_effect_chance`) — tracing its callees revealed a full status system, not
a counter. Two fields already referenced elsewhere before their real meaning was known
(`calc_hit_chance`'s Bucket check, `Turn_Order.md`'s "can't act" note) turned out to be 2 of the
same 9 statuses.

`id1`/`id2`/`id3` being one escalating ailment (not three separate ones) came from the user's
own game knowledge. The `id5`/`id7` `ActionTag=1` behavior was initially misread as forcing
`ActionType`=Attack; live-testing corrected this — it marks the turn already-resolved without
going through normal action selection, so `ActionType` reads back as the `255` sentinel and the
turn is silently skipped.

**Live-editing sessions**: a menu-paused savestate attempt was inconclusive (frame-advancing
alone never progresses a round waiting on the Fight/Run menu). Switching to a mid-round
savestate and injecting input via `joypad.set` worked. **Safety finding**: poking the
per-status duration-slot table (`+0x30a0`) alongside the bitmask hung the battle completely —
that region isn't safe to write blindly; a bitmask-only poke on `+0x4a` was always safe.

Round-end testing confirmed `id3` (vanishes/KO'd, matching a real death) and `id5`
(`ActionType` reads `255` after a round — tentatively named "Sleep" per the user's own
best guess, treated as provisional). `id7`/`id8` use their own dedicated countdown fields
rather than the generic duration-slot table.

Further rounds of testing (multiple ids against a controlled HP-trajectory baseline) confirmed
`id0` (Poison) as a clean periodic-damage signature, and `id8` (**confirmed by the user as
Copper Flesh**, HP-locked for 3 turns) once its dedicated countdown byte was properly seeded.
`id1`/`id2`/`id6` showed no detectable effect within a short window — explained afterward by
the balloon-escalation mechanic (`id1`/`id2`) and (for `id6`) the afflicted character simply
never trying to cast a spell during the test.

**Mechanism correction**: the real HP-lock check lives in `apply_hp_damage_display`
(`0x800e1654`, `if (StatusFlags & 0x8000) hp_delta = 0`), which — corrected after a full
disassembly read — never writes `HP_Current` directly; it only accumulates into a
`nHpDeltaAccumulator` (`+0x4e`) field for later application and the floating damage-number
display. Also corrected: this function's `hp_delta` sign convention is negative=healing,
positive=damage (documented backwards in an earlier pass) — this directly explains an earlier
Sunbeam mixup below.

### Passive rune effects — major correction

**Major correction, per the user's own game knowledge**: everything documented earlier as
"`equip_ptr+0x4c`, the weapon-type byte" was wrong — `equip_ptr` (via `class_ptrs[idx]->+0x1c`)
is the character's persistent Stats address, and `+0x4c` is `Rune.Id`. There is no separate
weapon-type struct.

Per-rune notes gathered while mapping the table now in docs: **Killer**/**Counter** confirmed
by the user directly. **Hazy** confirmed, correcting an earlier misread that had the
attacker/target argument backwards. **Gale** (doubles SPD) fits the name exactly. **Sunbeam**
corrected from an earlier "damage" guess to Regen — confirmed by the user: "+5, heals 1 HP of
the party per step on the field." **Fortune**: confirmed by the user ("doubles XP growth"), but
an earlier pass believed it doubled a *separate* field (`+0x10`) from an "aggro score" (`+0x14")
— that was wrong on two levels: there never was an aggro score (see the `battle_calc_enemy_
aggro` misidentification below), and `+0x10`/`+0x14` are the same address on every loop
iteration, algebraically, not two overlapping-looking fields. **Prosperity**: confirmed by the
user and independently verified via 2 monsters' static gold values matching Suikoden-RNG-lib
exactly. **Turtle**, **Holy**, **Champion's** are plausible but only loosely confirmed.
**Phero**: confirmed by the user exactly ("makes characters cover for the opposing gender").

All 29 `lbu ...,0x4c(...)` sites in `main.exe` were traced: 2 were false positives on the
unrelated `id7`/`id8` status-countdown struct, the rest are genuine `Rune.Id` reads. One
remains unresolved: `0x800f81e8` compares two combatants' MGC difference (`<10`) and
conditionally calls the RNG wrapper.

### Cover mechanic

Prompted by the user asking about cover mechanics while discussing Phero Rune. The story-pairing
lookup table's layout was initially off by one byte before landing on the correct interleaved
`(self_id, partner_id)` format — every pairing matches a real canon relationship (Eileen/Lepant
married, Tai Ho/Yam Koo the fishing duo, etc.), confirming it's a hardcoded story table.
classData layout search exhausted all 31 `+0xf84` access sites plus the full call graph
downstream of the cover functions with no new fields found; a handful of sites with no Ghidra
function boundary remain genuinely unchecked.

Real status names (`id7`="Unbalanced", exact match via `battle_menu_compute_command_
availability`) and `id4`="Bucket" (user-confirmed, with the caveat that a bitmask-only poke test
can't reproduce the real bucket icon since it needs a live-spawned handle) both confirmed per
the user's own game knowledge.

### Poison — full solve

Two entirely separate mechanisms found while tracing Neclord's Bats attack: the RNG-consuming
infliction roll, and the fully-deterministic per-tick damage. Duration's specific
decrement-and-clear consumer wasn't located this pass — a genuine open item separate from the
now-solved damage formula.

## Formation management: front-row auto-backfill

Found while chasing the status-effect ids into their round-end processing —
`battle_process_round_end_status_and_formation` also runs this system, resolving the
long-standing `monster_record+0x11` mystery. Neither this function nor its callee existed as a
disassembled Ghidra function until this investigation created them, meaning every earlier
"exhaustive" `+0x11` search was structurally blind to this code — worth remembering that an
exhaustive instruction search is only as exhaustive as what Ghidra has already disassembled.
This also resolves Gigantes' sprite-height/formation-footprint mismatch (tallest sprite
checked, but only needs 1 slot).

## `calc_hit_chance`/`check_critical_hit`/`apply_elemental_multiplier`

Killer-Rune crit doubling confirmed per the user's game knowledge. `apply_elemental_
multiplier`'s formula confirmed via a live cast prediction matching observed damage exactly.
Called from 21 sites; `get_xrefs_to` only found 17 — 4 more sat in undisassembled bytes
invisible to xref analysis and were found by a raw byte-pattern search for the `jal` opcode
encoding. Worth doing this completeness check whenever a suspiciously-round xref count comes
out of a region with large undefined-code gaps.

## Enemy elemental attacks: the third damage formula — full investigation arc

One of the longest-running open threads: Zombie Dragon's fire-breath damage was confirmed by
exact live RNG matching to be MGC-based, contradicting `calc_damage`'s ATK-DEF shape — every
traceable call site computed ATK-DEF, yet the live numbers matched `130 − target.MGC` exactly
(6/6 targets, including a 0.5× "resist" hit). Re-tracing the full call graph downstream of
`battle_execute_enemy_attack` showed every damage-computing branch actually found (normal, crit,
cover) calls the ordinary `calc_damage` (ATK-DEF) — none reach an MGC formula. Ruled out
"targets coincidentally had DEF==MGC" via a live read (clearly different values per target).

A full opcode audit (all 45 animation-script opcodes) found none of them touch stat fields or
call `calc_damage`/`apply_hp_damage_display` — purely visual. Also found `RngCallbackTable`
(`BattleState+0x1258`) is a static `main.exe` table, not per-battle heap data as previously
assumed — meaning overlay code *could* reach `calc_damage` indirectly through it, but no such
caller was found in Zombie Dragon's own functions at that point.

Re-validated the original 6-target match completely from scratch (fresh emulator instance,
independently-simulated LCG, real HP deltas) — reproduced exactly, and MGC-MGC clearly fit
where ATK-DEF was wildly off for every target.

**A previously-undocumented VFX subsystem** (identified by its own debug string, "`fire func
%d`") was found via a raw byte-pattern search for the cross-overlay callback-table pointer.
Fully parsed — zero damage calls anywhere in it — and an indirect-call audit initially found no
path to it from either confirmed dispatch function, leading to a **wrong conclusion that it was
dead code**.

**Resolved**: the user directly challenged the dead-code conclusion ("does it call RNG? that
would disprove it's dead"), prompting a closer re-read of the tick state machine — once its
internal tick counter passes 249, it loops every living party member and calls `RngCallbackTable`
slot 86 (`calc_rune_element_attack_damage`), a completely separate formula function, explaining
why a direct xref search on `calc_damage` never found it. Confirmed live: the target showing the
0.5× "resist" ratio had Soul Eater equipped (category-7 universal resist, not an element match);
a Fire-Rune target took full damage (Fire doesn't resist Fire Breath); Resurrection Rune
confirmed live to reduce damage too.

**A real compiled bug, found and confirmed live**: moving non-Fire-Rune characters into party
slot 6 reduced Fire Breath damage despite none of their runes being in the resistance table.
Raw disassembly showed why: for any `Rune.Id` not in the explicit table, the switch jumps to the
halving comparison without writing the "category" register (`$s1`), which the caller's own
damage loop is reusing as its target-slot counter — a register-reuse bug that always favors the
player. Confirmed by the user's own test results (Cleo's Fire Rune masks the bug, everyone
else's doesn't). A byte-pattern search across every touched overlay found 11+ more call sites
across 7 bosses/monsters with the same bug — only the original Zombie Dragon/slot-6 case is
confirmed in actual gameplay, the rest are static predictions.

The multi-target mechanism (`battle_enemy_attack_advance_multitarget`, gated on Double-Beat
Rune) describes real code, but the empirically-confirmed Fire Breath damage comes from the
separate `fire_func`/`calc_rune_element_attack_damage` path instead — likely because Zombie
Dragon's own equip check doesn't actually evaluate true during a real cast, meaning this
multi-target mechanism may belong to a different monster/move sharing the same generic
functions. Not confirmed further.

## Neclord's real Castle fight

Following [Enemy_AI_Tracing_Methodology.md](./Enemy_AI_Tracing_Methodology.md) with two
user-supplied savestates once static analysis hit a wall on the poison mechanism. The "always
uses its one special move" note was incomplete, not wrong — the real move choice (a 3-way
split) lives in the continuation, not the target-selection function.

**Wrongly concluded all three scripts share one damage handler** (inferred from code proximity).
**The user, who knows Neclord's real moveset, corrected this directly**: AoE Wind, AoE
Lightning, and a single-target physical bat-swarm attack. Tracing each script's own actual
damage call site confirmed exactly that. Lesson: trace the specific call site for each claimed
outcome rather than inferring from a plausible-looking nearby function.

Bats' poison mechanism resisted every static lead (no `apply_status_effect` call visible in the
tick machine's own decompile) and was resolved by tracing RNG advancement end-to-end, which
surfaced the poison call site as a byproduct — 86 total `rand()` calls for a Bats attack. One
correction along the way: a savestate labeled "before a Wind attack" was actually pre-Lightning,
settled by the formula's own prediction plus the user's follow-up confirmation.

All three damage formulas bit-exact confirmed (13/13 targets), including the register-reuse
resistance bug on Lightning (2 different targets, ruling out a naive "target index == element"
explanation for the bug's exact trigger condition, though the real trigger still isn't pinned
down). Bats matched `calc_damage`'s own Defend-halving rule exactly once accounting for all 6
targets Defending.

## Two identity corrections surfaced along the way

**"Dragon" is not the final boss.** This project had labeled `dragon_overlay.bin`'s monster (HP
6000) "the final boss" based only on stat matching against an external reference, never
confirmed via her own name. A charmap search for "Dragon"/"Golden Hydra" found neither as plain
text; a disc-wide "Hydra" search found exactly one hit, `vzv.bin` — the real final boss. "Dragon"
herself remains a separate, real boss.

**`vc3.bin` hosts multiple monsters, confirmed**: already had CrimsonDwarf documented there; a
fresh pass investigating a new slot-86 call site found a second AI function in the same file,
`gigantes_ai_select_target_and_move`.

## How monster overlays are actually organized

No internal "monster directory" structure exists in overlay files. The real answer is on the
Lua side: `lib/EncounterTable.lua` lists every area's random-encounter roster by name.
Cross-referencing `vc3.bin`'s known bosses against `EncounterTable.lua`'s `DWARVES_VAULT` entry
and charmap-searching for those names confirmed both Death Machine variants also live in
`vc3.bin`. Gotcha: `EncounterTable.lua` sometimes appends a human-added disambiguating suffix
(`"Death Machine R"`) not present in the real charmap-encoded name — strip it before encoding.

## Dead end: `vc61.bin` ("Dragon")'s garbled AI code is NOT explained by LZ compression

Goal was reading boss AI statically for small overlays like `vc61.bin` (31KB) where the monster
record decodes correctly but the AI code at the expected address isn't valid MIPS. Found and
fully decompiled `lz_decompress` (`0x800c3144`), reimplemented in Python, tested several ways —
none produced valid code; every actual caller of this function in Ghidra decompresses into
texture/sprite buffers only, never code overlays. Ruled out.

**Correction**: `vc61.bin` is genuinely Dragon's own disc file, not unrelated — a later pass
found its monster record decodes perfectly (name, level, HP, PWR, DEF, SPD, MGC, LUK, and the
AI pointer value all matching the live-derived data exactly) at a meaningful file offset. That
many independent structured fields agreeing cannot be coincidence, unlike a raw byte-diff
percentage. The real explanation for why this overlay's code doesn't decode directly under the
naive mapping remains open. Dragon herself was ultimately resolved via a user-supplied savestate
inside the fight instead (name-search couldn't work — "Dragon" is too short/common a string).

**Sydonia's counterattack investigation**: a suspicious debug string ("`sid wait`") led to
tracing what first looked like a Varkas tag-team combo, corrected (user pushback + re-reading
`play_attack_animation`'s semantics) to a genuine counterattack structure. Her own special-move
script never calls the required opcode 26 on herself, so it's confirmed dead/leftover code — the
user confirmed live it never triggers in the actual fight.

## Dragon's move selection

Fully solved and validated to a perfect 92/92 across three independent random-seed sweeps (12 +
30 + 50 seeds).

<details>
<summary>Investigation notes (two wrong turns, both caught by direct user challenge)</summary>

The move-choice roll's location took three passes. First guess — a function with the identical
formula, matching ~90% of a live sample — turned out to never actually execute for Dragon's
turn (its target-lock fields are written once, by the initial scan, and never touched again);
the formula match was coincidental. Chasing the ~10% gap, a VFX-interleaving theory was
proposed and the user caught the flaw directly ("the vfx rng rolls start after a move is
selected, which means they can't interfere") — retracted. The real location,
`dragon_special_move_real_frame_callback`, was found by abandoning the dead coroutine chain and
checking `main.exe`'s separate per-frame callback system instead, confirmed by directly
watching its install address.

Even after finding the right function, every mismatch (4/42) had the target-scan reject all 3
candidates — the model was rolling once on an all-reject outcome instead of retrying the whole
scan fresh. Fixing the retry loop scored 42/42, then 50/50 independently.

**Lesson**: a formula matching most of a live sample isn't proof of causation — verify the
specific code path actually executes before treating a numeric match as confirmation. And a
"mostly right" result worth checking for a 100%-clean split by some categorical variable before
accepting it as noise — that split is the signature of a real, fixable bug.
</details>

### Lightning's RNG cost — errors avoided

- Naive per-frame "did the RNG value change" counting undercounted by an order of magnitude —
  many `rand()` calls can land within one frame and collapse into "one change." Fixed by letting
  the RNG settle (unchanged 30 frames) then forward-simulating the exact call count.
- A red herring: the function called right after move-choice resolves is a texture-decompression
  waiter, not the particle driver — the real driver is what it hands off to.
- First simulator draft undercounted by missing position-based particle deactivation entirely.
- Second draft was still off ~5-10% due to a test-harness bug (skipping the already-validated
  target-scan/move-choice rolls that must run first, not a mechanism bug) — chaining them
  correctly produced bit-exact matches on all 16 seeds.

### Dragon's damage formula

User's hypothesis: "same structure as Zombie Dragon, but might use ATK instead of MGC." Confirmed
the structure, refuted the ATK guess — both moves use MGC, confirmed 3 independent ways
(decompile, live memory check showing distinct ATK/MGC values, and exact damage prediction
matches, 8/8 + 5/6 targets). Fire Breath's register-reuse bug directly confirmed: 5/6 targets
matched the plain formula, the 6th only matched once the extra halving was included — the
mismatch was the bug firing, not a formula error.

## Queen Ant's full moveset and the 3 accompanying ants — a long correction chain

User: "I want to understand the behavior of all enemies" in the Mt. Seifu Queen Ant fight. No
savestate was available initially, so the first pass was decompile-only and **wrongly concluded
her ~51% attack branch was visual-only, dealing no damage** — the user caught this immediately
("she has an AoE magic that hits all characters") and supplied a savestate. The mistake was the
same class as Neclord's hidden Poison roll: checking only C-level tick functions when the real
damage call lives in script-installed per-frame coroutine code with no C-level xrefs. Live
capture confirmed all 5 party members taking damage in one round, in 5 different amounts —
exactly the AoE signature described.

The "3 ants" initially appeared to have no independent decision-making when Queen Ant triggers
them. Move-choice probability was brute-forced exactly: AoE Earth 51.001%, CommandAnts 48.999%,
and CommandAnts confirmed to cost zero `rand()` calls even as a no-op.

**Major correction**, prompted by the user noticing the ants are faster than Queen Ant: turn
order (`weight = SPD*10 - 5 + rand()%10`) means Soldier Ant's weight range `[215,224]` never
overlaps Queen Ant's `[195,204]` — every living ant is *algebraically guaranteed* to act before
Queen Ant, every time. This retracted two earlier "findings" about ant target attribution and
RNG cost that were, unknowingly, observations of the ants' own independent turns, not of Queen
commanding anyone — verified directly by checking each "commanded" ant's actual continuation
pointer (always the generic single-attack resolver, never Queen's own commanded-attack function,
which has never been observed to fire). **Lesson: a plausible-looking target+damage match isn't
proof you're watching the function you think you are — verify the actual continuation-pointer
address, not just outcome consistency.**

A follow-up validation pass (`scripts/TraceQueenAntMoveSelection.lua`) bit-exact confirmed the
move-selection threshold, AoE RNG cost (dead slots cost 0 rolls), and AoE damage for all 4
targets. **In-spec test-injection lesson**: a first attempt boosted target HP to a flat 9999,
which overshot every target's own max and triggered an unrelated "clamp to max" correction that
erased the AoE's own damage before it could be read; corrected to `HPMax - 1` and got a clean
match — keep injected test values in-spec, not just "large enough."

An earlier "slot 3 register-reuse bug" claim was retracted after a clean counterexample showed
slot 3's live damage matching the plain formula, not the halved prediction — it only disproves
"slot 3 always halves," not that some other condition could still cause an occasional halving.

Soldier Ant's 77%/23% split and DoubleStrike formula were live-validated for the first time this
pass — 2 real DoubleStrike instances captured, one exact match, one where the doubled roll
exceeded the target's real max HP entirely (fixed by raising `HPMax` itself before testing, not
just current HP past a stale max).

**Open ends**: whether the ant count is always exactly 3, the exact opcode-level trigger chain
for the AoE cast install, an unidentified precondition bit on the command-branch counter, whether
any condition still causes an accidental resistance halving in the AoE loop, and
`ant_commanded_attack_damage`'s real RNG cost (never observed to actually fire) all remain
untested.

### Queen Ant's round-3 battle-end and ant-respawn mechanic

Prompted by the user's own game knowledge ("the 3rd turn of Queen Ant always ends the fight").
A user-supplied savestate right at round 3 gave the first live confirmation that the
`+0x1330`/`+0x1334` scripted-turn-override hook is actually armed in a real encounter. The
"declare victory" step itself wasn't traced further (leads to a generic coroutine-state write).
`SyncSignals+4` is also set by the unrelated Ted-vs-Queen-Ant fight for a clearly different
purpose (forcing a turn) — better understood as a general resync signal than literally "end the
battle."

### The scripted Ted-vs-Queen-Ant "forced Hell cast" fight

The user's second suggested candidate for the same hook, checked with another user-supplied
savestate. As a side benefit, the forced cast's `AbilitySlot=3` is independent confirmation that
Hell really is cast via slot 3 (level 3) in practice — see the open Hell-numbering question
below.

## Regular (non-boss) enemy AI

Checked whether ordinary field encounters share story bosses' hand-scripted-per-monster AI
shape, or some generic routine — refuted the "regular enemies use a shared routine" hypothesis.
**Killer Rabbit** (user-confirmed genuine long-range targeting) surfaced an important technical
correction: `b_data.bin` (and other per-area `X_data.bin` files) load at runtime base
`0x80080000`, not `0x80010000` like boss overlays — the same base-address bug that had earlier
misled an EarthGolem/`h_data.bin` investigation. A byte-pattern search for reads of offset
`0x11` across the entire file found zero hits — strong evidence against `+0x11` being any kind
of range mechanism even for a monster with confirmed long-range behavior.

## Open questions / not yet done

- ~~Full Ghidra struct definitions~~ — done: `BattleState`, `CombatantRec`, `EnemyData`,
  `MonsterRecord`, `ClassPtrEntry` are real Ghidra types. The suspected separate "equipment/class
  record" turned out to just be the already-known persistent Stats struct.
- ~~AI/enemy action selection~~ — resolved for Zombie Dragon and generalized to 9 more regular
  monsters via the static disc-file technique; only Zombie Dragon and Killer Rabbit are
  behaviorally live-validated at this point in the project. 3 template shapes identified:
  plain front-row-scan+Attack, a move-gate variant, and a leap-clone long-range variant.
- ~~Whether `g_abWeaponTypeToElement` lines up with the magic-side element numbering~~ —
  resolved: yes, one unified enum, confirmed directly in `calc_damage`'s own decompile.
- `0x80116078`'s (Hell's) `a0=4` still doesn't match its confirmed identity (should be level 3)
  — behavior confirms the spell, the numbering discrepancy is unexplained. The Ted-vs-Queen-Ant
  fight's forced `AbilitySlot=3` is independent supporting evidence for "should be level 3."
- Suikoden-RNG-lib has at least one confirmed inaccuracy (Charm Arrow: lists 400 dmg, real value
  is 500) — treat its damage numbers as a strong lead, not ground truth.
- The Zombie Dragon third-formula ATK-DEF-vs-MGC contradiction narrowed to: the monster's own
  attack script must override the damage with its own MGC-based opcode — that opcode hasn't been
  located (would need the fire-breath script bytecode parsed end-to-end); later resolved, see the
  `fire_func` VFX-subsystem entry above.
- Poison's duration-slot decrement-and-clear consumer wasn't located.
- Queen Ant open ends listed above; Dagon's branch-polarity uncertainty and the general caveat
  that Slasher Rabbit/Rabbit Bird/Dagon are structural-only reads with no live validation.
- ~~`MonsterRecord+0x2c`'s consuming code~~ — RESOLVED. Every technique anchored on
  round-combat-resolution code failed first (a `search_instructions` sweep, a hook-free memory
  scan, and live memory-hooking — confirmed completely non-functional for this PSX core in this
  BizHawk build, `onmemoryread`/`onmemorywrite` never fire even though `onframeend` does). The
  real reason: the actual consumer lives in a region of `main.exe` Ghidra had never carved into a
  `Function`, so both `get_xrefs_to` and `search_instructions` silently skip over it. Found by
  manually walking backward from a live call site through the battle round-state dispatcher to
  its root init call, `battle_init_sequence`. See docs for the full resolved mechanism
  (`battle_load_enemy_combatants` → `build_sprite_poly_resource`/`apply_sprite_texture_coords`).
- EnemyData's unexplored byte ranges: while tracing `+0x2c`, noticed `MonsterRecord` isn't
  actually 54 bytes — it's 64, with 10 more real bytes past `wGoldDrop` nobody had scanned.
  `+0x3c`/`+0x3e` turned out to copy verbatim into `EnemyData.nSpriteOffsetX`/`Y` — a per-monster
  sprite-centering pixel nudge, confirmed via the party-side analog hardcoding `(0,0)` for every
  character.
- ~~`+0x36`/`+0x38`/`+0x3a`'s meaning~~ — IDENTIFIED, correcting a wrong same-session conclusion.
  Checked every caller of the 3 sprite-resource functions, a statistical correlation pass, and a
  full 2MB main-RAM literal-value scan — all came up empty, plus a raw byte-pattern search for
  every load instruction referencing these offsets across `main.exe` and 3 overlays also found
  nothing. On the strength of those negatives, wrongly concluded these bytes were unused
  build-pipeline artifacts. **The user corrected this immediately**: each 2-byte field is
  actually two independent bytes — item ID and drop chance, 3 drop slots per monster — a layout
  already implemented in this project's own `lib/Battle.lua:readEnemyTable`, a file this
  investigation never cross-checked before concluding "unused." Real lesson: exhausting RE
  techniques on a *guessed* field shape doesn't rule out a different real shape the project's own
  tooling already knew about.
- Drop-roll consumer chase: first anchored on `BattleState+0x1260` (the gold-pool accumulator),
  which only led to the Bribe menu's cost-check logic (a genuine, previously-undocumented
  mechanic: cost = 3× enemy gold pool) — not drop-related. ~~Drop-roll/gold-award consumer~~ —
  FOUND by switching to a dynamic approach: won a live battle (`chooseRoundOption` +
  **`confirmRound`** — the critical fix, since `chooseRoundOption` alone never starts the round)
  and watched the per-slot continuation-pointer arrays for new addresses after Gigantes' death,
  surfacing a previously-unexplored results-screen module. Walked it forward until
  `search_instructions` on the rare staged-item-offset pointed straight at
  `battle_process_enemy_turns`. See docs for the full confirmed mechanic (uniform random slot,
  direct percentage chance, one item max per battle, Prosperity Rune's exact doubling condition).
- ~~`EnemyData`'s `aUnk_0x10`~~ — PARTIALLY RESOLVED: a live per-frame diff of Gigantes' idle
  round found the idle sway animation (`bIdleSwayTimer` counting down, `nSIdleSwayZStep` feeding
  `nRefPosZ` every frame). Most of the range stayed at 0 through the idle trace and remains
  unexplored — likely only used by other animation states.
- ~~`battle_calc_enemy_aggro`'s real purpose~~ — CORRECTED: misidentified by an earlier session
  (complete with a detailed "live-verified aggro values" writeup that was entirely wrong). It's
  the EXP award formula, confirmed when the user supplied the exact mechanic unprompted and every
  one of its 30 table entries matched a live read byte-for-byte. Proof independent of the table
  match: its output buffer is heap-allocated only at battle end, and the function it was claimed
  to feed doesn't reference that buffer at all. Renamed to `battle_calc_party_exp_award`. This
  also retroactively resolves the earlier "Fortune doubles a separate field" confusion — there
  was only ever one field.
- ~~`EnemyData.aUnk_0x42`~~ — RESOLVED, per the user's suggestion to "rig a guaranteed miss" once
  a genuinely long trace proved infeasible for other reasons. True 100% guaranteed misses are
  impossible (`calc_hit_chance` clamps to [60,99]) — confirmed along the way that a live SKL read
  stays stale for ~4 frames after `confirmRound()` before settling, a timing gotcha worth
  remembering for any stat-based rig. Getting a long enough trace took several fixes: dropping
  already-understood per-frame diffing (the real bottleneck was logging I/O volume, not emulation
  speed — `client.speedmode`/`invisibleemulation` made no measurable difference); re-confirming
  Free Will every round (a first long trace came back "0 changes," a false negative from the
  round-menu reappearing and needing re-confirmation); and re-applying the SKL rig every round
  (a sibling stat-refresh function silently undoes a one-time edit). With those fixed, a 13-round
  trace found `EnemyData+0x42`-`+0x5b` lights up specifically during Gigantes' AOE attack, not
  ordinary hits/misses — see docs for the full field-by-field writeup.
- Follow-up on `bUnk_0x43`/`aUnk_0x44`: blind searches for direct writes came up empty (same
  undisassembled-bytes blind spot as `+0x2c`). Found `pVfxEffectHandler`'s true type (a function
  pointer, not raw data) via `anim_op_spawn_sub_actor_from_table_slot`'s own write to the same
  struct offset on a freshly-spawned sub-actor — but whether this is the same code path that lit
  up on Gigantes' own slot wasn't resolved without decoding her own script bytecode.
- Decoded Gigantes' own script bytecode per go-ahead ("Yes, decode her script bytecode"). Her
  `MonsterRecord+0x28` slot 6 turned out to be a native compiled function (not bytecode), matching
  the Zombie Dragon precedent. Traced the full 5-function AOE cast chain end-to-end and confirmed
  none of it writes `EnemyData+0x43`/`+0x44`-`+0x53` — every byte of scratch state lives in heap
  buffers instead. Cross-checked against Zombie Dragon's own independent Fire Breath chain
  (`continue`, per the user) — same result. Two structurally independent monsters' elaborate
  special-move chains both avoiding these bytes is strong evidence they're simply unused padding
  in this build, not exhaustive proof (the other 122 monsters' own custom slots weren't checked).
  See docs' "Live EnemyData fields" section for the full chain writeup; all functions renamed and
  commented in `vc3.bin`/`enemy_ai_overlay.bin`, both programs saved.
