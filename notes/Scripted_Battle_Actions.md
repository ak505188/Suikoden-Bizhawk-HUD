# Scripted Battle Actions — investigation history

This is the history behind
[docs/game_mechanics/Scripted_Battle_Actions.md](../docs/game_mechanics/Scripted_Battle_Actions.md):
corrections, dead ends, live-testing sessions, and open questions that shaped the current clean
write-up. Section headers below correspond to sections in that doc.

## The two separate systems

An earlier pass at this investigation (see `battle_dispatch_current_actor_action` in
Turn_Order.md) found that a party member's queued action executes the instant
`combatant_rec+0x47` (`ActionType`) holds a valid value once it's their turn — no separate
"confirmed" flag. That's true, but incomplete: it only covers what happens *after* a round's
commands already exist. Getting there in the first place goes through the menu system now
documented in the main doc, confirmed live against `ZombieDragonStart.State`.

**The pre-writing test that ruled out a pure combatant-state bypass**: a test wrote valid Attack
commands for all 6 party members directly into `combatant_rec`, immediately after the savestate
loaded (before touching the Fight/Run/Bribe/Free Will menu at all), then advanced 750 frames
with zero input: nothing happened — `CURRENT_ACTOR` stayed at its uninitialized value, no HP
changed, the round never started. This is what established that the round-start menu is driven
by real (or simulated) button-press edges, not by polling combatant state.

## The menu system, decompiled

The round-start menu functions and `DAT_80179fe8` context struct (now in the main doc) were
found by reading `DAT_8017da90`'s coroutine slot 3 (a *third* coroutine slot, entirely separate
from `battle_advance_turn`/`battle_dispatch_current_actor_action`'s own slot) directly
before/after each real menu step — its stored address changes to one of the three menu functions
at exactly the point each UI screen appears.

## Why a pure memory-only bypass doesn't work (confirmed, not just suspected)

This was tested directly, since it's the more interesting question than "what taps work": write
`DAT_8017be4c = 0x41` (confirm) and the widget's own confirm bit, with **zero joypad/`Buttons`
calls anywhere in the script**, and see if the menu advances on its own.

- A single write did nothing lasting — the very next read showed the widget's confirm bit and
  the phase counter *already* looking "confirmed" from a previous real tap, then reverting.
- Holding the write across 8 consecutive frames (writing fresh every frame, still zero joypad
  calls) caused visible internal churn — the phase counter briefly dropped from `2` back to
  `0`, the widget's flags word gained extra bits — but settled right back to the steady
  "waiting for input" state every time. `ActionType` never left `255`.

Reaching the one legitimate window between "input decoded" and "menu reads it" (rather than
relying on `joypad.set()`) would need an execution-level hook precise to that instant, and this
project already has a confirmed, separate finding that `event.onmemoryexecute` doesn't fire
reliably on this PSX core — so that door is closed with the tooling currently available.

## The optimized recipe: 2 taps total, any party size

Two things sped this up a lot past the first working version, each independently confirmed:

- Confirmed with `choice=3` (Free Will): writing `DAT_80179fe8+8` while stably at phase 2, then
  a single real confirm tap, immediately populated **every living party member's**
  `ActionType`/`AbilitySlot`/`TargetIdx` via the AI — skipping the per-character command/target
  menus entirely, not just navigating them faster.
- Confirmed by hand originally via the full manual path (Fight → Attack + default target × 6 →
  override actor 1 to Defend → confirm "Ok?"): actor 1 genuinely defended (absent from the whole
  round's damage sequence) while everyone else's unmodified Attack commands executed normally.

Combined, the recipe collapsed from **1 + 2×partyCount + 1 taps down to 2 taps, regardless of
party size**. `lib/BattleRoundInput.lua` was re-validated end-to-end after being rewritten
around this recipe — byte-for-byte the same result as the original 15-tap version (Viktor
overridden to Defend took the dragon's retaliation but dealt no damage; the other 5 party
members' AI-picked Attacks landed on the dragon for the same combined 176 damage), via
`scripts/SimulateZombieDragonRound.lua`.

The original, slower manual-navigation recipe (Fight → per-character Attack+target × N → an
extra unexplained tap → Ok) is documented in git history / the plate comments if the exact
sequence is ever needed again.

## How to know the prompt is actually ready (no more frame-count guessing)

The polling check documented in the main doc replaces an earlier fixed ~150-frame guess — it's
both more reliable and faster: ready by frame ~95–113 on `ZombieDragonStart.State` across
repeated runs. The two phase gotchas (phase 1 vs phase 2, and each menu function defining its
own meaning for the shared phase counter) both cost real debugging time before being pinned
down.

## What the "Ok?" confirm actually touches (from a before/after memory diff)

Diffing the live battle struct across the exact frame the "Ok?" tap is processed surfaced the
`DAT_8017be3c+0x4` round counter, `enemy_data+0x40` bulk-clear, and the `ActionTag` reset now in
the main doc, plus:

- **`DAT_8017be3c+0x4` flips `0` → `1`** at this exact moment. **Corrected 2026-09-06**: this
  isn't a boolean "confirmed" flag as first thought (that read was only ever watched across a
  single round) — it's a genuine **turn/round counter**, confirmed live by diffing the whole
  battle struct across 3 consecutive rounds: `0 → 1 → 2 → 3`, and the only offset in the whole
  struct (a 0x4000-byte window scanned) showing a consistent per-round delta. Read as a full
  32-bit value (`memory.read_u32_le`, confirmed the upper 3 bytes stay 0 — it's just a small
  counter, not part of a packed field).
  **Corrected again 2026-09-06, this time on WHEN it flips**: it increments the INSTANT a round
  is confirmed (the very first frame after the "Ok?" tap), not when the round actually finishes
  — confirmed by tracing a real round frame-by-frame: the counter moved at frame+1, while HP
  kept changing for 900+ more frames as combat actually resolved. `lib/BattleRoundInput.lua`'s
  `waitForRoundComplete()` originally tried using this counter for "has the round finished" and
  returned near-instantly, before any action had resolved — a real bug, caught by testing with a
  guaranteed-damaging action set and finding HP hadn't moved at all.
  **Not sufficient alone to start a round**: writing it directly (with valid actions already in
  place) while the round-start menu is still up does nothing, confirming the menu UI's own state
  (not this counter) is the real gate on whether `battle_dispatch_current_actor_action`'s
  coroutine chain is even running yet.
- A handful of other scattered writes near `combatant_rec`'s per-actor region that don't yet
  have an established meaning — not chased further this pass.

## Enumerating a character's available actions

**Rune enumeration**: a prior session's attempt to read the equipped-rune id from a separate
battle-only "equip record" was simply the wrong structure, not a wrong offset — the real address
is the already-documented persistent Stats `+0x4C`. `DAT_8016a0e0[rune_id]` was confirmed by
charmap-decoding its own leading bytes as the rune's name ("Fire Rune", "Water Rune", "Soul
Eater" all decoded exactly). The slot→spell-id mapping was confirmed end-to-end: Fire's slot 4
byte reads `4`, and `DAT_8016d33c[4]+0x1c` reads `0x80101130` — Explosion's own already-confirmed
cast-entry address, an exact match. The MP gate was confirmed exactly: McDohl's Judgement (Lv4)
was unavailable in `ZombieDragonStart.State` purely because his MP4 was `0`.

**The story/scenario-flag lock, confirmed for Soul Eater specifically by comparing two save
states**:

- `ZombieDragonT2.State` (McDohl): the selectable-levels table (`DAT_80179fe8+0x80`) = `[1]`
  only. His MP there is `MP1=5, MP2=2, MP3=1, MP4=0` — MP2 and MP3 are both nonzero, so MP alone
  would predict levels 1-3 all selectable. Only level 1 appears.
- `StormFang.State` (McDohl): table = `[1, 2, 3]`. His MP there is `MP1=8, MP2=6, MP3=5, MP4=0`
  — MP1-3 nonzero (matching the 3 table entries exactly), MP4 zero (matching the absent 4th
  entry). This side is fully MP-explained on its own.
- Since ZombieDragonT2's nonzero MP2/MP3 don't produce levels 2/3 in the table the way
  StormFang's equivalent nonzero MP does, something *other than MP* is suppressing them — a real
  story-flag gate, matching the user's original description ("Soul Eater spells are locked
  behind certain story flags").

**The actual write-site for `DAT_80179fe8+0x80` was not found on this pass.** The two functions
called from `battle_menu_select_rune_level`'s setup (`FUN_80146dfc`, `FUN_80144620`) are both
generic, widely-reused UI widget helpers (grid-clear and geometry/bounding-box bit-packing
respectively) with no filtering logic — the real gate runs somewhere upstream of both, not
located at this point (see "Open questions" below for the later partial resolution).

**Unite enumeration**: fully mapped this pass. Decoded and cross-checked all 32 entries against
the Suikosource Unites Guide — zero discrepancies, both on decoded names and on every
required-`Id` byte. At the time this table was built, no character-specific filter had been
found anywhere in the resolver — the working assumption was that a character's actual menu only
shows entries where every required `Id` is present (and presumably alive) in the current party,
with that filtering believed to happen in menu/UI code that hadn't been located yet (later
resolved — see "Open questions" below).

## The InitialState snapshot (`lib/BattleSnapshot.lua`) — feeding a pure-code simulator

**ATK/DEF needed real investigation** — they are NOT simply readable pre-confirm:

- For **party members**, staleness was confirmed live by tracing all six party members through
  a real round: every one of them changed value on the very first tick after confirm, in the
  exact same tick the turn-order RNG roll already fired. There is no observable window where
  they're both valid and RNG-untouched. Four of the six happened to look small and plausible
  pre-confirm anyway (coincidence, not correctness — confirmed by comparing against the real
  post-confirm values, which differed for all six, not just the two with obviously-implausible
  numbers).
- Confirmed live that equipped-accessory bonuses can land directly in the final ATK/DEF
  accumulator slots, not just the base PWR/DEF slots: Viktor's two equipped accessories in
  `ZombieDragonStart.State` both bonus DEF directly, +4 and +3, landing his final DEF at
  85 base + 7 = 92.
- For **enemies**, confirmed live (Zombie Dragon: `+0x14`=175, `+0x18`=35, matching its real
  ATK/DEF exactly, stable from frame 50 through frame 3000 pre-confirm) that the pre-confirm
  value is already correct and usable directly, unlike party members.
- A full 2MB RAM scan for the party's known-correct post-confirm ATK/DEF values, both narrowly
  around each character's own persistent Stats struct and broadly across all of memory (looking
  for a consistent per-character stride pairing, the same technique that found the turn-order
  tie-break field in
  [Turn_Order.md](../docs/game_mechanics/Turn_Order.md)), turned up nothing — the correct value
  genuinely doesn't exist anywhere in memory before the round starts for party members. It has
  to be computed, not read. This is what settled on replicating
  `battle_compute_ally_derived_stats` in Lua rather than continuing to search for a readable
  field.

## The TurnResult capture (`BattleRoundInput:runTurn()`) — what a round actually did

Building this surfaced the same class of mistake as the ATK/DEF investigation above — trusting a
memory field's *apparent* meaning without watching it across the actual event it's supposed to
signal:

- The obvious choice for "has this round finished" was the round counter (`+0x4`) incrementing.
  It's wrong: confirmed by tracing a forced-damage round frame-by-frame that the counter moves
  at frame+1 after confirm (the instant the round *starts*), while real HP changes continued for
  900+ more frames as combat actually resolved. Using it as the completion signal, `runTurn()`'s
  first version returned almost instantly, and the demo script (`scripts/CaptureTurnResult.lua`)
  showed zero HP change for every combatant despite the RNG seed genuinely advancing — a strong
  tell that *something* ran, just not what was expected to be waited for.
- The correct signal was already sitting in the codebase: the same Fight/Run/Bribe/Free Will
  prompt used to *start* a round only reappears once every combatant's action has fully
  resolved, so `waitForRoundComplete()` just polls for that (reusing `waitForMenuReady`'s own
  handler/phase check) instead, or for the gamestate leaving `BATTLE` entirely (battle over).
- Re-run after the fix, the same demo produced the expected result: matching a hand-traced
  forced-attack round exactly, including Camille dropping to 0 HP and `Alive: false` -
  cross-validating both the fix and the death detection in one pass.

Outcome detection remains best-effort: `"defeat"` reads `Gamestate.GAME_OVER` directly (a real,
documented enum value), but `"victory"` is only inferred from "gamestate left `BATTLE` without
hitting `GAME_OVER` first" — plausible, but not yet confirmed against a real won battle (no
savestate positioned near a winnable finish was available to test against this pass).

## Open questions / not yet done

- Whether the same "write the cursor field once stably past its phase-1 transient" trick
  generalizes to `battle_menu_select_command`/`battle_menu_select_target` themselves (useful if
  a future need requires exercising the real per-character menus rather than the Free Will
  shortcut) — plausible (their own phase-1 body has no equivalent reset-to-0 seen in the Fight
  prompt's phase-1→2 transition, so it may be even safer there) but not independently tested,
  since Free Will makes it unnecessary for the general case.
- ~~`battle_menu_select_target`'s own decompile, and the four per-command continuation labels~~ —
  **decompiled 2026-09-07** and now in the main doc: `battle_menu_select_target` (`0x800eb628`)
  walks a precomputed valid-target list, checks reachability via the attacker's weapon-type byte,
  and hands off to the shared convergence point `LAB_800ea510`; the 4 continuations (Defend,
  Item, Unite, and Attack's own target-select) are described there. Item's/Unite's own large
  state machines (`0x800ebc08` Item, `0x800ed668` Unite) weren't fully traced past confirming
  they structurally mirror Attack's target-select — sizable, diminishing returns for this pass.
- ~~Whether Rune/Item/Unite overrides (`ActionType` `2`/`3`/`4`) survive the final confirm~~ —
  **confirmed 2026-09-07** and now in the main doc: every command's own confirm step (Rune/Item/
  Unite included) funnels through the same `LAB_800ea510` convergence point Defend/Attack use —
  `get_xrefs_to` on it found 7 total writers, one per command path plus Free Will's own entry
  point — and `ActionType` is written exactly once, in `battle_menu_select_command`'s shared
  pre-switch code, with nothing downstream ever touching it again.
- ~~What Run/Bribe's success case looks like at the memory level~~ — **traced 2026-09-07** and
  now in the main doc. Both handlers (`LAB_800ee124` Run, `LAB_800ee38c` Bribe — neither is a
  Ghidra-bounded function yet) **immediately, unconditionally set every living party member's
  `ActionType` to `1` (Defend)** before anything else — this is the actual code behind the
  "Run/Bribe defaults everyone to Defend" description, now proven rather than inferred. Run then
  calls `FUN_800f8464` (the real escape-roll resolver, not traced further) and shows a
  success/fail message before proceeding; Bribe runs the identical Defend-everyone loop, its own
  gold-cost/roll logic not traced past that shared step (diminishing returns — the requested
  "what does success look like" is answered: same Defend-fallback base behavior as Run).
- Whether a lower-level input-injection point exists for the confirm step itself that isn't
  subject to the once-per-frame race described above (e.g. a raw pad-register write reachable
  at a coarser, hookable granularity) — not explored; `joypad.set()` is the only
  confirmed-working layer for that specific step.
- ~~The menu/UI-side code that filters `DAT_8016d18c`'s 32 Unite entries down to whichever ones
  the current party can actually perform~~ — **found 2026-09-07** and now in the main doc:
  `compute_unite_eligible_slots` (renamed from `FUN_800ef104`, `0x800ef104`, called from
  `battle_menu_compute_command_availability`) walks all 32 entries, checks the actor's own
  roster Id against each entry's required-Id list, and validates the other required Id(s) are
  present and alive in the living party (`check_combatant_valid_target` +
  `wStatusFlags & 0x61 == 0`), writing eligible slots to `DAT_80179fe8+0x80` and the count to
  `+0xa8` — this drives the Unite command slot's enable/disable. `battle_select_unite_attack`'s
  own plate comment was updated to remove the stale "not located" note. No new `+0x16`
  target-type bits found beyond the already-documented `1`/`2`/`3`.
- The real write-site for `DAT_80179fe8+0x80` (the story-flag-gated selectable-Rune-levels
  table) — **partially resolved 2026-09-07**: found the immediate writer,
  `compute_selectable_rune_levels` (renamed from `FUN_800ef67c`, `0x800ef67c`, also called from
  `battle_menu_compute_command_availability`), which reads `Rune.Id`, walks
  `DAT_8016a0e0[rune_id]`'s ability-set record levels 4→1 requiring both a nonzero per-level
  spell-id byte AND nonzero MP for that tier, writing eligible levels to
  `DAT_80179fe8 + level*4 + 0x7c` (level `1` lands exactly at `+0x80`, confirming this table).
  **But this alone doesn't explain the story-flag gate** — no explicit story-flag check exists in
  this function, only the static spell-id-byte + MP checks, which doesn't reconcile with the live
  A/B evidence (`ZombieDragonT2.State` vs `StormFang.State`) on its own. Leading unconfirmed
  hypothesis: something upstream dynamically zeroes the disallowed levels' own spell-id bytes
  directly in `DAT_8016a0e0[26]`'s (Soul Eater's) record before battle starts, making this check
  reject them "for free" — but no writer to `DAT_8016a0e0` was found (`get_xrefs_to` shows only
  unrelated non-battle UI readers in `0x800c9xxx`-`0x800d9xxx`). Genuinely open, not forced.
