-- Run with: lua5.4 tests/test_Neclord.lua (from the project root)
--
-- Every expected value here was independently confirmed against a live BizHawk capture
-- (user-supplied savestates: Neclord.State and NeclordBats.State, the same battle position with
-- RNG modified to force the Bats branch instead of the naturally-occurring move), not just
-- derived from the simulator itself - see docs/game_mechanics/Battle_Damage_Formula.md's
-- "Neclord's real Castle fight" section for the full derivation.

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local RNGLib = require "lib.RNG"
local Neclord = require "lib.Enemies.Neclord"

TestNeclordMoveSelection = {}

-- Neclord.State's own native seed - the user initially mislabeled this "before a Wind attack"
-- but corrected it to Lightning once the math (and a live HP-damage-pattern/rune-signature
-- check) disagreed - a good example of trusting the traced formula over an unverified label
-- once both the decompile and independent live evidence agree.
function TestNeclordMoveSelection:testKnownCapturedSeeds()
  local move1 = Neclord.simulateMoveSelection(0x248b2e49, 3)
  luaunit.assertEquals(move1, "Lightning")

  local move2, target2 = Neclord.simulateMoveSelection(0xddb92a9b, 3)
  luaunit.assertEquals(move2, "Bats")
  luaunit.assertEquals(target2, 2) -- 1-indexed candidate 2 = party slot 1, matches the live
                                    -- poison target and damage pattern exactly
end

TestNeclordRngAdvancement = {}

-- Total RNG advancement per move, validated via LCG-step-counting against the live-settled
-- final RNG value (scripts/SettleNeclordBatsRNG.lua) - exact, not approximate.
function TestNeclordRngAdvancement:testLightningTotal()
  local move, _, postSeed, moveCalls = Neclord.simulateMoveSelection(0x248b2e49, 3)
  luaunit.assertEquals(move, "Lightning")
  local total = moveCalls + Neclord.simulateLightning(postSeed)
  luaunit.assertEquals(total, 9)
end

-- Bats: 2 target-scan + 2 move-choice + 60 spawn-position (20 bats x 3 rolls each, a "random
-- point in a sphere" generator) + 20 phase-offset (1 roll each) + 1 damage-variance + 1
-- guaranteed (chance_arg=100) Poison status roll = 86, matching NeclordBats.State's own
-- live-settled total exactly.
function TestNeclordRngAdvancement:testBatsTotal()
  local move, target, postSeed, moveCalls = Neclord.simulateMoveSelection(0xddb92a9b, 3)
  luaunit.assertEquals(move, "Bats")
  luaunit.assertEquals(target, 2)
  local batsCalls = Neclord.simulateBats(postSeed)
  luaunit.assertEquals(batsCalls, 82) -- 60 + 20 + 1 + 1
  luaunit.assertEquals(moveCalls + batsCalls, 86)
end

TestNeclordDamage = {}

local NECLORD_MGC = 275
local NECLORD_ATK = 450
-- Neclord.State/NeclordBats.State's own 6 party members (identical in both - same battle
-- position), read live (scripts/CheckNeclordFullStats.lua).
local TARGET_MGC = { 74, 76, 118, 130, 186, 145 }
local TARGET_DEF = { 127, 149, 112, 115, 65, 124 }

local function rollAfterCalls(startSeed, calls)
  local seed = startSeed
  for _ = 1, calls do seed = RNGLib.nextRNG(seed) end
  return RNGLib.getRNG2(seed)
end

-- Lightning (Neclord.State's own native seed, 0x248b2e49) - all 6 targets, bit-exact. Slots 3
-- and 5 show the same register-reuse "resistance" bug already documented for Zombie Dragon's
-- and Dragon's own Fire Breath (calc_rune_element_attack_damage's plate comment, main.exe
-- 0x800f8174) - neither target's own RuneId (160, 15) maps to any real category, so the halving
-- comes from whatever the caller's own loop-tracking register happened to leave behind, not a
-- genuine elemental resistance.
function TestNeclordDamage:testLightningAllTargets()
  local move, _, postSeed = Neclord.simulateMoveSelection(0x248b2e49, 3)
  luaunit.assertEquals(move, "Lightning")
  local observed = { 192, 192, 157, 78, 85, 65 }
  local halved = { false, false, false, true, false, true } -- slots 3, 5 (0-indexed)
  local seed = postSeed
  for i = 1, 6 do
    seed = RNGLib.nextRNG(seed)
    local roll = RNGLib.getRNG2(seed)
    local category = halved[i] and 4 or nil -- 4 = Lightning's own element, forcing the halving
    local damage = Neclord.calculateLightningDamage(NECLORD_MGC, TARGET_MGC[i], category,
      function() return roll end)
    luaunit.assertEquals(damage, observed[i], string.format("slot %d", i - 1))
  end
end

-- Wind (a seed hand-picked via brute-force search over lib/Enemies/Neclord.lua's own formula to
-- land on the Wind branch from this exact battle position, then live-captured) - all 6 targets,
-- bit-exact. Only slot 3 is halved here (same register-reuse bug, but NOT slot 5 this time -
-- confirming the bug's trigger isn't simply "target index == element", since slot 3 gets hit
-- for BOTH Wind's element=5 and Lightning's element=4 while slot 5 only gets hit for Lightning).
function TestNeclordDamage:testWindAllTargets()
  local move, _, postSeed = Neclord.simulateMoveSelection(2, 3)
  luaunit.assertEquals(move, "Wind")
  local observed = { 196, 218, 166, 74, 95, 137 }
  local halved = { false, false, false, true, false, false } -- slot 3 (0-indexed) only
  local seed = postSeed
  for i = 1, 6 do
    seed = RNGLib.nextRNG(seed)
    local roll = RNGLib.getRNG2(seed)
    local category = halved[i] and 5 or nil -- 5 = Wind's own element, forcing the halving
    local damage = Neclord.calculateWindDamage(NECLORD_MGC, TARGET_MGC[i], category,
      function() return roll end)
    luaunit.assertEquals(damage, observed[i], string.format("slot %d", i - 1))
  end
end

-- Bats (NeclordBats.State's own native seed) - the ordinary calc_damage Defend-halving rule
-- applies here (confirmed live: all 6 party members had ActionType==1/Defend in this
-- savestate), on top of the physical ATK-DEF base - nothing Neclord-specific, just the same
-- universal rule calc_damage always applies.
function TestNeclordDamage:testBatsTarget()
  local move, target, postSeed = Neclord.simulateMoveSelection(0xddb92a9b, 3)
  luaunit.assertEquals(move, "Bats")
  luaunit.assertEquals(target, 2) -- 1-indexed candidate 2 = party slot 1
  local roll = rollAfterCalls(postSeed, 81) -- past the 20 bats x (3 spawn + 1 phase-offset),
                                             -- landing exactly on the damage-variance roll itself
  local rawDamage = Neclord.calculateBatsDamage(NECLORD_ATK, TARGET_DEF[2], function() return roll end)
  local defendHalved = rawDamage // 2 -- C truncating division, both operands positive here
  luaunit.assertEquals(defendHalved, 156)
end

os.exit(luaunit.LuaUnit.run())
