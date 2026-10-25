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

**2026-09-27 — the above was wrong.** The "counterattack" is Sydonia's own special-move damage
step (renamed `sydonia_special_apply_damage`): `calc_damage(Sydonia, target) * 4 / 3`, no hit or
crit roll. Her special script does set the impact bit (opcode 26, mask 0x2, at f79 per the
walker) — the 2026-09-06 hand parse of `0x800700c0` missed it. The user flagged that her damage
didn't match expectations; a one-off verify script (since removed) then matched 11/11 special hits to
the ×4/3 formula. The old "never triggers" read was most likely the counter interpretation (no
reprisal was ever seen), not evidence the function doesn't run. Lesson: a continuation installed
at `+0x50` that polls the impact bit is a damage step until shown otherwise.

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

## 2026-09-27 corrections

- **Opcode 40 direction.** The general write-up said the roll was inverted for everyone
  (`roll < chance` = skip). Re-read from the decompile: that's the enemy branch only; a party
  member gets the status when `roll < chance` (so Pahn's/Kasumi's Unite Unbalanced roll, chance
  100, always lands). The Poison section already had the party direction right.
- **Unite menu eligibility.** "Item/Unite gated only by availability, never by status" was wrong
  for Unite: `compute_unite_eligible_slots` checks every participant, the commanded character
  included, for `+0x4a & 0x61` (Poison/Sleep/Unbalanced), and only searches from the commanded
  character's menu position onward. First re-read (by me) wrongly exempted the character's own
  status; the user corrected it (an Unbalanced character can never Unite) and confirmed the
  command-order rule live. The `DAT_80179fe8+0xb4` flag is still untraced.
- **Unite participant order.** Read straight from the defs in `main.exe` (`0x8016cd0c`, stride
  `0x24`): the damage table's p0/p1 order was right; Scripted_Battle_Actions.md's table had slots
  1, 15, 16, 17, 27 out of order and two names changed from the in-game strings.

## 2026-09-28: Dragon move timing

First trace (one-off script, since removed, whole party Defending) had Dragon act last in all 15
rounds, and I read the gate write on the frame after her busy cleared as the round-end reset,
concluding "next roll one frame after her busy clears". The user asked for a member slowed to
AGL 1 so someone acts after her: the rerun showed that write is her turn setting the gate to 30,
so the next roll is 31 frames after her busy clears. Lesson: a gate reset seen only at round end
can't be told apart from an actor's own gate write; get an actor after the one being timed.
Rerun also widened Lightning's particle-start drift to M+15..M+19.


## 2026-09-29: Boar Rune

Found by charmap-decoding `DAT_8016a0e0` (records 0x24 apart): Boar is Rune.Id 8, ability 1,
handler `0x800f8a9c` (created + named `rune_boar_cast_entry`). It's a copy of Falcon's entry with
the multiplier global at 20 instead of 30, so ×2 and no hit/crit roll came straight from reuse. The
Unbalance isn't in any handler; I only found it by walking every `04_play` file's slot 13 and
looking for a late `rand()`: Pahn, Eikei and Morgan all end slot 13 with opcode 40 (7, 100). Open
questions for the live run: damage after the handler's done (walker says ~30 frames after), and
whether `clear_status_effect` leaving `+0x1d58` set blocks a second cast's Unbalance.
Live run (a one-off verify script (since removed), `Seifu6Ant.State`) settled both: first pass matched nothing
because Pahn's ATK 46 overkilled 28-HP ants and the clamped HP drop can't match any roll. Held
ATK at 20 and restored enemy HP each round: 12/12 = 2x on the damage-frame rand, timings exactly
the walker's (no Falcon-style 1-frame shortfall), handler done S+292 before damage S+322, and a
second cast re-Unbalances (`+0x1d58` gets reset to 0 somewhere before the next prompt; not
found). Lesson: check the target's HP headroom before reading "no match" as a formula miss.
Also: target busy after the hit is 0 if it lives, 1 until S+415 if killed; I'd first written the
kill case up as the general one from the first run.
I'd written "×N applies after weakness and the Rune Piece bonus" for both runes on the strength
of the Falcon write-up alone; neither scripted run had a piece or an element, so it was
decompile-only until the user confirmed it live the same day. Say which runs actually exercised
a term before calling it confirmed.

## 2026-09-30: Red Solider Ant DoubleStrike timing

User asked for Mosquito + Red Solider Ant AI and timings. Both AIs were already in the static
sweep; basic-attack timings come straight from outputs/AttackTimingsClean.json. New: the
DoubleStrike continuation at a_data.bin `0x80080950` had no Ghidra function (created, named
`red_soldier_ant_special_double_strike`). It's the Boar-rune shape: `calc_damage << 1`, no hit
roll, no crit, own reaction script `0x800a5550`. Timed by feeding `0x800a5460` straight to
`Sim.run` and `walk_reaction(script=0x800a5550)` — the walker CLI can't take a raw script
address for an attack, only a table slot (it's slot 8 here, but `walk()` would still model it
as a basic attack's generic damage poll, which happens to match). Static only, no live check.
Same day, live-verified with the user's `3Mosquito1Ant.State` (Hero/Gremio/Pahn front, Ted/Cleo
back; 3 Mosquito + Red Solider Ant in the back row), 8 seeds × 4 rounds, party Defending. All 128
enemy turns matched on timing and on AI replay. Trap I fell into: my first comparison called
every "no HP loss on the declared target" a miss. Seven of those were actually Gremio **covering**
the low-HP Hero/Pahn (Hero cursor in `0x8016c29c`/`0x8016c2b4` = COVER_TARGET/COVER_AFTER,
attacker continuation `0x800f5e90` apply_covered_attack_damage), and six were Hero/Pahn counters.
Check the attacker's `+0x50` continuation, the cursor, and all party HP before labelling a miss.
Composed paths also bit me twice: a counter that kills adds the 93-frame death fade, and a cover
target frees at ally-free + 11 using the ally's *actual* free frame, which gets pushed later if
the ally is hit again first.
Then the user asked "Did you log Mosquito's ability to poison?". I hadn't. The sweep row said
"always plain Attack" because it only read the AI function, but the poison sits in Mosquito's
own hit-reaction script (opcode 40, status 0, arg 20). The walker's slot-1 `script_rand` is `[]`
for Mosquito because that field only covers the attack script, not the reaction. Lesson: an
enemy's "move" isn't only its AI. Check the slot-2 reaction for opcode 40 before calling a basic
Attack plain (see memory: script dispatch side effects). Verified from the existing log with
no rerun: 2 rand()s on every damage frame, and the replayed rolls matched every round-start
tick. My first tick check compared against frame 1 after confirm, but the tick lands on frame 2.
Correction, same day: the docs said Poison's duration is "12 (rounds)". It has no duration. The
12 from `apply_status_effect`'s switch only feeds `build_sprite_poly_resource` (the icon), and
the slot's `+0x30a8` is an expired flag that only `clear_status_effect` sets, not a counter
(instruction search for 0x30a0..0x30ac: its only readers are `FUN_800e02cc`, the icon updater,
and the apply/clear pair). This is the same mechanism the Sleep (id5) write-up already traced; I
just hadn't generalised it. Worth a re-check: the other generic-slot ids' "durations" (id1/2/4/6)
are probably cosmetic too.

## 2026-09-30: cover mechanic pinned down

Brief from the user: make find_cover_target simulable. Decompile (find_cover_target 0x800f79e0,
battle_check_counter_attack 0x800f4d5c, check_combatant_alive 0x800f8604) plus a live capture
(scripts/verify/VerifyCover.lua: HP poked to T and T-1, Gremio+Pahn KO'd, Phero poked onto Pahn;
VerifyCoverCompare.py models the function and matched 85/85, 42 cover timelines exact).
Things the old write-up had vague or missing:
- The trigger reads committed HP (+0x12) and HPMax (+0x10), `<` strict. The Hero at 28 HPMax is
  covered at 6, never at 7.
- The pair path checks only check_combatant_alive: busy blocks a partner, row doesn't.
  Back-row Cleo covered the Hero whenever Gremio and Pahn were both busy or KO'd.
- The "gender" byte is byte 10 of the loaded 04_play header (the name is bytes 1-9). Milich = 2
  and the kobolds = 3, so it's not strictly binary.
- Target free = ally's *final* free + 11. A re-hit on the ally in the next tick hides the clear
  from the target's poll (seen live twice now).
Still decompile/walker only: Sleep/Unbalanced partners covering, the Phero last-slot quirk
(scan starts at partyCount+1), a target with a higher index than its ally, ally death mid-cover.

## Spell cast durations (2026-10-06)

Live-measured every spell's cast length with `scripts/MeasureSpellTiming.lua`
(`SpellDuration.State`, McDohl with swapped runes; Luc as the Unite partner).
Results and marker definitions are in the doc's "Measured cast durations".
- The static tick sums were wrong for Explosion (320 vs 831), Final Flame
  (584 vs 681), Shining Wind (384 vs 535-539), and Hell/Black Shadow, whose
  old "≥224"/"≥176" were really 843 and 463.
- First end marker was wrong twice: `battle+0x14` never returns to 0, and
  counting handler changes ended Charm Arrow at +18 (it has a mid-machine
  hop). Voice of Earth has no end handler at all. The marker that held for
  every spell: the machine ends 3 frames before the next actor is picked
  (Charm Arrow is 4).
- A `& 3` mask on the spell definition's `+0x16` hid the distinct `8` and
  `0xA` values; the full six-value table is in the doc.
- Open: Scream, Rain of Kindness, Shining Wind, Guardian of Earth and Water
  Dragon vary by a few frames between seeds; cause unknown. Only one enemy
  and a full-HP party were tested, so target-count scaling is untested.
  Not tested: which caster triggers a Unite (McDohl did every time).

## Angry Blow RNG (2026-10-06)

- 6 `rand()` calls: 2 bolts x 2 (activation) + 2 x 1 (impact). Function
  addresses and phase layout are in the Ghidra plate comments
  (`spell_angryblow_*`, `0x8010c118/c140/c3b0`); the functions had to be
  created first, the Lightning spells weren't boxed.
- My first plate comment had phases 1 and 2 as 16 and 32 ticks. Wrong: 64
  and 48. The sum is 304 and matches the live machine length.
- The count depends on the target's `nRefPosZ>>12` only past about 975
  (forced live: 1000 -> 5, 1500 -> 4). z is depth toward the camera, so a
  real target never gets there. 901-999 is unmeasured.
- Open: enemy z values across other formations weren't scanned.



## Rainstorm RNG (2026-10-06)

- 26 + 2 x living enemies. 12 bolts x 2, bolt 0's single respawn at tick 68
  x 2, then 2 per living enemy in phase 4. Functions `spell_rainstorm_*` at
  `0x8010cbd8/cc00/ce80`, created in Ghidra (not boxed before).
- Looked like "12 bolts, impact rolls" after Angry Blow. Wrong: no rand at
  impact here. The respawn loop (`+0x24 == 0` and flash inactive) is what
  adds the extra 2, and it hides in a loop that only bolt 0 can satisfy.
- Fixed impact target (-128, 0, 0), so none of Angry Blow's depth caveat.
- User did the live check and confirmed the enemy scaling; no sim run of
  my own.

## Raging Blow / Ball of Lightning (2026-10-06)

- Both 0 `rand()`, taken from the user's own live check. No static pass, no
  functions boxed in Ghidra for them. If either ever shows RNG (an
  enemy-count term like Rainstorm's, say), this entry is the thing to
  recheck.

## Thunder God RNG (2026-10-06)

- 472, fixed: 96 setup + 16 (8 bolts) + 360 (24 flicker particles x 3 x 5).
  Functions `spell_thundergod_*` at `0x8010f418/f440/f8dc`, created in
  Ghidra. Static sum 484 matches the measured cast length.
- The tick machine alone shows only 1 literal `rand()`; the rest is in
  setup and the helper. The surprise was phase 4: nothing in the function
  deactivates the flicker particles. `FUN_801238e0` does, when the sprite
  animation finishes, so the count comes from the animation data. Sequence
  = the sprite id passed to `vfx_create_particle`; table at
  `*(*(0x800aa014)+0x14)`, frames `[id, duration]` from +4.
- Live-checked 2026-10-06 (a one-off capture script (since removed), 4 seeds): 96 / 2 x 8 /
  72 x 5 exactly as predicted, so the 10-tick period was right. Gotcha: a
  window to the next actor pick reads 478; the extra 6 are the next turn's
  roll at machine end +2. Count rands in [machine start, machine end].

## Clay Guardian RNG (2026-10-06)

- Seed-dependent, 90-132 over 20 seeds (multiples of 3). Only phase 3's
  sparkle loop rolls: 3 per activation, the third (`% 60`) is the life.
  Functions `spell_clayguardian_*` at `0x80110438/10460/1069c`; its context
  lives at `DAT_8017a058`, not `0x8017a050` like the Lightning spells.
- Live: 20/20 seeds and the first seed's per-tick counts matched the
  simulator first try. Static sum 336 matches the measured cast length.
- Not a bug but easy to trip over: the sparkle flag clears on phase 4's
  first tick, yet the spawn pass still runs on phase 3's last tick (the
  capture labels it `p4t0`, ticks are +1 in the labels).
- The buff scales combatant rec `+0x42`; the doc's "likely DEF-final" is
  still a hypothesis, nothing here tested it.
- User tested it live: Clay Guardian did NOT reduce damage taken. Matches
  `calc_damage` reading `wDEF` at `+0x32` while the spell writes `+0x42`.
  Not traced: whether `+0x42` ever feeds `+0x32` (my `0x42` instruction
  search was too noisy, many unrelated structs use that offset), and the
  magic-damage path wasn't tested. Don't write "bugged" as settled until
  that copy step is checked.

## Copper Flesh (2026-10-06)

- 0 rand, static. Functions `spell_copperflesh_*` at
  `0x80110cc8/cf0/f8c/111610`, created in Ghidra (not boxed before). Context
  is `DAT_8017a058`, the same slot Clay Guardian uses.
- Almost all the "how it works" was already in the plate comments of
  `apply_status_effect` and `apply_hp_damage_display` (a good reminder to
  read those first). New here: it lands on phase 4's first tick (224 ticks
  in), it blocks healing too, round-end decay is party-only so an enemy with
  id 8 never loses it, and recasting resets the counter.
- Static 448 vs measured 504: not explained by the end handler. Probably
  frame pacing; not measured per phase.
- Not checked: whether Hell's kill and item healing bypass the lock.


## Guardian of Earth RNG (2026-10-06)

- Seed-dependent, 380-408 over 20 seeds (all even): 40 setup + 2 per sparkle
  activation. Functions `spell_guardianofearth_*` at
  `0x80112048/12070/122f8/129ec`; context `DAT_8017a058`.
- Gotcha: it is NOT on the Earth Rune (id 6, slots 21-24). It is slot 4 of
  the Mother Earth Rune (id 30, +0x1a slots 22,23,24,33). My first capture
  used rune 6, the slot scan found nothing, the script errored and the
  headless window sat on the command menu. Scan the rune-set table
  (`0x8016a0e0`, one pointer per rune id) for the spell id first.
- Unlike Clay Guardian the sparkle life is not rolled: the sprite loops
  (`vfx_create_particle` param_4 = 1) so only the z cutoff (-300, 0x9600 per
  tick) ends it: 33 moves, re-activate every 34 passes. Start tick is
  `rand() % 48` per sparkle, and the tick counter is already incremented in
  the epilogue (s=0 fires on phase 3's last tick, labelled `p4t0`).
- Live: 20/20 seeds and the first seed's per-tick counts matched first try.
- Static phases 352 vs live 474-480 (older table): not measured per phase.
- The buff lands on phase 4's first tick for the whole living party; same
  `+0x42` x3/2 as Clay Guardian, so the "does nothing" caveat applies too
  (not tested for this spell).

## Scolding RNG (2026-10-06)

- 0 rand, static only. Functions `spell_scolding_*` at
  `0x80102dc0/102de8/103000/1037dc` (created in Ghidra), context
  `DAT_8017a038`. Phases 64+64+32+96 = 256 = the live length already in the
  docs table.
- Evidence for zero: no direct `rand()` in setup or tick machine;
  `apply_elemental_multiplier` only calls `printf`; hit script `0x8016f1cc`
  has no opcode 40; end handler only frees. Damage lands on the last tick of
  phase 3. Not live-tested (no live check was asked for; same status as
  Copper Flesh).

## Yell RNG (2026-10-06)

- Fixed 33 (11 activations x 3), live-validated on 20 seeds
  (a one-off capture script (since removed), McDohl Resurrection Rune id 7 slot 2, aimed
  at a LIVE ally: it has no effect but the animation and RNG run). Functions
  `spell_yell_*` at `0x80103824/1384c/103bfc/1043d0`, context `DAT_8017a038`.
  Phases 64+32+80+64+64+64 = 368 = live.
- CORRECTION: I first wrote 24 (static only). The user saw 33. Mistake: I
  treated the sparkle's `+0x24` as a fixed re-fire tick (0x30). The per-tick
  helper `FUN_8012080c` decrements it while the sparkle is active, so it is
  a countdown that re-matches the ever-increasing counter at (48+t)/2 for
  even t. Chain: 10,20,30,40 -> 29,34,39,44 -> 41,46 -> 47. Lesson: when a
  spell writes a field and a later "equals tick" test reads it, decompile
  every per-tick callee that touches the same particle before concluding
  the field is constant (same pattern as Rainstorm and Shining Wind's pool A).
- Start 0 never fires (labels begin at 1); the flag clears on phase 3's last
  tick before the pass. Revive: phase 5's last tick clears bValidFlag and
  calls apply_hp_damage_display(target, -HPMax/3); no rand.

## Scream RNG (2026-10-06)

- Fixed 162 (54 activations x 3), live-validated on 20 seeds plus the first
  seed's per-tick counts (a one-off capture script (since removed), McDohl Resurrection
  Rune id 7 slot 3, party-wide target type 0). Functions `spell_scream_*` at
  `0x80104468/10490/104808/104ff4`, context `DAT_8017a038`. Phases
  64+32+80+60+64+64 = 364 (docs said 364-366 live).
- Same epilogue sparkle pass as Yell: 20 sparkles, start ticks 0,2..38,
  counter 1..59 (phase 3 is 60 ticks, last tick clears the flag first).
  Applied the Yell lesson up front: read FUN_8012080c (the +0x24 countdown)
  before writing the model, and the static answer was right first time.
- Shared helper `simulateResurrectionSparkles(startTicks, passes)` now backs
  both simulateYell and simulateScream.
- Heal: phase 5's last tick, apply_hp_damage_display(member, -300) for each
  party member whose aUnk_0x50 byte != 1; no rand.

## Blazing Camp RNG (2026-10-06, first Rune Unite)

- Fixed 54, live-validated on 20 seeds + first-seed per-tick
  (a one-off capture script (since removed): McDohl Fire rune + Luc Lightning
  rune, both Rune slot 4 at the first enemy; setup from MeasureSpellTiming's
  UNITES case, spell id 36). Functions `spell_blazingcamp_*` at
  `0x80119584/195ac/19970/1a660`, context `DAT_8017a068` (the same slot
  Storm Fang uses; fine, only one runs at a time).
- Phases 64+32+150+64+64 = 374 = the live length in the docs table.
- Phase 2: 10 meteors at ticks 72+6k (2 each) + one impact rand each on the
  12th move (z -300 -> > -10, +25/tick; threshold is ctx[0x38]-10, a constant,
  not the target's z) = 30. Phase 3: 12 sparkles at ticks 0,3..33 (2 each) =
  24. Unlike Yell/Scream the phase-3 start ticks are never rewritten.
- Damage: calc_dual_element_spell_damage(0,3,target,caster,0x5dc) on all
  non-dead enemies at phase 4's last tick; no RNG. Hit scripts use native
  handler 13 (palette cycle only), checked before concluding zero.
- First Unite: Unites run through the same cast machinery, the machine just
  has its own cast entry; the capture window works unchanged.

## Thor RNG (2026-10-07, second Rune Unite)

- Seed-dependent, 550-610 over 20 seeds, live-validated (20 totals + first
  seed per-tick; a one-off capture script (since removed), McDohl Lightning rune + Luc
  Water rune, Rune slot 4 at the first enemy). Functions `spell_thor_*` at
  `0x8011a7f4/1a81c/1abd4/1bc3c`, context `DAT_8017a068`.
- Frames: static phases 64+48+128+80+64 = 384 ticks, measured 570-572 frames
  (docs table already said 571). Ticks are not 1 per frame in this spell; cause
  not investigated (likely 2-frame ticks under GPU load).
- 6 setup + 36 bolts + 120 trails + 4 x arc spawns. Arcs = the same 20 line
  particles / spawn helper as Flaming Arrow (radius 0x78): reused the FA model
  shape (spawn gate from tick 48, epilogue decay). Residual low 12 bits of
  trail_x read live: 0 (checked because FUN_80123a5c's heap_alloc leaves them
  uninitialised; documented FA residue values do not apply).
- Ordering lesson: the trail tail flag. Game updates the lead's flag and then
  copies it down the 10-slot array; I first shifted old values, which was 1
  tick late on every seed (total off by a few calls). Found by diffing the
  per-tick log against live: first mismatch at p2t58/59.
- Bolt flash: B life = rand%32+0x30 never matters because the paired C (48
  ticks) deactivates B. Only worth re-checking if C's countdown ever changes.
- Method win: for a big machine, get the structure from the per-tick live log
  first (labels showed 8@1, 4@13, 2@33.. immediately mapped to bolts, impact,
  trails) before writing the model.

## Scorched Earth RNG (2026-10-07, third Rune Unite)

- Fixed 282, live-validated: 20 seeds all 282, 563 frames each, first-seed
  per-tick log reproduced exactly (a one-off capture script (since removed):
  McDohl Earth rune + Luc Fire rune, Rune slot 4 at the first enemy).
  Functions `spell_scorchedearth_*` at `0x801179bc/179e4/17d5c/187fc`,
  context `DAT_8017a068`.
- No direct rand() in the tick machine: all rolls are
  vfx_activate_and_position_particle (2 each) + 48 in setup, so counts depend
  only on timing, hence seed-independent (no arc/lifetime rolls like Thor).
- 48 setup + F 154 + A 32 + E 48. F first fire = 4 (two checks in a row, the
  second `== -1` test has no active guard; found by the first model being 2
  per first fire, off by 2 at every first-fire label). A re-fire pattern is
  the Yell countdown again ((30+t)/2).
- Sprite lengths read from battle.bin: sheet at 0x800aa004, seq 0xd = 11 x 5 =
  55 ticks, seq 8 = 48, seq 3 (ring) loops and is ended by the scale logic
  (47 ticks, confirmed by the live respawn gaps). Reused the Thunder God
  convention: active t..t+L-1, reactivated at t+L.
- Phase 4's length is data dependent (waits until meteor/impact pools are
  inactive); not decoded. 563 total frames minus 484 for the other phases
  gives ~79 if 1 tick = 1 frame (unverified).
- Process win: wrote the model against the per-tick log first (Python), diffed,
  then ported to Lua. Two diffs found, both one-liners.

## Water Dragon RNG (2026-10-07, last traced Rune Unite)

- Seed-dependent, 2998-3193 over 20 seeds, live-validated: totals and the
  first seed's 218 per-tick entries matched on the first try
  (a one-off capture script (since removed): McDohl Water rune + Luc Wind rune,
  Rune slot 4 at the first enemy). Functions `spell_waterdragon_*` at
  `0x8011bde4/1be0c/1c24c/1cd48`, context `DAT_8017a068`.
- 302 setup + 24 bolts + three respawning pools (P1 30x4 life%180, P2 20x5
  with a z-crossing end and no life countdown, P3 80x4 life%96) gated
  on passes 64..318 (P2 128..318). Period of a counting-down pool = life+1
  (the inactive mark is set AFTER the respawn loop in the same pass, so the
  respawn is one pass later).
- Frames: 384 static ticks vs 672-682 live (docs table already had 671-681).
  Same gap as Thor, not explained. Both have a huge number of particles;
  unverified guess is 2-frame ticks under GPU load.
- Used the lessons so far: read every per-tick helper (FUN_8012076c, the pool
  loops) before modelling; prototyped in Python against the live log, then
  ported. The only trap was P2: its life field is never decremented, easy to
  assume it is.
- Unites status: Blazing Camp 54, Thor 550-610, Scorched Earth 282, Water
  Dragon ~3000 done; Storm Fang (38, documented earlier) not re-checked
  against per-tick helpers.

## Deadly Fingertips RNG + the four zero Wind/Earth spells (2026-10-07)

- The Shredding, Healing Wind, Storm, Voice of Earth: user says all 0. Added
  zero simulators + docs rows, not decompiled (Voice of Earth has no end
  handler, so a capture window would have needed a different marker).
- Deadly Fingertips: seed-dependent 1075-1170, live 20 seeds + first-seed
  per-tick (129 entries), a one-off capture script (since removed). Functions
  `spell_deadlyfingertips_*` at `0x80113a68/13a90/13e98/147d4` (cast entry and
  cleanup already existed in Ghidra; vfx_setup and tick machine created now),
  context `DAT_8017a060` (Soul Eater arena slot).
- Same mechanism as Dragon.simulateLightning (30 line particles,
  vfx_spawn_random_arc_particle, 5 rand per respawn); only the gate length
  differs: 209 passes (phase 2: 80, phase 3: 60, phase 4: 10, phase 5: 59).
  Reused the Dragon model's loop shape; the prototype matched on the first run.
- Gate edges mattered: phase 5's last tick clears the flag in the body BEFORE
  the epilogue, so that pass doesn't spawn. Phase 2's first tick sets it before
  its epilogue, so that pass does.
- Instant death roll: none. apply_elemental_multiplier only calls printf; the
  kill is deterministic from the immunity flag (+0x26 & 0x4000) and element
  compat. (Does NOT mean "always kills": immune targets and the 0x4000 flag
  block it.) The old "2 (instant-death)" base_power cell is not a chance.
- Frames: 366 static ticks vs 576 live, the same non-1:1 gap as Thor/Water
  Dragon; docs table had 575.
- Spells without a decompiled RNG model now: none except Storm Fang's re-check;
  the four zero spells rely on the user's verification.

## Fog of Deception effect check (2026-10-07)

- User asked to test what Fog does (expected: party evade up / enemy accuracy
  down; SpellDuration's enemy is a spell-immune boss). Case 6 (re-read the
  decompile): per living enemy, play 0x8016f1cc and rec+0x36 = (short)(rec+0x36
  *4/5). No immunity test in the code at all.
- Live (one-off script, since removed): rec+0x34..0x42 is 0 on EVERY
  combatant (party and boss) at before-confirm, setup frame and end handler,
  and nothing in +0x26..+0x43 changes during the whole 460-frame cast. So the
  scale hits 0 -> no effect on this save.
- calc_hit_chance reads only SKL +0x26 on both sides (+ Bucket 0x10 on a party
  attacker, Hazy rune id 18 on the target of an enemy attacker). It never reads
  +0x36, so even a nonzero +0x36 would not feed hit chance by that path.
- Big side finding: aUnk_0x34 is all zero for McDohl too, so Clay Guardian's
  +0x42 *3/2 is 0*1.5 = 0. That explains "Clay Guardian did not reduce damage"
  without needing a missing copy into +0x32, and kills the old "+0x42 is
  final DEF" guess (DEF at +0x32 was 135 in the same dump). One savestate only.
- Not done: who else reads +0x36/+0x42 (a byte-pattern search for the offset is
  noisy, many structs); other formations/gear where the block might be nonzero;
  a behaviour test (enemy hit rate with vs without Fog) since the field is 0.
  Both Fog and Clay Guardian look bugged/no-op as shipped, but only
  proven for this savestate.
- 2026-10-07 second save: `FogOfDeception.State` (early game, 5 party vs 5
  ordinary enemies, McDohl HP 59). Same: rec+0x34..0x42 zero on all 10
  combatants, no byte changes in +0x26..+0x43 during the 462-frame cast. Checked
  that aPad_0xb94a (struct offset 2964 = 0xb94) is combatant record #1, so the
  watched field is the scaled one. Not a boss-immunity effect. Also visible:
  "before confirm" stats were stale garbage (e.g. ATK 32896) that were
  recomputed by the setup frame, the known ~5-frame stale window.

## 2026-10-20: chained cover wait

Static read (Ghidra) plus a live 5 Bandits round 2 capture: the cover target's wait is
opcode 44 (mask 9) in script 0x8016c2b4, a per-frame busy poll on the ally, not a timer in
the C functions. A covered ally can be covered again while the first target waits; the
target frees at her final free + 11 (live: Cleo free 607, McDohl 618). Documented in
Battle_Damage_Formula.md "Cover target wait and chained covers". Open: what clears the
ally's bit 8, round-end timeout. TickBasedAlgorithm.md is not in this repo, so its cover
pseudocode still needs the same update there.
