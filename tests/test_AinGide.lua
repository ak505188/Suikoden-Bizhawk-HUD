-- Run with: lua5.4 tests/test_AinGide.lua (from the project root)
--
-- Every vector is a live capture (scripts/TraceAinGide.lua on AinGide.State, 40 injected seeds x 2
-- rounds, 2026-10-07; scripts/CheckAinGideTrace.py matched all 80 rounds). `seed` is the RNG at the
-- frame Ain Gide became the current actor; target is the 1-indexed front-row candidate (all
-- captures had 3 candidates); finalSeed is the RNG after the Special's last (damage) roll.

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local AinGide = require "lib.Enemies.AinGide"

TestAinGideMoveSelection = {}

function TestAinGideMoveSelection:testSpecialSeeds()
  local cases = {
    { seed = 0x0627a76d, target = 1, calls = 2, living = 6, finalSeed = 0x103c4075 },
    { seed = 0xcbcd91dc, target = 2, calls = 3, living = 6, finalSeed = 0xf5fb0ced },
    { seed = 0x231ed89f, target = 2, calls = 3, living = 6, finalSeed = 0x3e1ef914 },
    { seed = 0x8e64d1ae, target = 1, calls = 2, living = 5, finalSeed = 0x584123b1 },
    { seed = 0xf32cdd26, target = 3, calls = 7, living = 6, finalSeed = 0x2196534b },
    { seed = 0xff2f7485, target = 2, calls = 6, living = 6, finalSeed = 0x9b0b7289 },
    { seed = 0x3aee29c3, target = 2, calls = 9, living = 6, finalSeed = 0xce9c9032 },
    { seed = 0x17f88194, target = 2, calls = 3, living = 5, finalSeed = 0x073257bc },
  }
  for _, c in ipairs(cases) do
    local move, target, seed, calls = AinGide.simulateMoveSelection(c.seed, 3)
    local msg = string.format("seed %08x", c.seed)
    luaunit.assertEquals(move, "Special", msg)
    luaunit.assertEquals(target, c.target, msg)
    luaunit.assertEquals(calls, c.calls, msg)
    local final, total = AinGide.simulateSpecial(seed, c.living)
    luaunit.assertEquals(final, c.finalSeed, msg)
    luaunit.assertEquals(total, 48 + c.living, msg)
  end
end

function TestAinGideMoveSelection:testAttackSeeds()
  local cases = {
    { seed = 0x12df7e47, target = 1, calls = 2 },
    { seed = 0x3f88c4ff, target = 1, calls = 2 },
    { seed = 0xd1c16625, target = 1, calls = 5 },
    { seed = 0x8063f3ab, target = 3, calls = 4 },
    { seed = 0xd7b53a6e, target = 2, calls = 6 },
    { seed = 0x8c4b9c3d, target = 2, calls = 3 },
  }
  for _, c in ipairs(cases) do
    local move, target, _, calls = AinGide.simulateMoveSelection(c.seed, 3)
    local msg = string.format("seed %08x", c.seed)
    luaunit.assertEquals(move, "Attack", msg)
    luaunit.assertEquals(target, c.target, msg)
    luaunit.assertEquals(calls, c.calls, msg)
  end
end

TestAinGideSpecialDamage = {}

-- Live capture s1 r1 (T0 seed 0x0627a76d, move selection takes 2 rolls, then 48 particle rolls),
-- every rune config from scripts/TestAinGideRunes.lua. Members' MGC: 154 79 132 201 138 190.
local MGC = { 154, 79, 132, 201, 138, 190 }
local function damages(runes)
  local RNGLib = require "lib.RNG"
  local _, _, seed = AinGide.simulateMoveSelection(0x0627a76d, 3)
  for _ = 1, AinGide.SPECIAL_PARTICLE_ROLLS do seed = RNGLib.nextRNG(seed) end
  local out = {}
  for i = 1, 6 do
    seed = RNGLib.nextRNG(seed)
    local roll = RNGLib.getRNG2(seed)
    out[i] = AinGide.calculateSpecialDamage(MGC[i], runes[i], i, function() return roll end)
  end
  return out
end

function TestAinGideSpecialDamage:testRuneConfigs()
  -- unlisted rune (Boar 8): only slot 1 gets the accidental halving
  luaunit.assertEquals(damages({ 8, 8, 8, 8, 8, 8 }), { 137, 332, 259, 192, 291, 203 })
  luaunit.assertEquals(damages({ 0, 0, 0, 0, 0, 0 }), { 137, 332, 259, 192, 291, 203 })
  -- Fire: a real halving everywhere
  luaunit.assertEquals(damages({ 2, 2, 2, 2, 2, 2 }), { 137, 166, 129, 96, 145, 101 })
  -- Water (listed, category 2): no reduction at all, and it masks the slot-1 bug
  luaunit.assertEquals(damages({ 3, 3, 3, 3, 3, 3 })[1], 275)
  luaunit.assertEquals(damages({ 3, 8, 8, 8, 8, 8 })[1], 275)
  -- slot 1 unlisted, the rest Water: slot 1 still halved, the rest unreduced
  luaunit.assertEquals(damages({ 8, 3, 3, 3, 3, 3 })[1], 137)
end

os.exit(luaunit.LuaUnit.run())
