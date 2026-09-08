-- Run with: lua5.4 tests/test_DamageVariance.lua (from the project root)
--
-- lib.DamageVariance holds calc_damage's own shared RNG-variance step - extracted out of
-- lib.EnemyElementalAttack on 2026-09-07 (user: "Why is Soldier Ant using
-- EnemyElementalAttack?" -> "yeah" to extracting it) so purely physical callers (Neclord's Bats,
-- Queen Ant's commanded-ant damage, Soldier Ant's Attack/DoubleStrike) don't need to import a
-- module named after elemental attacks for a formula that has nothing to do with elements. Pure
-- move, no formula change - every existing bit-exact live-captured value across the
-- Enemies/*.lua modules that used to go through EnemyElementalAttack.calcVariance still passes
-- unchanged (see their own test files).

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local DamageVariance = require "lib.DamageVariance"

TestDamageVariance = {}

function TestDamageVariance:testCDivTruncatesTowardZero()
  luaunit.assertEquals(DamageVariance.cDiv(7, 2), 3)
  luaunit.assertEquals(DamageVariance.cDiv(-7, 2), -3) -- C truncation, not Lua's floor (-4)
  luaunit.assertEquals(DamageVariance.cDiv(7, -2), -3)
  luaunit.assertEquals(DamageVariance.cDiv(-7, -2), 3)
end

-- base < 10: small flat +-variance shape.
function TestDamageVariance:testSmallBase()
  local function fixedRoll() return 2 end
  -- (base+1) - (roll%4) = (5+1) - (2%4) = 6 - 2 = 4
  luaunit.assertEquals(DamageVariance.calcVariance(5, fixedRoll), 4)
end

-- base >= 10: ~+-10% variance shape.
function TestDamageVariance:testLargeBase()
  local function fixedRoll() return 0 end
  -- base + cDiv((base//2) - (roll%base), 5) = 27 + cDiv(13 - 0, 5) = 27 + 2 = 29
  luaunit.assertEquals(DamageVariance.calcVariance(27, fixedRoll), 29)
end

-- Bit-exact live-captured values already confirmed elsewhere in this project, re-verified here
-- directly against the extracted module (Soldier Ant's Attack branch, ant6->party slot 2).
function TestDamageVariance:testLiveCapturedValue()
  local function fixedRoll() return 6421 end
  local damage = DamageVariance.calcVariance(48 - 21, fixedRoll)
  luaunit.assertEquals(damage, 26)
end

os.exit(luaunit.LuaUnit.run())
