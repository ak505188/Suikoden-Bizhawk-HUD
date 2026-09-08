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

TestDancingFlames = {}

-- Unlike the other spells, Dancing Flames' RNG cost is a fixed constant (5 waves of 30
-- rand() calls, confirmed via a live capture) rather than seed-derived, so there's only
-- one case to pin - see Battle_Damage_Formula.md's "Dancing Flames" section.
function TestDancingFlames:testFixedTotal()
  luaunit.assertEquals(Magic.simulateDancingFlames(), 150)
end

TestShiningWind = {}

-- The original savestate's seed, validated tick-by-tick against a live frame-by-frame
-- capture (all 159 active ticks matched exactly, not just the total) - the hardest spell
-- traced so far, requiring several rounds of live-vs-simulated comparison to find a subtle
-- "accidental schedule re-match" quirk in one of its four particle pools.
function TestShiningWind:testKnownCapturedSeed()
  luaunit.assertEquals(Magic.simulateShiningWind(0xd7250f7e), 1302)
end

-- 20 more seeds, each injected directly into the savestate and measured live the same way
-- as the other spells' - all matched the simulator exactly (0 discrepancies). Validated
-- using a phase-counter-based settle check (waiting for case 4, which has zero RNG calls,
-- rather than a "quiet for N frames" heuristic) since this spell's chaotic Pool A
-- resonance pattern can produce longer quiet stretches than a naive threshold expects.
function TestShiningWind:testValidatedSeeds()
  local cases = {
    { 0x11111111, 1314 },
    { 0xcafebabe, 1338 },
    { 0xdeadbeef, 1320 },
    { 0x00000001, 1314 },
    { 0x7fffffff, 1356 },
    { 0x9e3779b9, 1350 },
    { 0x12345678, 1308 },
    { 0xa5a5a5a5, 1320 },
    { 0x00c0ffee, 1338 },
    { 0x1badb002, 1320 },
    { 0x5eadbeef, 1320 },
    { 0x8badf00d, 1338 },
    { 0xfeedface, 1326 },
    { 0x0defaced, 1320 },
    { 0xabad1dea, 1338 },
    { 0x31337000, 1308 },
    { 0x42424242, 1362 },
    { 0x55555555, 1344 },
    { 0xaaaaaaaa, 1296 },
    { 0xfffffffe, 1314 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateShiningWind(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

TestStormFang = {}

-- Storm Fang's RNG cost is a fixed constant (38 calls, all in the setup frame - confirmed
-- via a live capture spanning the spell's whole duration, the RNG never changes again
-- after that) rather than seed-derived, so there's only one case to pin - see
-- Battle_Damage_Formula.md's "Storm Fang" section.
function TestStormFang:testFixedTotal()
  luaunit.assertEquals(Magic.simulateStormFang(), 38)
end

TestHell = {}

-- Both savestates' own native seeds, each validated via a fresh live capture (savestate.load,
-- run to the case2->case3 phase transition, compare the resulting RNG state) rather than a
-- per-tick trace, since Hell's mechanism (see spell_hell_tick_state_machine's plate comment)
-- makes the per-tick call count depend on a global scaleAccum value baked into individual
-- particles' spawn formulas - the exact final RNG state is the more reliable ground truth.
-- TedHell.State is a scripted fight, McDohlHell.State is a random encounter, and
-- McDohlHellGregminster.State is a third, independently-supplied encounter - all three
-- produced byte-identical per-slot constant tables and (for every seed in
-- testValidatedSeeds below) byte-identical final RNG states, ruling out a
-- camera-position/battle-context dependence.
function TestHell:testKnownCapturedSeeds()
  luaunit.assertEquals(Magic.simulateHell(0x333db67a), 10972) -- TedHell.State
  luaunit.assertEquals(Magic.simulateHell(0xda27f738), 10784) -- McDohlHell.State
  luaunit.assertEquals(Magic.simulateHell(0x51a1ed4b), 12220) -- McDohlHellGregminster.State
end

-- 20 more seeds, each injected directly into all THREE savestates and measured live via the
-- same phase-transition method - every seed produced the identical final RNG state on all
-- three savestates, and every one matches the simulator exactly (0 discrepancies).
function TestHell:testValidatedSeeds()
  local cases = {
    { 0x00000001, 11280 },
    { 0x12345678, 11668 },
    { 0xdeadbeef, 10812 },
    { 0x00000000, 10400 },
    { 0xffffffff, 10780 },
    { 0x1b65fc6a, 11224 },
    { 0xd7250f7e, 10864 },
    { 0x41c64e6d, 11708 },
    { 0x7fffffff, 10780 },
    { 0x80000000, 10400 },
    { 0x0badf00d, 11308 },
    { 0xcafebabe, 10764 },
    { 0x5eed1234, 10824 },
    { 0x99999999, 11332 },
    { 0x33333333, 10532 },
    { 0x0000ffff, 10824 },
    { 0xffff0000, 12220 },
    { 0x11111111, 10832 },
    { 0x22222222, 10756 },
    { 0xabcdef01, 11192 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateHell(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

TestBlackShadow = {}

-- Both savestates' own native seeds. Unlike every other spell here, Black Shadow's total
-- isn't a pure function of seed alone - it also depends on per-savestate stale VFX-pool
-- memory (see spell_blackshadow_tick_state_machine's plate comment and simulateBlackShadow's
-- comment in lib/Magic.lua), so each savestate needs its own captured scale/residual table,
-- passed via the dedicated simulateBlackShadowWind/Bats wrappers.
function TestBlackShadow:testKnownCapturedSeeds()
  luaunit.assertEquals(Magic.simulateBlackShadowWind(0x6a2d97b4), 5796) -- BlackShadowWind.State
  luaunit.assertEquals(Magic.simulateBlackShadowBats(0x06614a28), 9476) -- BlackShadowBats.State
end

-- 20 more seeds, each injected directly into both savestates and measured live via the same
-- phase-transition method (case2->case3) as the other spells - every seed matches the
-- simulator's prediction exactly (0 discrepancies), using each savestate's own table.
function TestBlackShadow:testValidatedSeedsWind()
  local cases = {
    { 0x00000001, 6260 },
    { 0x12345678, 5736 },
    { 0xdeadbeef, 5968 },
    { 0x00000000, 5884 },
    { 0xffffffff, 5928 },
    { 0x1b65fc6a, 5732 },
    { 0xd7250f7e, 5664 },
    { 0x41c64e6d, 6548 },
    { 0x7fffffff, 5928 },
    { 0x80000000, 5884 },
    { 0x0badf00d, 5964 },
    { 0xcafebabe, 5860 },
    { 0x5eed1234, 6496 },
    { 0x99999999, 6616 },
    { 0x33333333, 6272 },
    { 0x0000ffff, 5800 },
    { 0xffff0000, 6276 },
    { 0x11111111, 5844 },
    { 0x22222222, 6376 },
    { 0xabcdef01, 6384 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateBlackShadowWind(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

function TestBlackShadow:testValidatedSeedsBats()
  local cases = {
    { 0x00000001, 9808 },
    { 0x12345678, 9632 },
    { 0xdeadbeef, 9560 },
    { 0x00000000, 9484 },
    { 0xffffffff, 9544 },
    { 0x1b65fc6a, 9708 },
    { 0xd7250f7e, 9572 },
    { 0x41c64e6d, 9648 },
    { 0x7fffffff, 9544 },
    { 0x80000000, 9484 },
    { 0x0badf00d, 10188 },
    { 0xcafebabe, 9552 },
    { 0x5eed1234, 9960 },
    { 0x99999999, 9444 },
    { 0x33333333, 9824 },
    { 0x0000ffff, 9500 },
    { 0xffff0000, 9832 },
    { 0x11111111, 9480 },
    { 0x22222222, 9712 },
    { 0xabcdef01, 9876 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateBlackShadowBats(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

os.exit(luaunit.LuaUnit.run())
