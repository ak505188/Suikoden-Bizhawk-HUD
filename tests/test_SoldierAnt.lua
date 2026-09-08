-- Run with: lua5.4 tests/test_SoldierAnt.lua (from the project root)
--
-- Soldier Ant's own independent per-turn AI (soldier_ant_ai_select_target_and_move, va7.bin
-- 0x800106b0) - separate from, and per Battle_Damage_Formula.md's "Queen Ant's full moveset"
-- section, the ONLY mechanism that actually produces ant attacks in the Mt. Seifu Queen Ant fight
-- (Queen's own "command ants" branch is empirically dead - the ants' guaranteed SPD advantage
-- means they always act first).
--
-- BIT-EXACT LIVE VALIDATION, 2026-09-07 (user: "Did you run sims to confirm our functions are
-- accurate?" -> "I'm talking about the probability for ant attacks, and the damage rolls" -
-- prompted because the ~77%/23% Attack/DoubleStrike split and the DoubleStrike damage formula had
-- only ever been read from the decompile, never live-tested, and no live DoubleStrike instance
-- had been observed at all). scripts/HuntSoldierAntDoubleStrike.lua ran 8 rounds against
-- QueenAnt.State and found 2 real DoubleStrike instances (ant6->party slot 2, ant8->party slot
-- 3) - the first ever captured. Both move-choice rolls independently verified to classify as
-- DoubleStrike under the exact threshold formula. Damage: ant8's target survived naturally (32
-- damage, exact); ant6's target died even after boosting to HPMax-1 (the doubled hit can exceed a
-- target's own real max HP entirely - a first attempt using HPMax-1 wasn't enough, matching the
-- earlier "in-spec test injection" lesson but taken further: this time the FIX was to raise
-- HPMax itself first, not just current HP, so a bigger buffer could be used without creating an
-- invalid current>max state) - scripts/CheckSoldierAntDoubleStrikeDamage.lua re-ran with HPMax
-- boosted to 300 and got a clean 56 damage reading. Both matched
-- SoldierAnt.calculateDoubleStrikeDamage bit-exact. The 4 Attack-branch damage values already
-- captured (2026-09-07, while investigating Queen Ant's "command ants" misattribution) still
-- cross-check exactly against this module's calculateAttackDamage.

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local RNGLib = require "lib.RNG"
local SoldierAnt = require "lib.Enemies.SoldierAnt"

TestSoldierAntMoveSelection = {}

-- Same target-scan-with-retry template as Dragon/ZombieDragon/Neclord.
function TestSoldierAntMoveSelection:testTargetScanAcceptReject()
  -- seed chosen so slot 1 rejects (roll%100<=50) and slot 2 accepts (roll%100>50) - just checks
  -- the mechanism runs the shared template, not a specific seed's real-game meaning.
  local move, target, seed, calls = SoldierAnt.simulateMoveSelection(1, 3)
  luaunit.assertNotNil(target)
  luaunit.assertTrue(calls >= 1)
end

-- EXACT probability (brute-forced over the full RNG2 output range 0-32767, not an estimate - see
-- QueenAnt's own testExactProbability for the same technique applied to her move-selection).
function TestSoldierAntMoveSelection:testExactProbability()
  local attack, ds = 0, 0
  for roll = 0, 32767 do
    local quotient = (roll * 100) // 32767 % 100
    if quotient < 0x4d then attack = attack + 1 else ds = ds + 1 end
  end
  luaunit.assertEquals(attack, 25232) -- 1577/2048 = 77.0020%
  luaunit.assertEquals(ds, 7536)      -- 471/2048  = 22.9980%
  luaunit.assertEquals(attack + ds, 32768)
end

-- The 2 live-captured DoubleStrike move-choice rolls (scripts/HuntSoldierAntDoubleStrike.lua)
-- both correctly classify as DoubleStrike under the exact threshold formula - not just "an attack
-- happened", the actual roll that decided it matches.
function TestSoldierAntMoveSelection:testLiveCapturedDoubleStrikeRollsClassifyCorrectly()
  local cases = { 4124188544, 4260779870 }
  for _, seed in ipairs(cases) do
    local roll = RNGLib.getRNG2(seed)
    local quotient = (roll * 100) // 32767 % 100
    luaunit.assertTrue(quotient >= 0x4d, string.format("seed %u should classify as DoubleStrike", seed))
  end
end

TestSoldierAntDamage = {}

-- Attack branch (~77%): NOT ant-specific - falls back to the generic
-- apply_uncovered_attack_damage/battle_execute_player_attack resolver (main.exe 0x800f5960),
-- confirmed live while investigating Queen Ant's "command ants" misattribution. 4 live-captured
-- values, all bit-exact.
function TestSoldierAntDamage:testLiveCapturedAttackDamage()
  local ATK = 48
  local cases = {
    { def = 21, roll = 6421, damage = 26 },
    { def = 38, roll = 32256, damage = 10 },
    { def = 31, roll = 15186, damage = 17 },
    { def = 36, roll = 22865, damage = 12 },
  }
  for _, c in ipairs(cases) do
    local function fixedRoll() return c.roll end
    local damage = SoldierAnt.calculateAttackDamage(ATK, c.def, fixedRoll)
    luaunit.assertEquals(damage, c.damage, string.format("DEF=%d", c.def))
  end
end

-- DoubleStrike branch (~23%): a single calc_damage roll, doubled - NOT a genuine double-roll
-- (distinct from the Queen-commanded ant_commanded_attack_damage, which really does roll twice).
-- 2 live-captured values, both bit-exact - the first live confirmation of this branch ever
-- captured in this project.
function TestSoldierAntDamage:testLiveCapturedDoubleStrikeDamage()
  local ATK = 48
  local cases = {
    { def = 21, roll = 2328, damage = 56 }, -- ant6 -> party slot 2 (needed HPMax boosted to 300 -
                                              -- HPMax-1 alone still died, the doubled hit can
                                              -- exceed a target's own real max HP entirely)
    { def = 31, roll = 18238, damage = 32 }, -- ant8 -> party slot 3 (survived naturally)
  }
  for _, c in ipairs(cases) do
    local function fixedRoll() return c.roll end
    local damage = SoldierAnt.calculateDoubleStrikeDamage(ATK, c.def, fixedRoll)
    luaunit.assertEquals(damage, c.damage, string.format("DEF=%d", c.def))
  end
end

-- calculateDoubleStrikeDamage really is calculateAttackDamage's own result doubled, not a
-- separately-varying formula - same underlying calcVariance roll, just *2 after.
function TestSoldierAntDamage:testDoubleStrikeIsAttackDamageDoubled()
  local function fixedRoll() return 15186 end
  local attackDamage = SoldierAnt.calculateAttackDamage(48, 31, fixedRoll)
  local doubleStrikeDamage = SoldierAnt.calculateDoubleStrikeDamage(48, 31, fixedRoll)
  luaunit.assertEquals(doubleStrikeDamage, attackDamage * 2)
end

os.exit(luaunit.LuaUnit.run())
