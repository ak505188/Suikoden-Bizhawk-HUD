-- Queen Ant (Mt. Seifu's scripted boss fight, va7.bin - AI at 0x80010ae0, lvl15 HP7000; a
-- genuinely different encounter from Seek Valley's random-encounter Queen Ant in vf2.bin, see
-- Monster_AI_Static_Catalog.md). Seed-exact simulated here, following the same rand()-call-
-- counting convention as lib/Magic.lua's simulate<Spell> functions and the sibling
-- lib/Enemies/*.lua modules. See docs/game_mechanics/Battle_Damage_Formula.md's "Queen Ant's
-- full moveset and the 3 accompanying ants" section and queen_ant_ai_self_heal_and_select_move /
-- queen_ant_aoe_earth_cast / queen_ant_aoe_earth_damage_loop / ant_commanded_attack_damage's own
-- Ghidra plate comments (va7.bin) for the full derivation.
--
-- Genuinely different shape from Dragon/Zombie Dragon/Neclord: no target-scan at all (Queen
-- Ant's own move is self/AOE-targeted), and her own HP is reset to max every turn unconditionally
-- (not modeled here - it's deterministic, costs no RNG, and doesn't affect anything this module
-- computes).

local RNGLib = require "lib.RNG"
local EnemyElementalAttack = require "lib.EnemyElementalAttack" -- AoE Earth (genuinely elemental)
local DamageVariance = require "lib.DamageVariance" -- commanded-ant damage (purely physical)

local QueenAnt = {}

-- Move-selection: ONE roll, no target-scan (queen_ant_ai_self_heal_and_select_move, 0x80010ae0).
-- (roll*100)/32767 < 0x33 -> her own AoeEarth attack; else -> CommandAnts (gated on an
-- unidentified enemy_data+0x90 bit 0x2 precondition and a counter this module doesn't model - see
-- the Ghidra plate comment - so CommandAnts here just means "the roll landed on that branch," not
-- that it does anything - see the MAJOR CORRECTION below: it's an empirically-dead branch).
--
-- EXACT PROBABILITY (brute-forced over the full RNG2 output range 0-32767, 2026-09-07, user:
-- "I need to know it's probablity vs it's Earth move"): AoeEarth = 16712/32768 = 2089/4096 =
-- 51.0010%; CommandAnts = 16056/32768 = 2007/4096 = 48.9990%. (RNG2 = (seed>>16)&0x7fff is a
-- direct bit-extraction from a uniformly-distributed 32-bit seed, so these counts ARE the exact
-- real-gameplay probabilities, not an approximation - "~51%/~49%" elsewhere in this project's
-- docs is a rounding of these same exact fractions.)
--
-- RNG COST OF THE DEAD BRANCH, retested 2026-09-07 (user: "I still need to know if it pushed
-- RNG"): CONFIRMED, both via decompile (queen_ant_command_ants_gate and
-- queen_ant_command_all_ants_attack both contain ZERO rand()-consuming instructions, in every
-- code path through either function, independent of whether any ant turns out to be eligible) and
-- via a fresh live retest (scripts/RetestCommandAntsRngCost.lua against QueenAnt.State):
-- Address.RNG read IDENTICAL (1272395548) at the exact frame each of
-- queen_ant_command_ants_gate / queen_ant_command_all_ants_attack / queen_ant_own_attack_finish
-- fired in sequence. The CommandAnts branch costs ZERO RNG beyond the single shared
-- move-selection roll below (the same 1 roll AoeEarth also costs) - it doesn't matter that it's a
-- no-op in practice, it was already a no-op for RNG purposes even on paper.
local MOVE_THRESHOLD = 0x33

-- simulateMoveSelection(startSeed) -> move, seed, calls
--   move: "AoeEarth" or "CommandAnts"
--   seed: the RNG state after this resolves - the startSeed to hand to simulateAoeEarth (AoeEarth)
--     or simulateCommandedAntAttack (CommandAnts, once its own gate/counter releases)
--   calls: total rand() calls consumed by this step alone (always 1 - no target-scan)
function QueenAnt.simulateMoveSelection(startSeed)
  local seed = RNGLib.nextRNG(startSeed)
  local roll = RNGLib.getRNG2(seed)
  local quotient = (roll * 100) // 32767
  local move = quotient < MOVE_THRESHOLD and "AoeEarth" or "CommandAnts"
  return move, seed, 1
end

-- AoeEarth: THE attack the user caught live 2026-09-07 ("she has an AoE magic that hits all
-- characters, looks similar to a Voice of Earth spell") after an earlier static-only pass wrongly
-- concluded this branch was visual-only - see queen_ant_aoe_earth_damage_loop's own plate comment
-- for the full story. Loops every living party member in formation-slot order (dead slots are
-- skipped and cost 0 rand() calls - the skip check happens before the roll, not after), calling
-- the shared calc_rune_element_attack_damage (main.exe 0x800f8174, RngCallbackTable slot 86) once
-- per living target: attacker=Queen Ant, element=3 (Earth/Mother Earth -
-- EnemyElementalAttack.RUNE_CATEGORY category 3), target=that slot's own MGC/DEF/RuneId.
--
-- Live-confirmed via scripts/CaptureQueenAntRounds.lua against QueenAnt.State: one round showed
-- all 5 living party members taking independent, differing damage simultaneously - the "hits all
-- characters" signature. RNG-cost formula (one roll per living target) bit-exact live-validated
-- 2026-09-07 via scripts/TraceQueenAntMoveSelection.lua: with party slot 2 already dead, exactly
-- 4 nextRNG() steps (matching the 4 remaining living slots 1/3/4/5) landed on the exact
-- live-observed post-AoE RNG value.
--
-- simulateAoeEarth(startSeed, numLivingTargets) -> totalRandCalls (one roll per LIVING target -
-- dead slots are free)
function QueenAnt.simulateAoeEarth(startSeed, numLivingTargets)
  local seed = startSeed
  local calls = 0
  for _ = 1, numLivingTargets do
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
  end
  return calls
end

local EARTH_ELEMENT = 3

-- calculateAoeEarthDamage(attackerMGC, targetMGC, targetRuneCategory, targetSlotIndex, rand)
--   -> damage
-- targetRuneCategory: from EnemyElementalAttack.RUNE_CATEGORY[targetRuneId], or nil if the
--   target's rune isn't one of the explicit cases.
-- targetSlotIndex: the target's 1-based party formation slot (1-6) - kept for future
--   investigation, currently UNUSED (see correction below).
--
-- CORRECTED 2026-09-07 (live simulation caught this, unprompted by the user this time): an
-- earlier pass claimed a "slot 3 register-reuse bug" here (same class as Dragon's Fire Breath
-- "slot 1" bug), based on a static disassembly note from an EARLIER session identifying `$s0`
-- (the loop's own live slot-index register) as the register calc_rune_element_attack_damage's
-- compiled switch falls through to when a target's real Rune.Id isn't explicitly handled. Bit-exact
-- live validation (scripts/CheckQueenAntStats.lua + TraceQueenAntMoveSelection.lua's captured AoE
-- roll sequence) CONTRADICTS this: party slot 3 (MGC=36, targetSlotIndex==3) took exactly 18
-- damage, matching the PLAIN NEUTRAL formula exactly - the "halved" prediction (9) does not match.
-- Slot 4 (MGC=7) also matched the plain neutral formula exactly (48). So the bug, AS PREVIOUSLY
-- DESCRIBED, does not fire here. Rather than keep applying a falsified rule, this function no
-- longer auto-substitutes a category for unmapped runes - `targetSlotIndex` is accepted (in case
-- a real trigger condition is found later) but currently has NO EFFECT. Whether some OTHER
-- register/condition still causes an occasional halving remains an open question - not something
-- this one clean counterexample can fully rule out, just something it disproves as a blanket
-- "slot 3 always halves" rule.
function QueenAnt.calculateAoeEarthDamage(attackerMGC, targetMGC, targetRuneCategory, targetSlotIndex, rand)
  local halved = targetRuneCategory == EARTH_ELEMENT or targetRuneCategory == 7
  return EnemyElementalAttack.calculateDamage(attackerMGC, targetMGC,
    halved and EnemyElementalAttack.Compat.RESIST or EnemyElementalAttack.Compat.NEUTRAL, rand)
end

-- CommandAnts: Queen Ant doesn't attack herself here - she commands every other living, idle
-- enemy (the accompanying ants) to attack the party in one go (queen_ant_command_all_ants_attack,
-- 0x80010edc).
--
-- MAJOR CORRECTION 2026-09-07 (user: "It looks like the soldier ants are faster than Queen Ant,
-- could it be running its command ants attack after the ants have already gone?"). This exposed a
-- serious misattribution running through TWO prior "corrections" below (kept, struck through in
-- spirit, for the history). The user was exactly right, and the reality is more absolute than
-- "sometimes": turn order (Turn_Order.md) picks the next actor each tick as
-- `weight = SPD*10 - 5 + rand()%10` among everyone who hasn't yet acted (`ActionTag==0`), highest
-- wins. Soldier Ant's SPD=22 gives weight range [215,224]; Queen Ant's SPD=20 gives [195,204] -
-- ranges that NEVER overlap. So EVERY living ant is GUARANTEED to act (via its own independent
-- soldier_ant_ai_select_target_and_move turn) before Queen Ant's own turn ever comes up, with zero
-- chance for jitter to change that. By the time her turn starts, every ant that's still alive
-- already has ActionTag=1 - failing queen_ant_command_all_ants_attack's own eligibility check
-- (`ActionTag==0`) for every one of them. Live-verified directly
-- (scripts/VerifyAntCommandAttribution.lua against QueenAnt.State's round 1): all 3 ants showed
-- ActionTag=1 at the exact frame `queen_ant_command_all_ants_attack` executed, and each ant's own
-- `combatant_rec+0x50` continuation pointer was `apply_uncovered_attack_damage`
-- (`main.exe 0x800f5960` - a GENERIC single-calc_damage-roll physical attack resolver used by
-- ANY combatant's ordinary Attack, nothing Queen-specific), never
-- `ant_commanded_attack_damage` (`va7.bin 0x800110d8`). **The "commanded ant" target attribution
-- and damage formula "corrected" below were actually observations of the ants' own INDEPENDENT
-- turns (which naturally always fire first) - `ant_commanded_attack_damage` was never actually
-- triggered in any tested round.** In every case tested, Queen's ~49% CommandAnts roll finds zero
-- eligible ants and does nothing observable (she still resets her own HP to max regardless of
-- which branch fires, so it's not entirely inert, but the "command the ants" flavor text has no
-- teeth given these stats).
--
-- What follows is preserved as an accurate model of queen_ant_command_all_ants_attack's own CODE
-- (still correct as a reading of what the function would do if it ever found an eligible ant -
-- e.g. a hypothetical fight variant with slower ants, or an edge case like a mid-round respawn
-- this project hasn't tested), but it should be treated as STRUCTURALLY-DERIVED AND UNCONFIRMED
-- LIVE, not bit-exact validated - every "confirmation" of it to date was actually watching a
-- different function.
--
-- First correction history (user: "how does commandAntAttack determine which ant, and which
-- target?"): an earlier pass wrongly assumed this used the same random target-scan-with-retry
-- formula as Dragon/ZombieDragon/Neclord/Soldier Ant's own independent turn AI - confirmed via raw
-- disassembly that queen_ant_command_all_ants_attack contains ZERO rand() calls, it's fully
-- deterministic (see selectCommandedTarget below) - this part of the reading is still accurate.
--
-- Second correction history (user: "That's incorrect, they target different party members"):
-- corrected the first pass's "concentrated fire" conclusion using the confirmed
-- anim_op_set_busy_flags mechanism (play_attack_animation runs synchronously, marking the target
-- busy, cascading to the next-highest eligible target for the next ant) - see selectCommandedTargets
-- below, which models this cascade. This mechanism is real IN THE CODE, but (per the correction
-- above) was never actually observed firing - the "different targets" pattern that seemed to
-- confirm it live was really 3 separate ants' own independent, randomly-scanned target choices.
--
-- selectCommandedTarget(candidates) -> targetIndex or nil
-- candidates: 1-indexed array of {alive = bool, busy = bool, stateCode = number} for every party
--   member (alive: combatant_rec+0x45==0; busy: the shared per-combatant AI-struct+0x5==0, the
--   SAME struct/field used to gate which ants are eligible to be commanded in the first place,
--   AND the field the ordinary Attack script's busy-flag opcode sets on its target; stateCode:
--   combatant_rec+0x44, an unidentified numeric status - must be <4 to be eligible).
-- Walks every candidate with no early exit, unconditionally overwriting the result on each match
-- - so the result is always the LAST (highest-index) eligible candidate in THIS candidate list,
-- not the first and not random. Does not mutate `candidates` - see selectCommandedTargets for the
-- full multi-ant cascade that does.
function QueenAnt.selectCommandedTarget(candidates)
  local target = nil
  for i, c in ipairs(candidates) do
    if c.alive and (not c.busy) and c.stateCode < 4 then
      target = i
    end
  end
  return target
end

-- selectCommandedTargets(candidates, numAnts) -> array of numAnts target indices (or nil entries
-- once no eligible candidate remains)
-- Models the full command-ants pass: ants are processed one at a time (matching
-- queen_ant_command_all_ants_attack's own ascending enemy-slot loop order), each one calling
-- selectCommandedTarget against the CURRENT candidate state, then - matching the confirmed
-- anim_op_set_busy_flags side effect of running that ant's attack script synchronously - marking
-- its own chosen target `busy = true` before the next ant's scan runs. `candidates` is copied,
-- not mutated in place, so the caller's own table survives unchanged.
function QueenAnt.selectCommandedTargets(candidates, numAnts)
  local working = {}
  for i, c in ipairs(candidates) do
    working[i] = { alive = c.alive, busy = c.busy, stateCode = c.stateCode }
  end
  local targets = {}
  for n = 1, numAnts do
    local target = QueenAnt.selectCommandedTarget(working)
    targets[n] = target
    if target then working[target].busy = true end
  end
  return targets
end

-- simulateCommandedAntAttack(startSeed) -> totalRandCalls
-- REVERTED to the 2-roll model 2026-09-07 (see MAJOR CORRECTION above): an intermediate pass
-- claimed this was 1 roll based on a live RNG trace, but that trace was measuring
-- apply_uncovered_attack_damage (a different, generic function) by mistake - Queen's own
-- ant_commanded_attack_damage was never actually observed firing in any tested round, since the
-- ants always act on their own faster turn first. Restored to match the raw disassembly, which
-- unambiguously shows calc_damage called twice with identical arguments, discarding the first
-- result and applying only the second - genuinely UNTESTED against live data (no capture exists
-- of this function actually executing), not bit-exact confirmed either way.
function QueenAnt.simulateCommandedAntAttack(startSeed)
  local seed = RNGLib.nextRNG(startSeed)
  seed = RNGLib.nextRNG(seed)
  return 2
end

-- calculateCommandedAntDamage(attackerATK, targetDEF, rand) -> damage
-- attackerATK/targetDEF: the COMMANDED ANT's own ATK and its target's DEF (not Queen Ant's own
-- stats - she doesn't deal this damage, she just triggers it). Physical, no elemental scaling at
-- all - reuses lib.DamageVariance's shared variance primitive, calling rand() twice and keeping
-- only the second draw - matching the raw disassembly's "discard first, apply second" shape.
-- REVERTED to this 2-roll model 2026-09-07 (see MAJOR CORRECTION above) - structurally accurate,
-- but genuinely untested live (ant_commanded_attack_damage has never been observed to actually
-- fire, since the ants' guaranteed SPD advantage means they always act on their own turn first,
-- leaving them ineligible when Queen tries to command them).
function QueenAnt.calculateCommandedAntDamage(attackerATK, targetDEF, rand)
  local base = attackerATK - targetDEF
  DamageVariance.calcVariance(base, rand) -- discarded
  local damage = DamageVariance.calcVariance(base, rand) -- applied
  if damage < 1 then damage = 1 end
  return damage
end

return QueenAnt
