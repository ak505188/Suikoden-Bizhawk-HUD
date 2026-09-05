-- Run with: lua5.4 tests/test_Magic.lua (from the project root)
--
-- Every expected value here was independently confirmed against a live BizHawk capture
-- (savestate + injected RNG seed), not just derived from the simulator itself - see
-- docs/game_mechanics/Battle_Damage_Formula.md's "How spells call RNG" section for the
-- full derivation and validation methodology.

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local Magic = require "lib.Magic"

TestEarthquake = {}

-- The original savestate's seed, validated tick-by-tick against a live frame-by-frame
-- capture (all ticks matched exactly, not just the total).
function TestEarthquake:testKnownCapturedSeed()
  luaunit.assertEquals(Magic.simulateEarthquake(0xe15d6b34), 1626)
end

-- 20 more seeds, each injected directly into the savestate and measured live via
-- LCG-step-counting from seed to the real settled RNG value - all matched the
-- simulator exactly (0 discrepancies).
function TestEarthquake:testValidatedSeeds()
  local cases = {
    { 0x11111111, 1639 },
    { 0xcafebabe, 1678 },
    { 0xdeadbeef, 1607 },
    { 0x00000001, 1534 },
    { 0x7fffffff, 1667 },
    { 0x9e3779b9, 1621 },
    { 0x12345678, 1631 },
    { 0xa5a5a5a5, 1659 },
    { 0x00c0ffee, 1622 },
    { 0x1badb002, 1614 },
    { 0x5eadbeef, 1607 },
    { 0x8badf00d, 1677 },
    { 0xfeedface, 1630 },
    { 0x0defaced, 1625 },
    { 0xabad1dea, 1592 },
    { 0x31337000, 1643 },
    { 0x42424242, 1704 },
    { 0x55555555, 1651 },
    { 0xaaaaaaaa, 1628 },
    { 0xfffffffe, 1639 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateEarthquake(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

TestCharmArrow = {}

-- The original savestate's seed, validated tick-by-tick against a live frame-by-frame
-- capture (all 64 ticks matched exactly, not just the total).
function TestCharmArrow:testKnownCapturedSeed()
  luaunit.assertEquals(Magic.simulateCharmArrow(0xddb92a9b), 24436)
end

-- 20 more seeds, each injected directly into the savestate and measured live the same
-- way as Earthquake's - all matched the simulator exactly (0 discrepancies).
function TestCharmArrow:testValidatedSeeds()
  local cases = {
    { 0x11111111, 24967 },
    { 0xcafebabe, 24828 },
    { 0xdeadbeef, 24305 },
    { 0x00000001, 24586 },
    { 0x7fffffff, 24412 },
    { 0x9e3779b9, 24438 },
    { 0x12345678, 24660 },
    { 0xa5a5a5a5, 24835 },
    { 0x00c0ffee, 24690 },
    { 0x1badb002, 24302 },
    { 0x5eadbeef, 24305 },
    { 0x8badf00d, 24675 },
    { 0xfeedface, 24599 },
    { 0x0defaced, 24386 },
    { 0xabad1dea, 24508 },
    { 0x31337000, 24519 },
    { 0x42424242, 24595 },
    { 0x55555555, 24381 },
    { 0xaaaaaaaa, 24659 },
    { 0xfffffffe, 24457 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateCharmArrow(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

TestFlamingArrow = {}

-- The original savestate's seed, validated tick-by-tick against a live frame-by-frame
-- capture (all 95 active ticks matched exactly, not just the total).
function TestFlamingArrow:testKnownCapturedSeed()
  luaunit.assertEquals(Magic.simulateFlamingArrow(0x1b65fc6a), 512)
end

-- 20 more seeds, each injected directly into the savestate and measured live the same
-- way as Earthquake's/Charm Arrow's - all matched the simulator exactly (0 discrepancies).
function TestFlamingArrow:testValidatedSeeds()
  local cases = {
    { 0x11111111, 524 },
    { 0xcafebabe, 540 },
    { 0xdeadbeef, 536 },
    { 0x00000001, 504 },
    { 0x7fffffff, 504 },
    { 0x9e3779b9, 516 },
    { 0x12345678, 528 },
    { 0xa5a5a5a5, 520 },
    { 0x00c0ffee, 524 },
    { 0x1badb002, 540 },
    { 0x5eadbeef, 536 },
    { 0x8badf00d, 512 },
    { 0xfeedface, 524 },
    { 0x0defaced, 496 },
    { 0xabad1dea, 532 },
    { 0x31337000, 508 },
    { 0x42424242, 476 },
    { 0x55555555, 524 },
    { 0xaaaaaaaa, 536 },
    { 0xfffffffe, 472 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateFlamingArrow(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

os.exit(luaunit.LuaUnit.run())
