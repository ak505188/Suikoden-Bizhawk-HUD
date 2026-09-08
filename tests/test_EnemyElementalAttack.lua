-- Run with: lua5.4 tests/test_EnemyElementalAttack.lua (from the project root)
--
-- Validated against a real Zombie Dragon fire-breath cast (ZombieDragonT2.State, seed
-- 0x00000001): the exact sequence of rand() calls consumed for damage application (one per
-- living target, six total) was traced live and matched by hand against each target's real
-- MGC/damage - see docs/game_mechanics/Battle_Damage_Formula.md's "Enemy elemental attacks"
-- section for the full derivation.

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local RNGLib = require "lib.RNG"
local EnemyElementalAttack = require "lib.EnemyElementalAttack"

TestEnemyElementalAttack = {}

-- The RNG state the instant before the first of the six damage rolls (captured live -
-- everything before this point, including whatever decided fire breath would fire this
-- turn, isn't part of this formula). Zombie Dragon's own MGC is 130 in this savestate.
function TestEnemyElementalAttack:testZombieDragonFireBreath()
  local DRAGON_MGC = 130
  local seed = 0xe95678e2

  local function rand()
    seed = RNGLib.nextRNG(seed)
    return RNGLib.getRNG2(seed)
  end

  local Compat = EnemyElementalAttack.Compat
  -- targetMgc, compat, expectedDamage (or expected minimum for the two overkill targets,
  -- whose real observed damage was capped at their remaining HP rather than the formula's
  -- full result)
  local targets = {
    { mgc = 47, compat = Compat.NEUTRAL, expected = 75 },
    { mgc = 39, compat = Compat.NEUTRAL, expected = 96 },
    { mgc = 80, compat = Compat.RESIST,  expected = 26 },
    { mgc = 93, compat = Compat.NEUTRAL, expected = 39 },
  }

  for i, t in ipairs(targets) do
    local damage = EnemyElementalAttack.calculateDamage(DRAGON_MGC, t.mgc, t.compat, rand)
    luaunit.assertEquals(damage, t.expected, string.format("target %d", i))
  end

  -- The remaining two targets (MGC 21 and 36, both NEUTRAL) were overkilled in the real
  -- capture (their observed damage was just however much HP they had left - 20 and 41 -
  -- not the formula's full result). Confirm the formula's full result comfortably exceeds
  -- what they actually had, rather than trying to match an already-capped number.
  local overkillTargets = {
    { mgc = 21, minExpected = 20 },
    { mgc = 36, minExpected = 41 },
  }
  for i, t in ipairs(overkillTargets) do
    local damage = EnemyElementalAttack.calculateDamage(DRAGON_MGC, t.mgc, Compat.NEUTRAL, rand)
    luaunit.assertTrue(damage > t.minExpected,
      string.format("overkill target %d: expected > %d, got %d", i, t.minExpected, damage))
  end
end

function TestEnemyElementalAttack:testElementalScaling()
  local calls = 0
  local function fixedRand()
    calls = calls + 1
    return 0 -- roll of 0 for a clean, predictable base case
  end

  local Compat = EnemyElementalAttack.Compat
  -- base = 100 - 50 = 50 (>= 10, so the variance branch applies); roll=0 gives
  -- variance = cDiv(25 - 0, 5) = 5, so pre-scaling damage = 55
  local neutral = EnemyElementalAttack.calculateDamage(100, 50, Compat.NEUTRAL, fixedRand)
  luaunit.assertEquals(neutral, 55)

  calls = 0
  local weak = EnemyElementalAttack.calculateDamage(100, 50, Compat.WEAK, fixedRand)
  luaunit.assertEquals(weak, 110)

  calls = 0
  local resist = EnemyElementalAttack.calculateDamage(100, 50, Compat.RESIST, fixedRand)
  luaunit.assertEquals(resist, 27) -- floor(55/2)

  calls = 0
  local immune = EnemyElementalAttack.calculateDamage(100, 50, Compat.IMMUNE, fixedRand)
  luaunit.assertEquals(immune, 0)
end

function TestEnemyElementalAttack:testFloorAtOne()
  local function zeroRand() return 0 end
  -- base < 10: (base+1) - rand()%4 = (5+1) - 0 = 6, still positive
  local small = EnemyElementalAttack.calculateDamage(55, 50, EnemyElementalAttack.Compat.NEUTRAL, zeroRand)
  luaunit.assertTrue(small >= 1)
end

os.exit(luaunit.LuaUnit.run())
