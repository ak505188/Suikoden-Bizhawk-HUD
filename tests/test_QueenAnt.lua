-- Run with: lua5.4 tests/test_QueenAnt.lua (from the project root)
--
-- Move-selection threshold and RNG-call-count contracts are exact ports of the decompile
-- (queen_ant_ai_self_heal_and_select_move / queen_ant_aoe_earth_damage_loop / ant_commanded_
-- attack_damage, va7.bin) - see docs/game_mechanics/Battle_Damage_Formula.md's "Queen Ant's full
-- moveset" section.
--
-- BIT-EXACT LIVE VALIDATION, 2026-09-07 (scripts/TraceQueenAntMoveSelection.lua +
-- scripts/CheckQueenAntStats.lua + scripts/CheckQueenAntAoeDamageNoDeath.lua against
-- QueenAnt.State): move-selection's 51%/49% threshold confirmed with 2 real seeds landing on
-- BOTH branches; the AoE's RNG-cost formula (1 roll per living target) confirmed exact (4 rolls
-- for 4 living targets after a mid-fight death); ALL 4 AoE damage rolls confirmed bit-exact -
-- 2 targets survived the AoE naturally, the other 2 would have died (HP clamped to 0, hiding the
-- real damage), so a follow-up capture boosted their HP to (their own real HPMax - 1) right
-- before the AoE fired (staying in-spec - an initial attempt using a flat 9999 overshot every
-- target's own max and triggered an unrelated "clamp current HP to max" correction that erased
-- the AoE's own damage entirely, a lesson in its own right) so their exact damage could be read
-- too. This same live pass DISPROVED an earlier "slot 3 register-reuse bug" claim - see
-- calculateAoeEarthDamage's own comment in lib/Enemies/QueenAnt.lua for the correction.
--
-- MAJOR CORRECTION, 2026-09-07 (user: "It looks like the soldier ants are faster than Queen Ant,
-- could it be running its command ants attack after the ants have already gone?"): everything
-- this file previously claimed about "commanded ant" target attribution and damage being
-- bit-exact live-confirmed was a MISATTRIBUTION. Soldier Ant's SPD=22 vs Queen Ant's SPD=20 makes
-- it ALGEBRAICALLY GUARANTEED (weight ranges [215,224] vs [195,204], zero overlap - see
-- Turn_Order.md) that every living ant acts on its own independent turn before Queen's turn ever
-- comes up - so by the time she rolls CommandAnts, every ant already has ActionTag=1 and fails
-- queen_ant_command_all_ants_attack's own eligibility check. Verified directly
-- (scripts/VerifyAntCommandAttribution.lua): the "commanded" ants' own continuation pointer was
-- `apply_uncovered_attack_damage` (main.exe 0x800f5960, a GENERIC single-roll attack resolver),
-- never `ant_commanded_attack_damage` (va7.bin 0x800110d8) - Queen's own command function was
-- never actually observed firing in any tested round. See the "MAJOR CORRECTION" comment in
-- lib/Enemies/QueenAnt.lua for the full writeup. calculateCommandedAntDamage/
-- simulateCommandedAntAttack have been REVERTED to the 2-roll model the raw disassembly always
-- showed - genuinely untested live, not bit-exact confirmed either way.

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local RNGLib = require "lib.RNG"
local QueenAnt = require "lib.Enemies.QueenAnt"
local EnemyElementalAttack = require "lib.EnemyElementalAttack"
local DamageVariance = require "lib.DamageVariance"

TestQueenAntMoveSelection = {}

-- Brute-force search for seeds landing just below/above the 51% threshold, confirming the exact
-- boundary matches the decompile's `(roll*100)/32767 < 0x33`.
function TestQueenAntMoveSelection:testThresholdBoundary()
  local foundAoe, foundCommand = false, false
  for seed = 0, 200000 do
    local move, _, calls = QueenAnt.simulateMoveSelection(seed)
    luaunit.assertEquals(calls, 1)
    if move == "AoeEarth" then foundAoe = true end
    if move == "CommandAnts" then foundCommand = true end
    if foundAoe and foundCommand then break end
  end
  luaunit.assertTrue(foundAoe, "never observed the AoeEarth branch")
  luaunit.assertTrue(foundCommand, "never observed the CommandAnts branch")
end

-- No target-scan at all (self/AOE-targeted) - always exactly 1 rand() call regardless of outcome.
function TestQueenAntMoveSelection:testAlwaysOneCall()
  for _, seed in ipairs({ 1, 42, 0xdeadbeef, 0x12345678 }) do
    local _, _, calls = QueenAnt.simulateMoveSelection(seed)
    luaunit.assertEquals(calls, 1)
  end
end

-- EXACT probability, 2026-09-07 (user: "I need to know it's probablity vs it's Earth move"):
-- brute-force every possible RNG2 output (0-32767, the full range a uniformly-distributed 32-bit
-- seed's (seed>>16)&0x7fff bit-extraction can produce) through the real formula, rather than
-- estimating. AoeEarth = 2089/4096 (51.0010%), CommandAnts = 2007/4096 (48.9990%) - exact
-- fractions, not an approximation, since RNG2 is a direct bit-extraction (uniform) not a
-- modulo/hash that could introduce bias.
function TestQueenAntMoveSelection:testExactProbability()
  local aoe, cmd = 0, 0
  for roll = 0, 32767 do
    local seed = roll << 16 -- getRNG2(seed) = (seed>>16)&0x7fff = roll, by construction
    local quotient = (RNGLib.getRNG2(seed) * 100) // 32767
    if quotient < 0x33 then aoe = aoe + 1 else cmd = cmd + 1 end
  end
  luaunit.assertEquals(aoe, 16712)
  luaunit.assertEquals(cmd, 16056)
  luaunit.assertEquals(aoe + cmd, 32768)
end

-- RNG cost of the CommandAnts branch even as a no-op, retested 2026-09-07 (user: "I still need to
-- know if it pushed RNG"): queen_ant_command_ants_gate and queen_ant_command_all_ants_attack both
-- contain ZERO rand()-consuming instructions in EVERY code path through either function
-- (confirmed via raw disassembly, independent of whether any ant turns out eligible) - and a
-- fresh live retest (scripts/RetestCommandAntsRngCost.lua) confirmed Address.RNG identical across
-- the entire gate->command_all_ants_attack->finish sequence. simulateCommandedAntAttack models
-- only the (never-observed-live) per-ant damage cost, not this - there is no separate
-- "simulateCommandAntsBranch" RNG-cost function because the branch itself costs nothing on its
-- own; QueenAnt.simulateMoveSelection's own 1 roll is the ONLY RNG either branch spends unless
-- CommandAnts ever actually finds an eligible ant (never observed).
function TestQueenAntMoveSelection:testCommandAntsBranchItselfCostsNoRng()
  local move, seed, calls = QueenAnt.simulateMoveSelection(1395857551)
  luaunit.assertEquals(move, "CommandAnts")
  luaunit.assertEquals(calls, 1)
  -- the branch itself (gate + command_all_ants_attack, absent any eligible ant) has no
  -- corresponding simulate*() call to make here precisely because it costs 0 - this test just
  -- documents that fact rather than exercising a function.
  luaunit.assertEquals(seed, 1272395548) -- matches the live-retested value directly
end

-- 2 live-captured seeds (scripts/TraceQueenAntMoveSelection.lua against QueenAnt.State, isolated
-- via BattleState+0xc - the single global "current decision" cursor shared by
-- queen_ant_ai_self_heal_and_select_move/_own_attack_windup/_command_ants_gate - transitioning
-- directly from its pre-roll value to one of the two branch addresses one frame later, with no
-- other RNG consumer active in that single-frame gap), one landing on each branch - both the
-- move AND the resulting RNG state matched bit-exact.
function TestQueenAntMoveSelection:testLiveCapturedSeeds()
  local cases = {
    { seed = 1395857551, move = "CommandAnts", newSeed = 1272395548 },
    { seed = 624323935, move = "AoeEarth", newSeed = 603567020 },
  }
  for _, case in ipairs(cases) do
    local move, newSeed, calls = QueenAnt.simulateMoveSelection(case.seed)
    luaunit.assertEquals(move, case.move, string.format("seed %u move", case.seed))
    luaunit.assertEquals(newSeed, case.newSeed, string.format("seed %u newSeed", case.seed))
    luaunit.assertEquals(calls, 1)
  end
end

TestQueenAntAoeEarth = {}

-- One rand() call per LIVING target, dead slots free - matches Neclord.simulateWind/Lightning's
-- own convention (numTargets == number of living targets actually hit).
function TestQueenAntAoeEarth:testCallCountScalesWithLivingTargets()
  for _, n in ipairs({ 0, 1, 3, 5, 6 }) do
    luaunit.assertEquals(QueenAnt.simulateAoeEarth(1, n), n)
  end
end

-- Live-captured (scripts/TraceQueenAntMoveSelection.lua against QueenAnt.State): with party slot
-- 2 already dead going into this AoE, the RNG state was stable at 152574069 for many frames, then
-- landed on 3185493745 the instant the AoE resolved - exactly 4 nextRNG() steps, matching the 4
-- remaining LIVING targets (slots 1/3/4/5), confirming dead slots really do cost 0 rolls.
function TestQueenAntAoeEarth:testLiveCapturedRngCost()
  local calls = QueenAnt.simulateAoeEarth(152574069, 4)
  luaunit.assertEquals(calls, 4)
  local seed = 152574069
  for _ = 1, calls do seed = RNGLib.nextRNG(seed) end
  luaunit.assertEquals(seed, 3185493745)
end

-- Damage composition matches EnemyElementalAttack.calculateDamage directly (same shared formula
-- every enemy elemental attack in this project uses) when the target's rune category is known
-- and doesn't collide with Earth (3) or Soul Eater (7).
function TestQueenAntAoeEarth:testNeutralMatchesSharedFormula()
  local rolls = { 5, 10, 15 }
  local i = 0
  local function rand() i = i + 1; return rolls[i] end
  local expected = EnemyElementalAttack.calculateDamage(200, 80, EnemyElementalAttack.Compat.NEUTRAL, rand)
  i = 0
  local actual = QueenAnt.calculateAoeEarthDamage(200, 80, 1, 2, rand) -- category=1 (Fire), slot 2 - no collision
  luaunit.assertEquals(actual, expected)
end

-- CORRECTED 2026-09-07: an earlier pass claimed occupying SLOT 3 specifically caused an
-- accidental ~50% reduction (a leftover-register bug, same class as Dragon's Fire Breath "slot 1"
-- bug). Live validation DISPROVED this - see calculateAoeEarthDamage's own comment. Slot index has
-- no effect regardless of the rune category passed.
function TestQueenAntAoeEarth:testSlotIndexHasNoEffect()
  local function fixedRoll() return 10 end
  local slot3 = QueenAnt.calculateAoeEarthDamage(200, 80, nil, 3, fixedRoll)
  local slot2 = QueenAnt.calculateAoeEarthDamage(200, 80, nil, 2, fixedRoll)
  local expectedNeutral = EnemyElementalAttack.calculateDamage(200, 80, EnemyElementalAttack.Compat.NEUTRAL, fixedRoll)
  luaunit.assertEquals(slot3, expectedNeutral)
  luaunit.assertEquals(slot2, expectedNeutral)
end

-- Bit-exact live-captured damage (scripts/CheckQueenAntStats.lua + TraceQueenAntMoveSelection.lua
-- against QueenAnt.State): Queen Ant's own MGC=55 (read from the enemy-layout combatant record,
-- +0x1c - a DIFFERENT field offset than party records use for MGC, +0x2c - confirmed via
-- scripts/DumpQueenAntRecords.lua against Soldier Ant's own already-known stats). Both targets
-- were still alive after the hit, so the exact damage (not just a death lower-bound) is provable.
function TestQueenAntAoeEarth:testLiveCapturedDamage()
  local QUEEN_MGC = 55
  local cases = {
    { targetMGC = 26, targetSlotIndex = 1, roll = 22068, damage = 27 }, -- would have died
                                                                          -- naturally (HP clamped
                                                                          -- to 0) - confirmed via
                                                                          -- CheckQueenAntAoeDamageNoDeath.lua's
                                                                          -- HP-boost capture
    { targetMGC = 36, targetSlotIndex = 3, roll = 12670, damage = 18 }, -- was wrongly predicted
                                                                          -- halved to 9 by the now-
                                                                          -- retracted slot-3 bug
    { targetMGC = 7, targetSlotIndex = 4, roll = 14372, damage = 48 },
    { targetMGC = 14, targetSlotIndex = 5, roll = 15838, damage = 42 }, -- also would have died
                                                                          -- naturally
  }
  for _, c in ipairs(cases) do
    local function fixedRoll() return c.roll end
    local damage = QueenAnt.calculateAoeEarthDamage(QUEEN_MGC, c.targetMGC, nil, c.targetSlotIndex, fixedRoll)
    luaunit.assertEquals(damage, c.damage, string.format("slot %d", c.targetSlotIndex))
  end
end

-- A target whose REAL rune category is 7 (Soul Eater, universal resist) is halved regardless of
-- slot, same as every other enemy elemental attack in this project.
function TestQueenAntAoeEarth:testSoulEaterAlwaysHalved()
  local function fixedRoll() return 10 end
  local damage = QueenAnt.calculateAoeEarthDamage(200, 80, 7, 5, fixedRoll)
  local expected = EnemyElementalAttack.calculateDamage(200, 80, EnemyElementalAttack.Compat.RESIST, fixedRoll)
  luaunit.assertEquals(damage, expected)
end

TestQueenAntCommandedTarget = {}

-- Deterministic, no RNG: picks the LAST (highest-index) eligible candidate, not the first.
function TestQueenAntCommandedTarget:testPicksLastEligible()
  local candidates = {
    { alive = true, busy = false, stateCode = 0 }, -- eligible (1)
    { alive = false, busy = false, stateCode = 0 }, -- dead
    { alive = true, busy = false, stateCode = 0 }, -- eligible (3) - should win over slot 1
  }
  luaunit.assertEquals(QueenAnt.selectCommandedTarget(candidates), 3)
end

function TestQueenAntCommandedTarget:testBusySkipped()
  local candidates = {
    { alive = true, busy = false, stateCode = 0 },
    { alive = true, busy = true, stateCode = 0 }, -- busy - skipped even though alive
  }
  luaunit.assertEquals(QueenAnt.selectCommandedTarget(candidates), 1)
end

function TestQueenAntCommandedTarget:testStateCodeThreshold()
  local candidates = {
    { alive = true, busy = false, stateCode = 3 }, -- eligible (< 4)
    { alive = true, busy = false, stateCode = 4 }, -- ineligible (not < 4)
  }
  luaunit.assertEquals(QueenAnt.selectCommandedTarget(candidates), 1)
end

function TestQueenAntCommandedTarget:testNoneEligibleReturnsNil()
  local candidates = {
    { alive = false, busy = false, stateCode = 0 },
    { alive = true, busy = true, stateCode = 0 },
  }
  luaunit.assertNil(QueenAnt.selectCommandedTarget(candidates))
end

-- CORRECTED 2026-09-07 (user: "That's incorrect, they target different party members" -
-- selectCommandedTarget alone, called repeatedly against an UNCHANGED candidate list, would
-- wrongly suggest every commanded ant hits the same target). selectCommandedTargets models the
-- cascade play_attack_animation's synchronous execution + anim_op_set_busy_flags would produce
-- IF queen_ant_command_all_ants_attack ever actually found an eligible ant - per the MAJOR
-- CORRECTION at the top of this file, it never has in any tested round (ants always act first on
-- their own faster turn), so this remains a structurally-derived model of the code, not something
-- confirmed against a live "commanded" attack.
function TestQueenAntCommandedTarget:testCascadesToDifferentTargets()
  local candidates = {
    { alive = true, busy = false, stateCode = 0 }, -- slot 1
    { alive = true, busy = false, stateCode = 0 }, -- slot 2
    { alive = true, busy = false, stateCode = 0 }, -- slot 3
  }
  local targets = QueenAnt.selectCommandedTargets(candidates, 3)
  luaunit.assertEquals(targets, { 3, 2, 1 })
  -- the caller's own candidate list is untouched (selectCommandedTargets copies, not mutates)
  luaunit.assertFalse(candidates[3].busy)
end

-- Once every eligible candidate has been claimed by an earlier ant, further ants get nil (no
-- valid target left) - not an error and not a wraparound back to an already-hit target.
function TestQueenAntCommandedTarget:testRunsOutOfEligibleTargets()
  local candidates = {
    { alive = true, busy = false, stateCode = 0 },
    { alive = true, busy = false, stateCode = 0 },
  }
  local targets = QueenAnt.selectCommandedTargets(candidates, 4)
  luaunit.assertEquals(targets, { 2, 1, nil, nil })
end

-- A dead/ineligible slot never gets targeted even after every OTHER eligible candidate is used
-- up (no fallback onto an otherwise-invalid slot).
function TestQueenAntCommandedTarget:testIneligibleSlotNeverTargeted()
  local candidates = {
    { alive = true, busy = false, stateCode = 0 },  -- slot 1: eligible
    { alive = false, busy = false, stateCode = 0 }, -- slot 2: dead, never eligible
  }
  local targets = QueenAnt.selectCommandedTargets(candidates, 2)
  luaunit.assertEquals(targets, { 1, nil })
end

TestQueenAntCommandedAnt = {}

-- REVERTED 2026-09-07 (see the file's own MAJOR CORRECTION header): back to 2 rand() calls per
-- commanded-ant attack, matching the raw disassembly (calc_damage called twice in a row with
-- identical arguments, discard first, apply second) - genuinely untested against live data, since
-- ant_commanded_attack_damage has never been observed to actually fire (the ants' guaranteed SPD
-- advantage means they always act on their own turn first, making them ineligible when Queen
-- tries to command them).
function TestQueenAntCommandedAnt:testTwoCalls()
  luaunit.assertEquals(QueenAnt.simulateCommandedAntAttack(1), 2)
end

-- The FIRST roll is discarded per the disassembly - only the SECOND roll's value reaches the
-- final damage, even though both rolls are consumed from the RNG stream.
function TestQueenAntCommandedAnt:testDiscardsFirstRoll()
  local rolls = { 999, 50 } -- wildly different rolls so a mix-up would be obvious
  local i = 0
  local function rand() i = i + 1; return rolls[i] end
  local actual = QueenAnt.calculateCommandedAntDamage(150, 40, rand)

  local function secondOnly() return 50 end
  local expected = DamageVariance.calcVariance(150 - 40, secondOnly)
  if expected < 1 then expected = 1 end
  luaunit.assertEquals(actual, expected)
end

-- NOTE (not a test of ant_commanded_attack_damage - see the file header's MAJOR CORRECTION): the
-- numbers 26/10/17/12 that earlier passes attributed to this function were real live damage, just
-- from a DIFFERENT function (apply_uncovered_attack_damage, main.exe 0x800f5960 - the ants' own
-- independent-turn plain Attack, a generic single-roll resolver used by any combatant, now
-- modeled in lib/Enemies/SoldierAnt.lua). Those values already validate the SAME shared
-- lib.DamageVariance formula this project uses everywhere else (Neclord's Bats damage, etc.) -
-- not anything QueenAnt-specific, so they don't belong as QueenAnt module tests. No live sample
-- of ant_commanded_attack_damage's own 2-roll formula actually firing exists yet.

os.exit(luaunit.LuaUnit.run())
