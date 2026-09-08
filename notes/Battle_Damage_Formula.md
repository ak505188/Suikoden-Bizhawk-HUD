# Battle Damage Formula — investigation history

This is the history behind
[docs/game_mechanics/Battle_Damage_Formula.md](../docs/game_mechanics/Battle_Damage_Formula.md):
corrections, dead ends, live-testing sessions, and open questions that
shaped the current clean write-up. Section headers below correspond to
sections in that doc.

## The central battle-state struct

`class_ptrs` offset was cited ambiguously across earlier session notes as
either `+0xF84` or `+0xF90` (two different sessions disagreed) — resolved
in favor of `+0xF84`, confirmed directly from Ghidra's own decompiled
pointer arithmetic once the struct was formally typed.

**Formalized as real Ghidra struct types 2026-09-07** (`BattleState`,
`CombatantRec`, `EnemyData`, `MonsterRecord`, `ClassPtrEntry` — in
`main.exe`'s own data type manager, not just this doc): the global pointer
(`DAT_8017be3c`, renamed `g_pBattleState`) is now typed `BattleState *`,
and every function that touches it decompiles with real field names
(`.wSKL`, `.bActionType`, `.wStatusFlags`, `.pClassDataPtr`, etc.) instead
of raw offset arithmetic — verified across `calc_hit_chance`, `calc_
damage`, `apply_status_effect`, `apply_elemental_multiplier`, and `mark_
enemy_formation_slot_occupancy`. Large regions where fields are known to
exist but aren't confidently pinned down (the sync-signal array around
`+0x30`, most of the `+0xdc`-`+0xb40` and `+0xb94`-`+0x1258` gaps,
`+0x1268`-`+0x1344`, `+0x1348`-`+0x3420` including the per-status
duration-slot table at `+0x30a0`) are left as explicit `undefined1[]`
padding rather than guessed at — safer than baking in a wrong layout.
`CombatantRec`/`EnemyData`/`ClassPtrEntry` are declared as single array
elements at their correct starting offsets (real counts vary by battle) —
index further via pointer arithmetic using each struct's own confirmed
size rather than array subscripting.

Still worth reconciling against the independently-derived RAM-side enemy
struct in
[Battles_and_Encounters.md](../docs/game_mechanics/Battles_and_Encounters.md#enemy-struct-60-bytes-per-enemy-libbattlelua-readenemytable)
(found via a completely different method — live memory reads, not
disassembly).

## `calc_hit_chance`

The halving condition (Bucket-status for party members, Hazy-Rune check
for enemies) was, at the time this section was first written, not
independently confirmed — later resolved via the status-effects and
passive-rune-effects investigations below.

## Magic Unite spells

Not yet done: confirming the MGC/2 bonus and resistance-priority rules
Suikosource describes against the actual consumer code (the `+0x14`
handler this resolves to isn't traced past `battle_check_magic_unite`
itself); naming Earth's/Water's Lv4/Lv5 spells (handler addresses known,
not yet cross-referenced against the external spell-name reference).

## The unique-rune ability table (`DAT_8016a630`)

Originally an open mystery: the `+0x16` flag byte was thought to be a
simple two-value flag, and `DAT_8016a630` was guessed to be an
enemy/monster table. Reading all 34 entries of the equipped-rune lookup
table directly showed it's actually three-valued, and settled that
`DAT_8016a630` is not an enemy/monster table — it's a separate
special-ability definition table for the 6 unique/single-character runes.

Not yet determined: what value-`2` entries (index 14 onward, unconditionally
rejected) actually represent, or whether they're reachable through some
other resolver entirely — open for a future pass.

(The Defend handler and the `[0]`/Attack dispatch entry are resolved — see
[Turn_Order.md](../docs/game_mechanics/Turn_Order.md#how-a-turn-actually-starts-battle_dispatch_current_actor_action).)

## Status effects

Found 2026-09-06 while investigating what looked like an unexplored
counterattack gate (`anim_op_roll_status_effect_chance`, one of
`play_attack_animation`'s 45 script opcodes) — tracing what it actually
*called* revealed a status-ailment/buff system, not a counter. Two fields
from this system were already independently referenced elsewhere in this
project's docs before their real meaning was known: `calc_hit_chance`'s
"`+0x4a` bit `0x10` halves accuracy" note and `Turn_Order.md`'s "`+0x4a`
bit `0x20` = can't act, skip AI" note — both turned out to be 2 of the same
9 statuses.

**`id1`/`id2`/`id3` are one escalating ailment, not three separate ones**
— per the user's own game knowledge, 2026-09-06.

**`id5`/`id7` ActionTag correction (2026-09-06)**: `id5` and `id7` setting
`ActionTag=1` was previously misread as forcing `ActionType`=Attack.
Live-testing confirmed this actually marks the combatant's turn as
already-resolved without ever going through normal action selection, so
`ActionType` reads back as the `255` sentinel rather than `0`(Attack) — the
ailment silently skips the turn rather than forcing an uncontrolled Attack.

### Live-editing sessions

**Attempt #1 (menu-paused savestate, inconclusive)**: poked
`combatant_rec+0x4a` directly in a real battle (`Gigantes.State`, one
status id at a time, also populating the per-status duration-slot fields so
the bit wouldn't get silently cleared) and screenshotted — all 9 came back
visually identical to baseline. Root cause: the savestate is frozen at the
"Fight/Run/Bribe/Free Will" decision menu, and frame-advancing alone never
progresses a round while that menu is waiting on input — the headless
spawn process clears all input bindings (so it can't steal the user's real
controller), so nothing was ever going to reach the round-end code that
would react to the status.

**Attempt #2 (mid-round savestate + injected input, successful)**:
switched to `GigantesEnd.State` (mid-round, not menu-paused) and drove the
round to completion by directly calling BizHawk's `joypad.set({["P1
X"]=true})` for a burst of frames — works even with input bindings
cleared, since it sets button state programmatically. Confirmed via
`combatant_rec+0x46`/`+0x47` reads that rounds genuinely advance this way.
**Important safety finding**: poking the per-status duration-slot table
(`+0x30a0` region) alongside the bitmask caused the battle to hang
completely (no further progress no matter how much input was injected/how
many frames advanced) — the assumed 4×u32 slot layout is apparently not
safe to write blindly. Do not poke that region without further care; a
bitmask-only poke on `+0x4a` was sufficient for every id tested and never
caused a hang.

With that fixed, round-end processing gave clean confirmation on 2 of the
9 ids:
- **`id3`**: live-confirmed visually — vanishes from the HP list, sprite
  lies face-down, matching a KO. Bit never cleared throughout testing.
- **`id5`**: live-confirmed behaviorally — `ActionType` read back as `255`
  after a round passed. **Tentatively named "Sleep" (2026-09-07, per the
  user's own best guess** — "likely sleep or petrify, but I can't think of
  any enemy that sets either — there is only 1 player way to set sleep"):
  treat this identification as provisional/unconfirmed, unlike the other 8
  ids which are either code-solid or user-confirmed outright.

`id7`/`id8` use their own dedicated countdown fields rather than the
generic duration-slot table — both resolve in 1-2 rounds. Live-tested both
(bitmask-only poke) without incident, but a clean read wasn't possible this
way: a bitmask-only poke leaves `+0x4d`/`+0x4c` at pre-existing garbage, so
the round-end countdown-to-`0` check never fires within a short window.

**Round 2 of live testing (2026-09-06, `id0`/`id1`/`id2`/`id4`/`id6`/`id7`/`id8`,
bitmask-only, `GigantesEnd.State`, 3 mashed-through rounds each)**:
Gigantes' own HP trajectory across the 3 rounds came back bit-for-bit
identical (`3900→3900→3707→3661`) across `id0`, `id1`, `id2`, `id6`, `id8`
tests — the underlying combat played out identically in all five. Yet the
afflicted character's own HP only dropped (`266→253`) in the `id0` test
specifically, staying flat at `266` in the other four — a clean
confirmation of a Poison-style periodic-damage effect. `id0` is also one of
the 4 "persists across battles" ids — Poison lingering across fights until
cured is the expected classic mechanic.

`id4`/`id7` showed different Gigantes trajectories, consistent with them
genuinely altering something (a changed hit/miss outcome or a skipped turn
cascades into different RNG outcomes), matching their already-established
mechanics, though neither produced a clean standalone signature this pass.
`id1`, `id2`, `id6`, `id8` showed no detectable effect within this 3-round
window — an honest negative, most likely because their real behavior needs
duration-slot/counter data this project can't safely initialize via a raw
poke.

**Round 3 of live testing (2026-09-06)**: re-ran `id1`/`id2`/`id6` against
a proper 6-round baseline for a cleaner control, and properly initialized
`id7`/`id8`'s dedicated countdown bytes (`+0x4d=1`, `+0x4c=2`) so their
real short lifecycle could run to completion.

- `id1`/`id2`/`id6`: completely identical to baseline across all 6 rounds.
  Now explained for `id1`/`id2` by the "balloon" escalation mechanic — a
  lone poke never escalating to `id3` producing no visible effect is
  exactly what the mechanic predicts. `id6` remains a genuine unexplained
  negative, most likely a conditional effect (e.g. Silence-like) that
  never got a chance to trigger since the afflicted character just kept
  physically attacking.
- `id7`: with `+0x4d` seeded, decrement matched the code (`1→0` after one
  round) but the status got stuck rather than expiring — traced to
  `clear_status_effect`'s own guard clause, which no-ops for every status
  except `id8` unless the generic duration-slot's "active" flag is also
  set.
- `id8`: entire lifecycle completed correctly (`+0x4c` ticked `2→1→0`,
  status bit cleared by round 6). Screenshots at the same checkpoint showed
  the afflicted character at full HP (`266/266`) vs. `250/266` in
  baseline/every other id — a clean, isolated signal the character avoided
  a hit landing in every other test. **Confirmed by the user (2026-09-07):
  `id8` is the effect from the "Copper Flesh" spell, which locks HP for 3
  turns.**

**Mechanism fully traced in code (2026-09-07, corrected same day)**: not
via `combatant_rec+0x4c` at all — the real check lives in `apply_hp_
damage_display` (`0x800e1654`), whose first check is `if
(combatant_rec.StatusFlags & 0x8000) hp_delta = 0;` followed by `if
(hp_delta == 0) return -1`. **Correction**: this function is NOT the
"single choke point where any computed damage/heal value gets applied to
HP" as first described — full disassembly (not just decompile) shows it
never writes `HP_Current` at all; it only accumulates the delta into a
running `nHpDeltaAccumulator` field (`+0x4e`) and queues the floating
damage-number display. Some other, not-yet-identified function applies
that accumulator to real HP afterward. Functionally this doesn't change the
conclusion. **Also corrected 2026-09-07**: this function's `hp_delta` sign
convention was documented backwards in an earlier pass — it's negative =
healing, positive = damage (confirmed both by its own overheal-clamp
logic and by `apply_uncovered_attack_damage`/`apply_covered_attack_damage`
passing `calc_damage`'s raw positive return through unmodified). This
directly explains the Sunbeam mixup below. `combatant_rec+0x4c` (the field
`apply_status_effect` actually sets to `2`) is purely id8's own duration
countdown, not something the damage-blocking check itself reads — the
earlier assumption sent the search down the wrong field.

Checked every `lbu ...,0x4c(...)` site in `main.exe` (29 hits) looking for
a `combatant_rec+0x4c` reader; the one promising-sounding candidate,
`check_dodge_counter`, turned out to read the persistent Stats struct's
`Rune.Id`, not `combatant_rec+0x4c` — a red herring for this specific
mystery, though a genuine, useful find for the passive-rune-effects thread.
The remaining ~28 `+0x4c` sites haven't all been individually traced back
to their base struct.

### Passive rune effects — major correction

**Major correction, per the user's own game knowledge.** Everything
documented in an earlier session as "`equip_ptr+0x4c`, the weapon-type
byte" was never a separate weapon/equipment-type concept —
"`equip_ptr`" (reached via the `class_ptrs[idx]->+0x1c` chain) **is the
character's persistent Stats address**, and `+0x4c` on it is `Rune.Id`.
There is no separate "weapon-type" struct or field; every check is really
"does this combatant have rune `N` equipped."

Confirmation/narrative-fit notes per rune, gathered while mapping the table
now in docs:
- **Killer (`15`)**: confirmed by the user exactly.
- **Counter (`16`)**: strong match by name — the user's own instinct was
  "nothing guarantees dodge," but the function resolves both dodge and
  counter outcomes, so this fits the counter half cleanly.
- **Hazy (`18`)**: confirmed, and a correction of an earlier misread — the
  check reads `param_2` (the target, i.e. the Hazy-wearer), not the
  attacker; the first pass mixed up which argument was indexed and wrongly
  reported this as "halves the attacker's own accuracy."
- **Gale (`19`)**: found 2026-09-07; "Gale" doubling speed is an exact
  narrative fit, inherits confidence from `battle_compute_ally_derived_
  stats` already being byte-for-byte validated against real game data.
- **Sunbeam (`20`)**: corrected 2026-09-07 — Regen, not damage. Confirmed
  by the user exactly: "Regen +5. Heals 1 HP of the party per step on the
  field." The `DAT_8017db24` subsystem is very likely the overworld
  step-counter, not a scripted event as first guessed.
- **Fortune (`22`)**: corrected 2026-09-07 — doubles a different
  per-party-member field (`+0x10`) than the aggro score itself (`+0x14`),
  which had been originally conflated since both are computed in the same
  function with overlapping-looking address arithmetic. Confirmed by the
  user: "Fortune doubles XP growth."
- **Prosperity (`23`)**: confirmed by the user ("Prosperity doubles money
  (bits) drops") and independently verified 2026-09-07: statically read
  `+0x34` from 2 monster records via the disc-file charmap name-search
  technique (no live emulator needed) — Zombie Dragon (`vb5g.bin`) reads
  `2000`, Killer Rabbit (`b_data.bin`) reads `80`, both exact matches
  against `Suikoden-RNG-lib`'s `enemies.js` `"bits"` field. Neither sample
  exercised the bit-0 "compressed large value" branch, so it remains
  unconfirmed by live data, just by the code path itself.
- **Turtle (`25`)**: plausible per the user ("could also be some equipment
  for specific statuses").
- **Holy (`21`)**: plausible, unconfirmed — found 2026-09-07 via the same
  shared `FUN_801261b0(21)` helper Sunbeam/Champion's use.
- **Champion's (`24`)**: plausible — found 2026-09-07; fits "guarantees
  success" narratively, but the actual scene/event wasn't identified.
- **Phero (`26`)**: confirmed by the user exactly: "Phero makes characters
  cover for the opposing gender" — resolved what `find_cover_target`
  (renamed from `find_heal_target`) actually does, once its real caller
  (`battle_check_counter_attack`) was traced.

Given several of these narrative fits were genuinely uncertain (the user
flagged real doubt on Double-Beat/AOE specifically, though Hazy and the
aggro/XP conflation both turned out to be misreads rather than real
uncertainty), the *numeric* mapping (id → mechanism) is solid — it's
directly read from code — but the *flavor* interpretation is a secondary
layer, now mostly user-confirmed.

**All 29 original `lbu ...,0x4c(...)` sites traced 2026-09-07** (adding
`19` Gale, `20`'s second context, `21` Holy, `24` Champion's): 2 turned out
to be false positives on a completely different struct's own `+0x4c`/
`+0x4d` (the `id8`/`id7` status countdowns — unrelated to `Rune.Id`), the
rest are genuine `Rune.Id` reads, either already covered or confirmed as
re-resolving the same ability-set table various UI/menu screens already
use to display a rune's name (no new mechanical effect). One genuine read
remains unresolved: `0x800f81e8` compares two combatants' MGC-stat
difference (`<10`) and conditionally calls the RNG wrapper — purpose not
pinned down.

### Cover mechanic

Prompted by the user asking "have you looked at the cover mechanics at
all?" while discussing Phero Rune — traced the full mechanism starting
from `find_cover_target`'s one real caller, `battle_check_counter_attack`
(name is a misnomer from an earlier session).

The story-pairing lookup table's true layout was initially off by one byte
(`DAT_8016c815` looked like the array, but the true layout is interleaved
`(self_id, partner_id)` pairs starting one byte earlier). Every pairing
matches a real canon relationship (Eileen/Lepant are married; Tai Ho/Yam
Koo are the comic fishing duo; Tengaar/Hix are the known couple;
Sylvina/Kirkis are both elves) — confirms this is a hardcoded
story-relationship table, not a stat-based heuristic.

**classData layout search (2026-09-07): exhausted, no new fields found on
classData itself.** Traced all 31 direct `ClassPtrsArray` (`+0xf84`) access
sites in `main.exe`, plus every function reachable from `find_cover_
target`/`battle_check_counter_attack`'s call graph (`check_critical_hit`,
`check_dodge_counter`, `calc_hit_chance`, `calc_damage`, `battle_select_
special_ability`, `battle_try_special_attack`, `battle_execute_enemy_
attack`, `battle_calc_enemy_aggro`, `battle_refresh_combatant_derived_
stats`, `anim_op_roll_status_effect_chance`, `apply_covered_attack_damage`,
`apply_uncovered_attack_damage`, `battle_check_magic_unite`, `battle_menu_
select_target`, `battle_menu_confirm_rune_level`, and others). A handful of
`+0xf84` sites have no Ghidra function boundary (`0x800e861c`, `0x800e896c`,
`0x800ea664`, `0x800ecc34`, `0x800f5b60`, `0x800f81d8`) and remain
genuinely unchecked — the only unexplored thread if this comes up again.

**Unconfirmed side-note**: `ClassPtrEntry`'s own 8-byte `aUnk_0x04` blob's
first 4 bytes look like they may be a cached, redundant direct pointer to
the same `PersistentStats` struct (not a separate one) — `calc_damage` and
`check_dodge_counter`/`battle_execute_enemy_attack` read `+0x55`/`+0x56`
through it identically to the `classData+0x1c` path — but this wasn't
confirmed with a live memory comparison, so `ClassPtrEntry` itself hasn't
been changed to reflect it.

**Real names confirmed (2026-09-06/07, per the user's own game knowledge)**
via `battle_menu_compute_command_availability` (renamed from
`FUN_800eedd0`), previously only found as an incidental `+0x4a` reader.
This is an exact match for **`id7` = "Unbalanced"**: Attack and Rune both
disabled, leaving only Defend/Item/Unite — "the character can only defend
or use items for 1 turn," exactly as described. It also revealed `id6`'s
real mechanism for the first time (Rune-only disable), which fully
explains why the earlier live-poke test of `id6` alone showed zero
observable effect — the test character never tried to cast a spell.

`id4` confirmed as "Bucket" with an important caveat from the user: the
real game shows a visible bucket icon over the afflicted character, which
the earlier raw memory-poke test failed to reproduce — consistent with the
icon needing a real handle computed by `FUN_800e1e3c` (spawned only
through the genuine `apply_status_effect` code path), not something a
bitmask-only poke can fake.

### Poison — full solve, 2026-09-07

Two entirely separate mechanisms, found while tracing Neclord's Bats
attack — one consumes RNG, the other is fully deterministic. Duration's
specific decrement-and-clear consumer for Poison's own duration slot (the
generic per-status table, used for the 6 status ids `battle_process_
round_end_status_and_formation` doesn't handle) was not located this pass
— still a genuine open item, separate from the now fully-solved per-tick
damage formula.

## Formation management: front-row auto-backfill

Found 2026-09-05→06 while chasing the status-effect ids above into their
round-end processing — `battle_process_round_end_status_and_formation`
turned out to also run this front-row auto-backfill system, and following
it resolved the long-standing `monster_record+0x11` mystery. Neither this
function nor its callee existed as a disassembled Ghidra function until
this investigation created them — meaning every earlier, believed-
exhaustive `+0x11` code search (several passes, spanning `main.exe`, every
boss AI overlay, every regular-enemy AI function, and the complete
45-entry animation-script opcode table) was structurally blind to this
code the whole time. Worth remembering: an "exhaustive" instruction-level
search is only as exhaustive as what Ghidra has already disassembled —
worth re-running after any new function gets created nearby, not trusted
to stay valid forever.

This resolves the one case that had broken the "sprite size" hypothesis:
Gigantes is visually one of the tallest sprites checked (confirmed via
live VRAM capture, clips off the top of the screen), yet apparently narrow
enough to need only a single formation slot.

## `calc_hit_chance`/`check_critical_hit`/`apply_elemental_multiplier`

`check_critical_hit`'s Killer-Rune doubling was confirmed 2026-09-07 (per
the user's own game knowledge).

`apply_elemental_multiplier`'s magic damage formula was confirmed via a
live cast prediction (attacker MGC 190 / base_power 500 / weak target →
`(500+95)*2=1190`, matched observed damage exactly).

`apply_elemental_multiplier` is called from 21 sites. `get_xrefs_to` only
found 17 of these; 4 more (`0x800ff174`, `0x801033e8`, `0x80105748`,
`0x80111ce8`) sat in undisassembled bytes invisible to xref analysis and
were found by a raw byte-pattern search for the `jal` opcode encoding
(`ca96040c`). Worth doing this kind of byte-level completeness check
whenever a suspiciously-round xref count comes out of a region with large
undefined-code gaps.

## Enemy elemental attacks: the third damage formula — full investigation arc

This was one of the longest-running open threads in the project: Zombie
Dragon's fire-breath damage was confirmed by exact live RNG matching
against a captured cast (`ZombieDragonT2.State`, seed `0x00000001`) to be
MGC-based, not the ATK-DEF shape every traceable `calc_damage` call site
computes — a genuine contradiction that took several passes to resolve.

**Initial capture**: one `rand()` call per living target, six total,
matched by hand against each target's real MGC stat (`130 - target.MGC`,
Zombie Dragon's own MGC is 130):

| Target | MGC | base (130−MGC) | roll | formula result | observed damage | ratio |
|---|---|---|---|---|---|---|
| 0 | 47 | 83 | 4978 | 75 | 75 | 1.0 (neutral) |
| 1 | 39 | 91 | 20495 | 96 | 96 | 1.0 (neutral) |
| 2 | 80 | 50 | 10311 | 52 | 26 | 0.5 (resist) |
| 3 | 93 | 37 | 11367 | 39 | 39 | 1.0 (neutral) |
| 4 | 21 | 109 | 30054 | 104 | 20 (overkill) | consistent |
| 5 | 36 | 94 | 17031 | 100 | 41 (overkill) | consistent |

The initial attempt used *target DEF* (matching `calc_damage`'s own
shape) and only landed in the right ballpark, not exact; swapping in
*target MGC* produced the exact match above.

**"Not yet reconciled — deepened, not resolved, 2026-09-07"**: re-traced
the full call graph downstream of `battle_execute_enemy_attack` via raw
disassembly (most of these are inline state-machine continuations Ghidra
never function-boundaried, hence missed by earlier passes): the normal
non-crit path, the CRIT path, and the cover-mechanic path **all three**
call `calc_damage` itself — which computes `wATK-wDEF` with no MGC
reference anywhere, gated to party-member attackers only for the elemental
bonus. So every damage-computing branch actually found calls the ATK-DEF
formula — none reach an MGC-based one. Two live-hypotheses: (a) the
per-monster attack SCRIPT applies its own damage-override opcode between
`calc_damage`'s return and `apply_hp_damage_display`; (b) the captured
savestate's targets coincidentally had `wDEF == wMGC`.

**Hypothesis (b) definitively ruled out, 2026-09-07**: live-read
`wDEF`/`wMGC` for all 6 party members from the same savestate — `DEF` and
`MGC` are clearly different, unrelated values for every target (e.g.
target 0: `MGC=47` vs `DEF=92`). Hypothesis (a) became the only remaining
explanation. An earlier attempted live execution-breakpoint on `calc_
damage` (`event.onmemoryexecute`) never fired, suggesting execution hooks
may not work reliably on this core.

**Deep dive into hypothesis (a), 2026-09-07: substantially narrowed, still
not fully closed.** Fully audited all 45 animation-script opcodes via
batch decompile — none of them read/write `CombatantRec`'s
`PWR`/`DEF`/`MGC`/`ATK` fields, or call `calc_damage`/`apply_hp_damage_
display`. Every opcode is purely visual/state-management.

Also discovered along the way: `RngCallbackTable` (`BattleState+0x1258`)
is a STATIC `main.exe` table, not per-battle heap data as previously
assumed. This means overlay code *could* invoke `calc_damage`/`apply_hp_
damage_display` indirectly through this table — but no caller doing so was
found in Zombie Dragon's own AI functions, her fire-breath
self-positioning script, or the post-fire-breath wait-state.

The actual per-target hit animation during the multi-target loop uses a
different script — slot `[4]` of the monster's own script table — which
was partially parsed (opens with the same sync-signal + move shape) but
not walked to completion at this point; several of its opcodes are
"dual-mode" (branch on a `param_2` argument the main dispatch loop always
passes as `0`), implying some other not-yet-found per-tick "resume" caller
must invoke them with `param_2=1` — the VM's exact resumption semantics
weren't fully reverse-engineered yet, so a damage-triggering opcode later
in this script couldn't be ruled out with full confidence at this stage.

**Re-confirmed ATK-DEF genuinely doesn't fit, using real live DEF
values**: Zombie Dragon's ATK (her PWR, 175) minus each of the 6 targets'
DEF (92, 90, 82, 80, 35, 33) gives `83, 85, 93, 95, 140, 142` vs. the real
captured `base` values `83, 91, 50, 37, 109, 94` — only target 0 lines up,
and even that's a numerical accident (`175−130 == 92−47 == 45` by
coincidence).

### Re-validated from scratch, 2026-09-07

Given this project found one other "confirmed by an earlier session"
result resting on a wrong assumption earlier the same day
(`apply_hp_damage_display`'s sign convention), the original 6-target RNG
match was re-verified completely from scratch — loaded `ZombieDragonT2.
State` in a fresh headless emulator instance, injected RNG seed
`0x00000001`, independently simulated the LCG forward in Python, then let
the real attack play out and read the real HP deltas.

Real damage reproduced exactly: `75, 96, 26, 39, 20 (overkill), 41
(overkill)` — identical to the original table.

| Target | Real damage | MGC-MGC prediction | ATK-DEF prediction |
|---|---|---|---|
| 0 | 75 | 77 | 77 |
| 1 | 96 | 95 | 81 |
| 2 | 26 | 52 → 26 exactly with resist ×0.5 | 89 (no relation) |
| 3 | 39 | 37 | 97 |
| 4 | ≥20 (overkill) | 101 | 132 |
| 5 | ≥41 (overkill) | 88 | 139 |

`ATK-DEF` is wildly off for every target. `MGC-MGC` lands in the right
ballpark for every target, with an exact match on target 2 once the
elemental resist multiplier is applied. The small remaining misalignment
on targets 0/1/3 (off by 1-2) is consistent with the target-selection
loop's own variable reject-and-reroll mechanism consuming an unaccounted,
non-fixed number of `rand()` calls before the move-decision roll — an
alignment detail, not a contradiction of the core result.

**Conclusion at this stage**: this is a real, independently-reconfirmed
phenomenon, not an artifact of a wrong assumption. The mystery narrowed
entirely to *where in the code* the MGC-based override happens.

### The VM's cross-frame resumption mechanism decoded — still unresolved at this point

Decoded the animation VM's "dual-mode opcode" puzzle: a second driver
function, `FUN_800e358c`, runs once per frame for every active combatant,
reads a cached "currently paused opcode," re-invokes it with `mode=1` to
tick it, and resumes normal `mode=0` dispatch on completion. Slot `[4]`'s
complete bytecode was walked start to finish: 18 words, no sub-animation
spawn, no frame-callback install, no damage logic anywhere — closing off
the "dual-mode opcodes might hide something later" concern.

A genuinely new discovery while chasing this: a raw byte-pattern search
for instructions loading the cross-overlay callback-table pointer turned
up an entire, previously-undocumented VFX subsystem in Zombie Dragon's
overlay, identified by its own embedded debug string ("`fire func %d`").
Fully parsed end to end — zero calls to `calc_damage`/`apply_hp_damage_
display`, zero stat-field reads, anywhere in this chain.

An indirect-call audit across the whole overlay initially found no path to
it from either confirmed Zombie Dragon dispatch function, leading to a
**wrong conclusion (retracted below) that this subsystem was dead code**.

### RESOLVED, 2026-09-07: this is the real mechanism — the "dead code" conclusion was wrong

The user directly challenged the dead-code conclusion ("fire func looks
like fire breath, could be reachable — does it call RNG? that would
disprove it's dead"), which prompted a closer re-read of the tick state
machine's own decompile — already fully captured minutes earlier, but with
one critical call missed on first pass. Once its internal tick counter
passes 249, it loops every living party member and calls `RngCallbackTable`
slot 86 — a completely separate, dedicated formula function
(`calc_rune_element_attack_damage`) — then feeds the result into
`apply_hp_damage_display`. This is why a direct xref search on `calc_
damage`'s own address never found it: the real code doesn't call `calc_
damage` at all.

**Confirmed live 2026-09-07** against the real captured Fire Breath data:
read all 6 party members' actual equipped `Rune.Id`. The target showing
the 0.5× "resist" ratio (`MGC=80`, real damage `26` vs `~52` unscaled) has
`Rune.Id=1` (Soul Eater) equipped — confirming the resist was Soul Eater's
unconditional category-7 rule, not an element match. A separate target
with `Rune.Id=2` (Fire) took full, unreduced damage — confirming Fire Rune
does not resist Fire Breath, matching what the user independently recalled
from testing. **Category 6 (Resurrection alone) — confirmed live**: the
user directly tested Resurrection Rune against Fire Breath in-game and
confirmed it does reduce damage.

### A real compiled bug, found and confirmed live

Further user testing surfaced something the switch table alone didn't
predict: moving Cleo (Fire Rune) into party slot 6 did not reduce Fire
Breath damage (expected — Fire doesn't match `element=6`). But moving
Gremio (Holy Rune), or Viktor/Tai Ho/Camille (no rune equipped) into slot
6 *did* reduce it — despite none of those runes appearing in the
resistance table.

Reading the raw MIPS disassembly (not just the decompile) explained why:
for every `Rune.Id` not in the explicit table, the switch jumps straight
to the halving comparison without ever writing the "category" variable
(register `$s1`), which the *caller* (the fire_func tick state machine's
own damage loop) is reusing as the loop's own target-party-slot counter
(confirmed via disassembly: `addiu s1,s1,1` drives the loop, `move
a1,s1` passes that same register as `target_idx`). Confirmed exactly by
the user's own test results — Cleo's Fire Rune masks the bug (it
explicitly sets category 1 before the buggy read would otherwise occur),
while everyone else's rune (or lack of one) leaves the leftover
slot-index value in place. **Confirmed live** further: moving the
"resisted" characters to slots other than 6 made the reduction disappear
entirely.

A raw byte-pattern search for the exact call sequence across every monster
overlay this project has touched turned up at least 11 more call sites
across 7 different bosses/monsters — confirming this "beneficial exploit"
is a general property of the shared formula function, not Fire-Breath-
specific. Only the original Zombie Dragon/slot-6 case has been confirmed
in actual gameplay; every other "live" row in the table is a static
prediction from disassembly alone, not yet tested in-game.

### Reconciling the multi-target mechanism with fire_func

The multi-target mechanism (`battle_enemy_attack_advance_multitarget`/
`battle_enemy_attack_multitarget_continue`, gated on class/equip byte
`==0x0e`) describes real, existing code — `calc_damage`, ATK-DEF, one
`battle_execute_enemy_attack` call per target — but the actual empirically-
confirmed Fire Breath damage comes from the separate `fire_func`/
`calc_rune_element_attack_damage` path instead. Since `apply_hp_damage_
display` only accumulates a delta rather than overwriting HP outright, if
both mechanisms genuinely fired for the same cast the two damage
contributions should stack — but the live re-validation matched
`fire_func`'s formula alone with no sign of an additional ATK-DEF-shaped
component. Likely explanation, not confirmed: Zombie Dragon's specific
attacker/equip check (`class_ptrs[attacker]->+0x1c->+0x4c == 0x0e`) may not
actually evaluate true for her during a real Fire Breath cast — meaning
this multi-target mechanism may describe a different monster's or move's
own code path that happens to share the same general-purpose functions.
Worth checking directly (read `combatant_rec+0x4a` bit `0x4000` live
during a real fire-breath cast) if this comes up again. The exact call
site that resolves and invokes catalog slot 6 (as opposed to slots 1/4)
wasn't pinned down either.

## Neclord's real Castle fight

Started as a deliberate exercise in how far pure Ghidra analysis can get
without any live capture, following
[Enemy_AI_Tracing_Methodology.md](./Enemy_AI_Tracing_Methodology.md),
then continued with two user-supplied savestates (`Neclord.State`,
`NeclordBats.State` — the same battle position, RNG modified in the second
to force the Bats branch) once static analysis hit a real wall on the
poison mechanism.

**"Always uses its one special move" note was incomplete, not wrong** —
that earlier description only covered the target-selection function
itself, which just schedules a fixed continuation; the real move choice
lives in the continuation, and turned out to be a 3-way split rather than
Dragon's simple two-way gate.

**Three genuinely different attacks, confirmed after an initial wrong
conclusion.** The first pass wrongly concluded all three scripts converge
on one shared damage handler (reasoning from code proximity — a small
busy-gate function gets installed as the post-dispatch continuation
regardless of which script ran, and the nearest subsequent code happened
to belong to only one of the three attacks). **The user, who knows
Neclord's real moveset, directly corrected this**: he has an AoE Wind
attack, an AoE Lightning attack, and a single-target physical bat-swarm
attack. Tracing each script's own actual damage call site (rather than
assuming shared control flow from proximity) confirmed this exactly.
Matches the user's "probably physical" guess for Bats exactly.

**Process note**: the wrong "one shared handler" conclusion came from
assuming code adjacency implied control flow, without actually checking
each of the three paths' own eventual damage call. The fix was the same
discipline used elsewhere in this project — trace the *specific* call site
for each claimed outcome rather than inferring from a plausible-looking
nearby function.

**Where static analysis hit its actual wall (poison)**: the exact
addresses of the 3 per-script custom frame callbacks were not resolved
through the natural static candidate for the table's own base (turned out
to be a different, unrelated data block). The Wind/Lightning damage
mechanisms were found by directly disassembling forward from each script's
dispatch point and a byte-pattern search, but a live-confirmed poison
effect resisted every static lead: no `apply_status_effect` call in the
Bats tick machine's own decompile, and two nearby "hit-reaction"-shaped
scripts had no `anim_op_roll_status_effect_chance` call in either.

**Bats' poison mechanism** was resolved by tracing the RNG advancement
mechanic end-to-end (`scripts/SettleNeclordBatsRNG.lua`), which surfaced
the poison call site as a direct byproduct. Ground truth: LCG-step-
counting against `NeclordBats.State`'s own seed gave an exact total of 86
`rand()` calls. One correction along the way: the user had originally
labeled `Neclord.State` "before a Wind attack," but the traced move-choice
formula predicted Lightning for that seed — a live HP-damage-pattern check
plus the user's own follow-up ("My label was wrong, it was Lightning")
settled it in the formula's favor. This also resolved why an earlier live
trace found the target's own script-cursor field never changing: that
trace only polled once per frame, and the second script's entire execution
window completes within frames the per-frame poll's snapshots didn't
happen to land on — the same "multiple opcodes run within one frame,
invisible to per-frame polling" gotcha already documented elsewhere for
RNG call-counting, newly confirmed for script-cursor polling too.

**All three damage formulas, bit-exact confirmed (13/13 targets)**:
Lightning matched exactly including the register-reuse "resistance" bug on
both slot 3 and slot 5 — neither target's own equipped Rune maps to a real
category. Wind matched exactly too, but only slot 3 shows the halving this
time, not slot 5. Slot 3 being hit for *both* Wind's `element=5` and
Lightning's `element=4` rules out a naive "target index == element"
explanation for the bug's trigger — the exact register/loop-position
responsible isn't pinned down, but the bug's reality and reproducibility
are confirmed two ways. Bats: predicted 313 raw damage; observed live
damage was 156 = `313 // 2` exactly — all 6 party members had
`ActionType==1` (Defend) at the time, this is `calc_damage`'s own
already-documented Defend-halving rule applying normally, nothing
Neclord-specific.

Only a broader multi-seed sweep (matching Dragon's own 92-seed validation)
remains as a nice-to-have; the mechanism itself is closed out.

## Two identity corrections surfaced along the way

**"Dragon" is not the final boss.** This project had labeled
`dragon_overlay.bin`'s monster (HP 6000) "the final boss dragon" based only
on matching her HP/Id against an external stat reference — never confirmed
via her own in-game name. A direct charmap name-search within that overlay
for both "Dragon" and "Golden Hydra" found neither as plain text, prompting
a disc-wide search for "Hydra" instead, which found exactly one hit:
`vzv.bin`. Her own overlay has 3 `calc_rune_element_attack_damage` call
sites — more than the 2 moves she's known to have, so at least one of her
moves likely has 2 damage phases, not yet disambiguated. "Dragon" herself
remains a real, separate, still-unidentified mid/late-game boss under this
framing — her true identity wasn't re-established this pass.

**`vc3.bin` hosts multiple monsters, confirmed** — this project already
had CrimsonDwarf's AI documented in `vc3.bin`; a fresh pass investigating
the new slot-86 call site found a second, previously-undocumented AI
function in the same file, self-identified as `gigantes_ai_select_target_
and_move`.

## How monster overlays are actually organized

Prompted by the `vc3.bin` finding above — checked whether overlay files
carry some kind of internal "monster directory" a human (or the game)
could read to enumerate everyone packed into one file. No such structure
was found; the start of `vc3.bin` is just code and two debug strings
("bunshin" = Japanese for "clone/double," fitting flavor for a monster
whose own move is a repeat-attack), not an index.

The real answer turned out to already exist on the Lua side:
`lib/EncounterTable.lua`, listing every area's random-encounter roster by
name. Cross-referencing `vc3.bin`'s two known bosses against
`EncounterTable.lua`'s `DWARVES_VAULT` entry and charmap-searching `vc3.bin`
for those names directly confirmed both Death Machine variants also live
in `vc3.bin`. (Death Boar itself wasn't found in `vc3.bin` — it's shared
with the neighboring `DWARF_TRAIL` encounter table too, so it likely lives
in a separate, common file referenced by both areas; not chased further.)

**Practical technique for any future overlay-mapping work**: find one
boss's overlay via the usual name-search method, identify the area from
context, then charmap-search that same overlay for every name in that
area's `enemies` list. One gotcha: `EncounterTable.lua` sometimes appends a
disambiguating suffix (`"Death Machine R"`/`"Death Machine B"`) when two
monsters share an in-game name — that suffix is human-added, not part of
the real charmap-encoded name, and searching for it verbatim will silently
fail. Strip it before encoding.

## Dead end: `vc61.bin` ("Dragon")'s garbled AI code is NOT explained by LZ compression

Goal was to read boss AI statically, with no live emulator session, for
small overlays like `vc61.bin` (31412 bytes) where the monster record
decodes correctly in plaintext (file offset 0x3f4, AI pointer value
`0x80012594` matching the already-known live-derived address) but the raw
bytes at that same address under a naive `file_offset = runtime_addr -
0x80010000` mapping are not valid MIPS.

Found and fully decompiled `lz_decompress` (`0x800c3144`, `main.exe`) — a
real 1024-byte ring-buffer LZSS-style decompressor — plus its wrapper
`decompress_4bit_graphics`. Reimplemented it in Python and tested it
against `vc61.bin` several ways; none produced anything resembling the
decompressed AI code or even preserved the plaintext "Dragon" name that
should survive if the record itself is outside any compressed span.
Checking every actual caller of `lz_decompress` in Ghidra showed all of
them decompress into texture/sprite-dimension-sized buffers — this
function is used exclusively for compressed graphics assets in this
engine, never for code overlays. Ruled out.

**Leading unproven hypothesis for next time**: `vc61.bin`'s small size
(31KB, vs. 250-600KB for "normal" self-contained boss overlays that read
their AI code directly with no compression) suggests it may be a small
delta/patch overlay carrying only monster-specific *data*, while its AI
*code* actually lives in a larger shared/generic template overlay already
resident in memory by the time `vc61.bin` loads. Not yet tested.

**Correction, 2026-09-07: `vc61.bin` is NOT an unrelated file — retracting
the earlier "94% different, coincidental match" conclusion above.** A
later, independent pass (using the disc-wide `MonsterRecord`-shape
scanner, see
[Monster_AI_Static_Catalog.md](../docs/game_mechanics/Monster_AI_Static_Catalog.md))
found `vc61.bin`'s own monster record decodes perfectly at file offset
`0x3f4`: name "Dragon", level 40, HP 6000, PWR 250, DEF 35, SPD 40, MGC
150, LUK 65 — all seven fields exact matches — and its `pAiFunction`
field's raw VALUE is `0x80012594`, exactly the live-derived AI address.
That many independent structured fields agreeing, at a meaningful (not
arbitrary) file offset, cannot reasonably be coincidence — unlike a raw
whole-file byte-diff percentage, which proves nothing about a *compressed*
file. The correct current understanding: `vc61.bin` **is** genuinely
Dragon's own disc file; its data section is plaintext, but its code
section does not decode as valid MIPS under the naive mapping every other
overlay in this project uses. The real explanation for why this one
overlay's code doesn't decode directly remains open. Always verify a
disc-file identification against multiple independent structured fields
(not just a plausible address, and not just a raw byte-diff percentage)
before concluding a match is right *or* wrong — the same standard
`vb5g.bin` was confirmed against for Zombie Dragon.

Also: **Dragon was resolved after all**, once the user supplied a
savestate actually inside that fight (`TurnOrderRNGCall.State`) — the
name-search approach genuinely couldn't have found this one ("Dragon" is
too short/common a string; a full-disc search turned up 144 raw hits,
every single one ordinary story dialogue about "Dragon Knights"/"Dragon's
Den", no genuine monster record among them). Live-resolved via the
reliable method instead: read `Id`/HP directly (`Id=1`, `HP=5818/6000` —
matches the known Dragon boss stats exactly), followed `attack_data_
table[Id]+0x30`, and dumped the live overlay fresh rather than trust
either of the earlier disc-search candidates.

**Sydonia's counterattack investigation**: investigating a suspicious
debug string (`"sid wait\n"`) scheduled after her special move led to a
whole side-investigation. Initial read: a Varkas tag-team combo.
Corrected (user pushback + re-reading `play_attack_animation`'s own
confirmed semantics for `enemy_data+4`): it's actually a counterattack
structure. Manually parsed Sydonia's own special-move script bytecode end
to end — opcode 26 never appears in it, so her own attack can never arm
this counter. User confirmed live this never triggers in the actual fight.

## Dragon's move selection

Fully solved and validated to a perfect 92/92 across three independent
random-seed sweeps (12 + 30 + 50 seeds).

<details>
<summary>Investigation notes (two wrong turns, both caught by direct user challenge, before landing on the final answer)</summary>

The move-choice roll's real location took three passes to find. First
guess — `dragon_move_confirm_or_override_to_fire_breath` (`c_data.bin @
0x80080490`, found via a raw byte-search for Zombie Dragon's own `0x7fff`
divisor constant) — had the identical formula and looked entirely
plausible, matching ~90% of a 12+30-seed live sample. But it was wrong:
directly checking whether it ever writes its own target-lock fields a
second time across full-length live traces showed those fields are
written exactly once, by the first scan, and never again — that function's
code never actually executes for Dragon's turn. The formula match was a
coincidence (likely a shared/templated pattern reused elsewhere in the
same shared area overlay), not causation.

Chasing the resulting ~10% prediction gap, a first theory blamed
hit-effect/particle VFX consumption interleaving with the decision roll.
The user caught the flaw directly: "the vfx rng rolls start after a move
is selected, which means they can't interfere with the move selection
roll" — correct, and retracted. The real location was found by abandoning
the `battle_base+0xc` coroutine chain entirely (confirmed dead past frame
2, even at the exact frame damage lands) and checking `main.exe`'s
separate per-frame callback system instead, which led to `dragon_special_
move_real_frame_callback` — confirmed by directly watching `enemy_data
[Dragon]+0x54` install that function's address at the right moment, not
inferred.

Even after finding the right function, the ~90%-only match rate had one
more real bug, not random noise: every single mismatch (4 of 42, across
both live batches) had the simulated target-scan reject all 3 candidates —
0/4 correct there, vs. 38/38 correct whenever any candidate accepted. The
Python model was rolling once more on an all-reject outcome and treating
that as the move-choice roll, instead of retrying the whole 3-candidate
scan fresh (matching the real dispatcher's own retry behavior). Fixing the
retry loop scored 42/42, and a fully independent 50-seed re-verification
held at 50/50 with no changes — 92/92 total, zero residual.

**Process lesson**: a formula that matches most of a live sample is not
proof it's the right causal function — always verify the specific code
path actually executes (watch its own distinctive memory writes across a
full live sequence) before treating a numeric match as confirmation. And a
"mostly right" result is worth checking for a 100%-clean split by some
categorical variable before accepting it as irreducible noise — that split
is the signature of a real, fixable bug, not something to explain away.
</details>

### Lightning's RNG cost — errors avoided while reverse-engineering it

- **Naive per-frame "did the RNG value change" counting undercounts by an
  order of magnitude.** An early pass reported totals of 69-77, because
  many `rand()` calls can land within a single frame's CPU execution and
  get collapsed into "one change." The fix: let the RNG **settle**
  (unchanged for 30 consecutive frames) after the attack fully resolves,
  then recover the exact call count by forward-simulating from the start
  seed until it reaches that settled value.
- **A red herring in the disassembly**: the state-machine function called
  immediately after move-choice resolves (formerly misnamed
  `..._tick_state_machine`) turns out to be a texture-decompression-queue
  waiter, not the particle driver — its own `RngCallbackTable` calls all
  resolve to `main.exe`'s texture-decompression subsystem. The real
  particle-spawn driver is the function it hands off to.
- **First simulator draft undercounted** by modeling only the lifetime
  countdown and missing the position-based deactivation entirely — found
  by re-examining the render function and noticing it performs `posZ +=
  velZ` as a side effect even though it makes zero `rand()` calls itself.
- **Second draft was still off by ~5-10%** even after adding position
  integration. The root cause was a test-harness bug, not a mechanism bug:
  the harness was invoking the VFX simulation directly on the original
  seed, skipping the already-validated target-scan-with-retry and
  move-choice roll that must run first. Chaining those correctly
  immediately produced bit-exact matches on all 16 seeds.

`Queen Ant` and `Crystal Core` are traced but deliberately not wired into
`lib/EnemyAIPredictor.lua`'s live HUD display — both have self/
globally-triggered mechanics that don't fit a "pick a party-member target"
probability output.

### Dragon's damage formula

User's hypothesis going in: "it likely uses the same structure as Zombie
Dragon, but it might use a different value for its ATK instead of MGC."
Confirmed the structure matches Zombie Dragon exactly, but refuted the ATK
hypothesis — both of Dragon's moves use MGC. Confirmed three independent
ways: the decompile reads `wMGC` for both sides; a live memory check of
`Dragon.State` shows genuinely distinct `ATK=250`/`MGC=150` (not aliased or
bugged together); predicted damage from `attacker.MGC(150) - target.MGC`
matches every observed live damage value exactly (8/8 Lightning seeds, 5/6
Fire Breath targets in one capture).

Fire Breath's register-reuse bug was directly confirmed, not just
predicted: a 6-target live Fire Breath capture matched the plain formula
exactly on 5/6 targets, and the 6th (slot 1, predicted 31 unscaled) only
matched the observed value of 15 once the extra halving was included
(`31 // 2 = 15`) — the mismatch was the bug firing, not a formula error.

## Queen Ant's full moveset and the 3 accompanying ants — a long correction chain

User: "the Queen Ant fight in Mt. Seifu that comes with 3 ants. I want to
understand the behavior of all enemies there." No savestate was available
for this specific fight initially, so the first pass was read from the
decompile only.

**Correction #1 (same day, live-validated):** that first pass concluded
Queen Ant's own ~51% attack branch was "visual-only, dealing no damage" —
the user caught this immediately: "You're missing at least 1 attack, she
has an AoE magic that hits all characters, looks similar to a Voice of
Earth spell," and supplied a fresh start-of-fight savestate
(`QueenAnt.State`) to test with. The mistake was the same class already
made once before with Neclord's hidden Poison roll: checking only the
C-level tick functions for a direct damage-formula call, when the real
call lives in script-installed per-frame coroutine code with no C-level
xrefs at all. **Live-confirmed** via `scripts/CaptureQueenAntRounds.lua`:
round 1 showed all 5 party members taking damage in the same round, in
five different amounts (-8, -29, -18, -48, -38) — exactly the "hits all
characters" signature the user described.

**The headline finding**: the "3 ants" have no independent decision-making
when Queen Ant triggers them — or so it initially seemed. `queen_ant_ai_
self_heal_and_select_move` resets her own current HP to max every turn
(matches her canonical regeneration/egg-laying lore directly in code).
Exact probability was brute-forced 2026-09-07 (user: "I need to know it's
probablity vs it's Earth move" — not a rounded estimate, since RNG2 is a
direct bit-extraction from a uniformly-distributed seed, not a modulo/hash
that could bias the split): AoE Earth = 51.0010%, CommandAnts = 48.9990%.

**CommandAnts retested 2026-09-07 (user: "Queen Ant's Command Ants is
essentially a dead move, but I still need to know if it pushed RNG"):
CONFIRMED zero RNG cost even as a no-op.** Both the gate and the command
function contain zero `rand()`-consuming instructions in every code path,
confirmed both on paper and via a fresh live retest reading identical RNG
state across the sequence.

**MAJOR CORRECTION, 2026-09-07 (user: "It looks like the soldier ants are
faster than Queen Ant, could it be running its command ants attack after
the ants have already gone?").** Exactly right, and worse than
"sometimes": it's algebraically guaranteed, every time. Turn order picks
the next actor by `weight = SPD*10 - 5 + rand()%10` among everyone who
hasn't yet acted. Soldier Ant's SPD=22 gives weight range `[215,224]`;
Queen Ant's SPD=20 gives `[195,204]` — these ranges never overlap, so
every living ant is guaranteed to take its own independent turn before
Queen Ant's turn ever comes up, with zero chance for jitter to change
that.

This retracted BOTH intermediate corrections previously recorded here
(target attribution via each ant's `bAnimTargetIdx`; the "RNG cost is 1
roll not 2" finding) — both were, unknowingly, observations of the ants'
own independent turns, not of Queen commanding anyone. Verified directly
(`scripts/VerifyAntCommandAttribution.lua`): at the exact frame the
command function executed, all 3 ants showed `ActionTag=1`, and each
"commanded" ant's own continuation pointer was `apply_uncovered_attack_
damage` (the generic single-attack resolver installed by the ant's own
independent turn), never `ant_commanded_attack_damage` (Queen's own
commanded-attack function) — which has never been observed to actually
fire in any tested round. **The lesson: a plausible-looking target+damage
match isn't proof you're watching the function you think you are — verify
the actual continuation-pointer address, not just outcome consistency,
when two different code paths could both plausibly produce "monster hits
party member with calc_damage."**

`ant_commanded_attack_damage`'s own disassembly (re-confirmed, not a
misreading) still calls `calc_damage` twice in a row with identical
arguments, discarding the first result and applying only the second —
`lib/Enemies/QueenAnt.lua`'s functions modeling this were reverted to a
2-roll model, since the "1 roll" live-measurement was actually of a
different function. Whether it really costs 2 rolls or some caching effect
makes it 1 remains genuinely untested — no live capture of this function
actually executing exists yet.

**Third correction/validation pass, 2026-09-07 (user: "Run simulations to
confirm our results are accurate")**: built
`scripts/TraceQueenAntMoveSelection.lua`, watching `BattleState+0xc` plus
`Address.RNG` and every combatant's HP/busy-flag every frame. Move-
selection threshold bit-exact confirmed both branches (two real seeds
captured at the exact transition frame). AoE RNG cost bit-exact confirmed
(with party slot 2 already dead entering a later round, RNG state advanced
by exactly 4 steps matching the 4 remaining living slots — dead slots cost
0 rolls). AoE damage bit-exact confirmed for all 4 targets: 2 survivors
matched immediately; the other 2 would have died naturally, so a follow-up
(`scripts/CheckQueenAntAoeDamageNoDeath.lua`, prompted by the user: "check
by calculating the damage rolls... regardless") boosted their HP before
the AoE fired.

**In-spec test-injection lesson**: first attempt used a flat 9999 boost —
this overshot every target's own max and triggered an unrelated "clamp
current HP to max" correction that erased the AoE's own damage entirely
before it could be read (all 4 boosted targets ended up exactly at their
own HPMax, not HPMax-minus-damage). Corrected to `HPMax - 1` and re-run:
all 4 targets matched the plain neutral formula exactly, zero mismatches —
a real lesson: keep injected test values in-spec, not just "large enough."

**The "slot 3 register-reuse bug" is RETRACTED.** An earlier pass
(informed by a static note from a prior session identifying `$s0` as the
fallback register) claimed party slot 3 specifically takes an accidental
~50% reduction in this loop. Slot 3's live-captured damage (18) contradicts
the halved prediction (9) and matches the plain formula exactly. Whether
some other condition still causes an occasional halving here is an open
question this one clean counterexample doesn't fully settle — it only
disproves "slot 3 always halves" as a blanket rule.

**Fourth pass, 2026-09-07 (user: "Can we check the ant targeting and
damage?" then a follow-up: "Ant has 2 different attacks... perhaps that's
the 2nd roll you saw?"): SUPERSEDED by the MAJOR CORRECTION above.** This
pass originally claimed to have live-validated `ant_commanded_attack_
damage`'s per-ant target attribution and disproved its RNG cost down to
"1 roll," and then further "ruled out" a hidden move-choice with a 4th
sample. All of that live validation was actually measuring `apply_
uncovered_attack_damage` by mistake, per the SPD-guarantee finding above —
the numbers captured (targets 2/1/3, damage 26/10/17/12) were real, just
attributed to the wrong function. The one genuinely-confirmed finding from
that pass survives intact: with only 1 living party member left, only 1
ant actually attacked that round — the other 2 ants' target fields held
stale data rather than fresh values.

**Soldier Ant live validation, 2026-09-07 (user: "Did you run sims to
confirm our functions are accurate?" -> "I'm talking about the probability
for ant attacks, and the damage rolls").** Neither the 77%/23% split nor
the DoubleStrike damage formula had ever been live-tested before this
pass — no DoubleStrike instance had even been observed. 2 real DoubleStrike
instances captured (`scripts/HuntSoldierAntDoubleStrike.lua`, 8 rounds) —
the first ever observed live in this project. Ant8's target survived
naturally (32 damage, exact match). Ant6's target died even after boosting
HP to `HPMax-1` right before the hit — the doubled roll can exceed a
target's own real max HP entirely (base 48-21=27, doubled range ~50-58,
above that target's own HPMax of 55). Fixed by raising `HPMax` itself to
300 first (not just current HP past a stale max, which would trigger the
same "clamp to max" bug already documented for Queen Ant's own AoE
capture), then setting current to 299 — got a clean 56-damage reading.

**Open ends, honestly flagged**: `QueenAnt.State`'s own formation was
confirmed live as exactly 5 party members + 3 Soldier Ants + Queen Ant,
but whether the ant count is always exactly 3 across other encounters of
this fight, or variable/replenished via the round-3-callback's own
respawn mechanic, wasn't independently re-checked; the exact opcode-level
trigger chain from `queen_ant_own_attack_windup`'s script dispatch to
`queen_ant_aoe_earth_cast`'s install as a frame callback wasn't read
byte-by-byte (inferred from live behavior + code shape); `enemy_data
[self]+0x90` bit `0x2` (the precondition gating whether her command-branch
counter even decrements) wasn't identified; whether any condition causes
an accidental resistance halving in the AoE loop is unresolved; and
`ant_commanded_attack_damage`'s real RNG cost remains completely untested,
since no live capture of it actually firing exists.

### Queen Ant's round-3 battle-end and ant-respawn mechanic

Prompted by the user's own game knowledge ("the 3rd turn of Queen Ant
always ends the fight") while discussing `Turn_Order.md`'s unresolved "who
arms `+0x1330`" question. The user supplied a savestate
(`QueenAntT3End.State`) sitting right at round 3 — reading live memory
confirmed `BattleState+0x1330 = 1` and `+0x1334 = 0x8001139c`, the first
live confirmation that any real encounter actually uses this hook
(previously only traced structurally, never seen armed). The
"declare victory" step wasn't traced further (the chain leads to a generic
coroutine-state write, not an obviously-named "battle over" function), but
the round-number threshold match against the user's own description is
already a clean, solid confirmation.

**Caveat added after checking the Ted-vs-Queen-Ant fight below**:
`SyncSignals+4` is also set by that completely different scripted
encounter, in a context that's obviously about forcing a turn, not ending
a battle — so it's better understood as a general resync signal, not
literally "end the battle" by itself. It plausibly *leads to* the battle
ending here, but the direct causal link wasn't independently observed.

### The scripted Ted-vs-Queen-Ant "forced Hell cast" fight

The user's second suggested candidate for the `+0x1330`/`+0x1334` hook,
checked immediately after the round-3 finding above with another
user-supplied savestate (`QueenAntTed.State`). As a side benefit,
`AbilitySlot=3` for this forced Hell cast is independent live confirmation
for the "should be level 3" open question about Hell's spell numbering
(see Open Questions below).

## Regular (non-boss) enemy AI

Dug into whether ordinary field encounters use the same hand-scripted-
per-monster AI shape as story bosses, or some shared generic routine. So
"regular enemies use it, bosses don't" (a hypothesis this project once
held) is refuted, not just untested.

**Killer Rabbit is the interesting exception.** User confirmed this enemy
has genuine long-range targeting and provided a live savestate
(`KillerRabbit.State`) to check it directly.

This surfaced an important technical correction: `b_data.bin` (and almost
certainly `h_data.bin` and every other per-area `NN_area.X/X_data.bin`
file) actually loads at runtime base `0x80080000`, not `0x80010000` like
the boss-specific `vXX.bin` overlays. Caught because the live-read monster
record's sanitized address (`0x8009f748`) only lines up with the file's
own byte offset (`0x1f748`) under that base — assuming `0x80010000` put
the record's `+0x30` AI-function pointer outside the file's own mapped
range, exactly the same failure hit earlier for EarthGolem/`h_data.bin` —
that one is now understood to be the same base-address bug, not evidence
its AI lives elsewhere entirely.

A byte-pattern search for `lbu`/`lb` reads of offset `0x11` across
`b_data.bin`'s entire ~161KB file (not just the AI functions) found zero
hits — strong evidence against `+0x11` being the S/M/L range mechanism
even for a monster with unambiguous, code-confirmed long-range behavior.

**3 more regular monsters traced 2026-09-07 (structural decompile only,
no live validation)** via the same static disc-file technique: Slasher
Rabbit, Rabbit Bird, Dagon. None of these 3 have been behaviorally
validated against a captured live seed — a future pass would need a
savestate for each to run the full validation checklist. Dagon's exact
branch polarity of its "commit to plain Attack vs. abandon" fallback
wasn't independently re-verified and deserves a careful re-read before
relying on it, given this project's history of misread branch polarities
elsewhere (e.g. Zombie Dragon's own first-pass accept/reject mixup, see
`Enemy_AI_Tracing_Methodology.md`).

## Open questions / not yet done

- ~~Full Ghidra struct definitions for the battle-state struct, the
  combatant stat record, and the equipment/class record~~ — done
  2026-09-07: `BattleState`, `CombatantRec`, `EnemyData`, `MonsterRecord`,
  `ClassPtrEntry` are now real Ghidra types. What this doc was calling the
  "equipment/class record" turned out to just be the character's
  already-known persistent Stats struct, not a separate battle-only
  record — no new struct needed there, just correcting the earlier
  mislabeling. A future pass could add a `PersistentStats` Ghidra struct
  type covering the known offsets, mirroring the existing Lua-side field
  layout, if that struct gets touched by enough battle code to be worth
  formalizing on the Ghidra side too.
- ~~AI/enemy action selection~~ — resolved for Zombie Dragon 2026-09-06,
  generalized to 9 more regular monsters 2026-09-06/07: CrimsonDwarf,
  Colossus, DevilArmor, DevilShield, GiantSnail, Killer Rabbit, Slasher
  Rabbit, Rabbit Bird, Dagon — all structurally decompiled via the static
  disc-file technique, only Zombie Dragon (and Killer Rabbit, via a
  user-supplied savestate) are behaviorally live-validated. 3 template
  shapes identified so far: plain front-row-scan+Attack, a move-gate
  variant (`0x33` threshold, seen in DevilShield and Dagon), and a
  leap-clone long-range variant (Killer Rabbit, Slasher Rabbit). Every
  OTHER monster's own AI function pointer still needs its own overlay
  dumped and traced individually if it comes up again — the technique
  itself is now well-proven and repeatable, just not exhaustively applied
  to every monster in the game.
- ~~Whether `g_abWeaponTypeToElement`'s ids `0-4` line up with the
  magic-side element numbering~~ — resolved 2026-09-07: yes, one unified
  enum, not a separate weapon-only scheme. Confirmed directly in `calc_
  damage`'s own decompile: it computes `element_id` from this table then
  indexes the exact same `attack_data_table[target.Id]+0x20+element_id`
  compatibility row that `apply_elemental_multiplier` uses for spells.
  `lib/Magic.lua` has no separate element-id table of its own to
  cross-check — the magic-side numbering comes entirely from `apply_
  elemental_multiplier`'s own 21 call sites, already cross-validated
  against `Suikoden-RNG-lib`'s `Spells.js` damage values.
- `0x80116078`'s (Hell's) `a0=4` still doesn't match its confirmed
  identity (should be level 3 by spell order) — behavior confirms the
  spell, the numbering discrepancy is unexplained. Independent supporting
  evidence for "should be level 3" found 2026-09-07: live-reading the
  scripted Ted-vs-Queen-Ant fight showed Ted's forced action set to
  `AbilitySlot(+0x48) = 3` for his scripted Hell cast — directly confirms
  level 3 is really the slot used to cast Hell in practice, leaving the
  internal `a0=4` mismatch inside Hell's own cast-entry code as the only
  remaining unexplained piece.
- The external `Suikoden-RNG-lib` reference has at least one confirmed
  inaccuracy (Charm Arrow: lists 400 dmg, the ROM's real value is 500,
  confirmed via live gameplay math) — treat its damage numbers as a strong
  lead, not ground truth, until cross-checked.
- The Zombie Dragon third-formula section: the ATK-DEF-vs-MGC contradiction
  with `calc_damage`'s own disassembled code — narrowed 2026-09-07: the
  "coincidental DEF==MGC" explanation is now definitively ruled out via a
  live read, leaving only "the monster's own attack script overrides the
  damage with its own MGC-based opcode" as the explanation — that specific
  opcode hasn't been located yet, would need Zombie Dragon's fire-breath
  script bytecode parsed end-to-end.
- Poison's duration-slot decrement-and-clear consumer (the generic
  per-status table entry for `id0`) was not located.
- Queen Ant: whether the ant count is always exactly 3 across other
  encounters of this fight, the exact opcode-level trigger chain from her
  attack windup to the AoE cast's install as a frame callback, the
  `enemy_data[self]+0x90` bit `0x2` precondition, whether any condition
  still causes an accidental resistance halving in her AoE loop, and
  `ant_commanded_attack_damage`'s real RNG cost — all untested/unresolved.
- Dagon's branch-polarity uncertainty on its Attack-vs-abandon fallback,
  and the general caveat that Slasher Rabbit/Rabbit Bird/Dagon are
  structural-only reads with no live validation yet.
