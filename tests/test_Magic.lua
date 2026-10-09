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

TestFinalFlame = {}

-- Cleo (Rage Rune) casting Final Flame on Zombie Dragon (ZombieDragonStart.State), seed read
-- the frame before spell_finalflame_vfx_setup runs - validated tick-by-tick against the live
-- per-frame capture (every tick of setup and cases 1-2 matched, not just the total).
function TestFinalFlame:testKnownCapturedSeed()
  luaunit.assertEquals(Magic.simulateFinalFlame(0x799c61f8), 538)
end

-- 20 more seeds, each injected into the same savestate (scripts/CaptureFinalFlameSeeds.lua) and
-- measured live per tick - all matched the simulator exactly (0 discrepancies), as did the 9
-- other seeds of the first capture.
function TestFinalFlame:testValidatedSeeds()
  local cases = {
    { 0xadad7f18, 536 },
    { 0xe8ffa639, 534 },
    { 0x2451cd5a, 536 },
    { 0x5fa3f47b, 538 },
    { 0x9af61b9c, 540 },
    { 0xd64842bd, 530 },
    { 0x119a69de, 530 },
    { 0x4cec90ff, 528 },
    { 0x883eb820, 532 },
    { 0xc390df41, 526 },
    { 0xfee30662, 530 },
    { 0x3a352d83, 534 },
    { 0x758754a4, 538 },
    { 0xb0d97bc5, 530 },
    { 0xec2ba2e6, 530 },
    { 0x277dca07, 534 },
    { 0x62cff128, 540 },
    { 0x9e221849, 532 },
    { 0xd9743f6a, 532 },
    { 0x14c6668b, 530 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateFinalFlame(seed), expected,
      string.format("seed 0x%08x", seed))
  end
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

TestScolding = {}

-- Zero RNG, static only (spell_scolding_* plate comments).
function TestScolding:testFixedTotal()
  luaunit.assertEquals(Magic.simulateScolding(), 0)
end

TestYell = {}

-- Fixed 33: 11 sparkle activations x 3 rand(). Live: 20 injected seeds all gave 33 (scripts/CaptureYellSeeds.lua,
-- aimed at a live ally); the first seed's activations were at counter 10,20,29,30,34,39,40,41,44,46,47.
function TestYell:testFixedTotal()
  luaunit.assertEquals(Magic.simulateYell(), 33)
end

TestScream = {}

-- Fixed 162: 54 sparkle activations x 3 rand(). Live: 20 injected seeds all gave 162
-- (scripts/CaptureScreamSeeds.lua) and the first seed's per-tick counts matched the model.
function TestScream:testFixedTotal()
  luaunit.assertEquals(Magic.simulateScream(), 162)
end

TestBlazingCamp = {}

-- Fixed 54: 10 meteors x (2 + 1 impact) + 12 sparkles x 2. Live: 20 injected seeds all gave 54
-- (scripts/CaptureBlazingCampSeeds.lua) and the first seed's per-tick counts matched.
function TestBlazingCamp:testFixedTotal()
  luaunit.assertEquals(Magic.simulateBlazingCamp(), 54)
end

TestThor = {}

-- McDohl Lightning + Luc Water (Magic Unite Thor, id 37) on SpellDuration.State, aimed at the first enemy. 20
-- injected seeds (scripts/CaptureThorSeeds.lua): the real rand() count from spell_thor_vfx_setup (0x8011a81c) to
-- the end handler (0x8011bc3c). Each case is { RNG at setup, calls }. The first seed's per-tick counts matched too
-- (6 at setup, 8 at the bolt tick, 83 when the 20 arcs first spawn, ...).
function TestThor:testKnownSeed()
  luaunit.assertEquals(Magic.simulateThor(0x58dbd149), 594)
end

function TestThor:testValidatedSeeds()
  local cases = {
    { 0x58dbd149, 594 }, -- injected seed 0x11111111
    { 0xb4a56396, 590 }, -- injected seed 0xcafebabe
    { 0xf0289ce7, 574 }, -- injected seed 0xdeadbeef
    { 0x9cfbae39, 590 }, -- injected seed 0x00000001
    { 0x7d3feff7, 554 }, -- injected seed 0x7fffffff
    { 0x3101a6f1, 550 }, -- injected seed 0x9e3779b9
    { 0x6ac77c90, 570 }, -- injected seed 0x12345678
    { 0xdd33e45d, 610 }, -- injected seed 0xa5a5a5a5
    { 0x67651ec6, 570 }, -- injected seed 0x00c0ffee
    { 0x3a8d3d5a, 574 }, -- injected seed 0x1badb002
    { 0x70289ce7, 574 }, -- injected seed 0x5eadbeef
    { 0x10de13c5, 574 }, -- injected seed 0x8badf00d
    { 0x0d1a95a6, 566 }, -- injected seed 0xfeedface
    { 0x4c3e8ca5, 586 }, -- injected seed 0x0defaced
    { 0xc47f8042, 578 }, -- injected seed 0xabad1dea
    { 0xa34f3f18, 586 }, -- injected seed 0x31337000
    { 0xa059d79a, 566 }, -- injected seed 0x42424242
    { 0x87d3da0d, 554 }, -- injected seed 0x55555555
    { 0x4289e502, 574 }, -- injected seed 0xaaaaaaaa
    { 0x2d6210d6, 550 }, -- injected seed 0xfffffffe
  }
  for _, case in ipairs(cases) do
    luaunit.assertEquals(Magic.simulateThor(case[1]), case[2], string.format("seed 0x%08x", case[1]))
  end
end

TestScorchedEarth = {}

-- Fixed 282: 48 setup + 154 (F) + 32 (A) + 48 (E). Live: 20 injected seeds all gave 282
-- (scripts/CaptureScorchedEarthSeeds.lua) and the first seed's per-tick counts matched.
function TestScorchedEarth:testFixedTotal()
  luaunit.assertEquals(Magic.simulateScorchedEarth(), 282)
end

TestWaterDragon = {}

-- McDohl Water + Luc Wind (Magic Unite Water Dragon, id 38) on SpellDuration.State, aimed at the first enemy. 20
-- injected seeds (scripts/CaptureWaterDragonSeeds.lua): the real rand() count from spell_waterdragon_vfx_setup
-- (0x8011be0c) to the end handler (0x8011cd48). Each case is { RNG at setup, calls }. The first seed's per-tick
-- counts matched too (302 at setup, 440 on the first gated pass).
function TestWaterDragon:testKnownSeed()
  luaunit.assertEquals(Magic.simulateWaterDragon(0x58dbd149), 2998)
end

function TestWaterDragon:testValidatedSeeds()
  local cases = {
    { 0x58dbd149, 2998 }, -- injected seed 0x11111111
    { 0xb4a56396, 3024 }, -- injected seed 0xcafebabe
    { 0xf0289ce7, 3013 }, -- injected seed 0xdeadbeef
    { 0x9cfbae39, 3179 }, -- injected seed 0x00000001
    { 0x7d3feff7, 3160 }, -- injected seed 0x7fffffff
    { 0x3101a6f1, 3128 }, -- injected seed 0x9e3779b9
    { 0x6ac77c90, 3040 }, -- injected seed 0x12345678
    { 0xdd33e45d, 3025 }, -- injected seed 0xa5a5a5a5
    { 0x67651ec6, 3104 }, -- injected seed 0x00c0ffee
    { 0x3a8d3d5a, 3037 }, -- injected seed 0x1badb002
    { 0x70289ce7, 3013 }, -- injected seed 0x5eadbeef
    { 0x10de13c5, 3013 }, -- injected seed 0x8badf00d
    { 0x0d1a95a6, 3061 }, -- injected seed 0xfeedface
    { 0x4c3e8ca5, 3022 }, -- injected seed 0x0defaced
    { 0xc47f8042, 3193 }, -- injected seed 0xabad1dea
    { 0xa34f3f18, 3095 }, -- injected seed 0x31337000
    { 0xa059d79a, 3097 }, -- injected seed 0x42424242
    { 0x87d3da0d, 3004 }, -- injected seed 0x55555555
    { 0x4289e502, 3099 }, -- injected seed 0xaaaaaaaa
    { 0x2d6210d6, 3048 }, -- injected seed 0xfffffffe
  }
  for _, case in ipairs(cases) do
    luaunit.assertEquals(Magic.simulateWaterDragon(case[1]), case[2], string.format("seed 0x%08x", case[1]))
  end
end

TestDeadlyFingertips = {}

-- McDohl's own Soul Eater Rune slot 1 (Deadly Fingertips, id 25) on SpellDuration.State, aimed at the first
-- enemy. 20 injected seeds (scripts/CaptureDeadlyFingertipsSeeds.lua): the real rand() count from
-- spell_deadlyfingertips_vfx_setup (0x80113a90) to the cleanup (0x801147d4). Each case is { RNG at setup, calls }.
-- The first seed's per-tick counts matched too (150 on the first pass, then 5 per spark respawn).
function TestDeadlyFingertips:testKnownSeed()
  luaunit.assertEquals(Magic.simulateDeadlyFingertips(0x58dbd149), 1130)
end

function TestDeadlyFingertips:testValidatedSeeds()
  local cases = {
    { 0x58dbd149, 1130 }, -- injected seed 0x11111111
    { 0xb4a56396, 1120 }, -- injected seed 0xcafebabe
    { 0xf0289ce7, 1100 }, -- injected seed 0xdeadbeef
    { 0x9cfbae39, 1110 }, -- injected seed 0x00000001
    { 0x7d3feff7, 1150 }, -- injected seed 0x7fffffff
    { 0x3101a6f1, 1160 }, -- injected seed 0x9e3779b9
    { 0x6ac77c90, 1145 }, -- injected seed 0x12345678
    { 0xdd33e45d, 1120 }, -- injected seed 0xa5a5a5a5
    { 0x67651ec6, 1075 }, -- injected seed 0x00c0ffee
    { 0x3a8d3d5a, 1150 }, -- injected seed 0x1badb002
    { 0x70289ce7, 1100 }, -- injected seed 0x5eadbeef
    { 0x10de13c5, 1160 }, -- injected seed 0x8badf00d
    { 0x0d1a95a6, 1125 }, -- injected seed 0xfeedface
    { 0x4c3e8ca5, 1075 }, -- injected seed 0x0defaced
    { 0xc47f8042, 1140 }, -- injected seed 0xabad1dea
    { 0xa34f3f18, 1120 }, -- injected seed 0x31337000
    { 0xa059d79a, 1120 }, -- injected seed 0x42424242
    { 0x87d3da0d, 1170 }, -- injected seed 0x55555555
    { 0x4289e502, 1105 }, -- injected seed 0xaaaaaaaa
    { 0x2d6210d6, 1105 }, -- injected seed 0xfffffffe
  }
  for _, case in ipairs(cases) do
    luaunit.assertEquals(Magic.simulateDeadlyFingertips(case[1]), case[2], string.format("seed 0x%08x", case[1]))
  end
end

TestAngryBlow = {}

-- 6 rand() calls at the native target depth (z=0); live-measured at forced target z of
-- 0/500/900 -> 6, 1000 -> 5, 1500 -> 4 (scripts/CaptureAngryBlowDepth.lua).
function TestAngryBlow:testFixedTotal()
  luaunit.assertEquals(Magic.simulateAngryBlow(), 6)
end

function TestAngryBlow:testLiveMeasuredDepths()
  for z, expected in pairs({ [0] = 6, [500] = 6, [900] = 6, [1000] = 5, [1500] = 4 }) do
    luaunit.assertEquals(Magic.simulateAngryBlow(z), expected)
  end
end

TestRainstorm = {}

-- 26 + 2 per living enemy: 12 bolts x 2, bolt 0's one respawn x 2, then 2 per enemy in
-- phase 4 (28 for the one-enemy test save; enemy scaling confirmed live by the user).
function TestRainstorm:testOneEnemy()
  luaunit.assertEquals(Magic.simulateRainstorm(1), 28)
end

function TestRainstorm:testScalesWithLivingEnemies()
  for n = 0, 6 do
    luaunit.assertEquals(Magic.simulateRainstorm(n), 26 + 2 * n)
  end
end

TestClayGuardian = {}

-- McDohl's Earth Lv1 (Clay Guardian, id 21) on SpellDuration.State, aimed at himself. 20 injected seeds
-- (scripts/CaptureClayGuardianSeeds.lua): the real rand() count from spell_clayguardian_vfx_setup to the
-- tick machine's end handler (0x80110c38) is LCG-step-counted between the real RNG values. Each case is
-- { RNG at setup, calls }. The first seed's per-tick counts also matched exactly (30 at tick 0, then
-- 3 per sparkle respawn, 6 at ticks 51 and 58).
function TestClayGuardian:testKnownSeed()
  luaunit.assertEquals(Magic.simulateClayGuardian(0x58dbd149), 105)
end

function TestClayGuardian:testValidatedSeeds()
  local cases = {
    { 0x58dbd149, 105 }, -- injected seed 0x11111111
    { 0xb4a56396, 117 }, -- injected seed 0xcafebabe
    { 0xf0289ce7, 129 }, -- injected seed 0xdeadbeef
    { 0x9cfbae39, 120 }, -- injected seed 0x00000001
    { 0x7d3feff7, 111 }, -- injected seed 0x7fffffff
    { 0x3101a6f1, 105 }, -- injected seed 0x9e3779b9
    { 0x6ac77c90, 132 }, -- injected seed 0x12345678
    { 0xdd33e45d, 114 }, -- injected seed 0xa5a5a5a5
    { 0x67651ec6, 105 }, -- injected seed 0x00c0ffee
    { 0x3a8d3d5a, 99 }, -- injected seed 0x1badb002
    { 0x70289ce7, 129 }, -- injected seed 0x5eadbeef
    { 0x10de13c5, 132 }, -- injected seed 0x8badf00d
    { 0x0d1a95a6, 117 }, -- injected seed 0xfeedface
    { 0x4c3e8ca5, 117 }, -- injected seed 0x0defaced
    { 0xc47f8042, 105 }, -- injected seed 0xabad1dea
    { 0xa34f3f18, 96 }, -- injected seed 0x31337000
    { 0xa059d79a, 105 }, -- injected seed 0x42424242
    { 0x87d3da0d, 102 }, -- injected seed 0x55555555
    { 0x4289e502, 114 }, -- injected seed 0xaaaaaaaa
    { 0x2d6210d6, 90 }, -- injected seed 0xfffffffe
  }
  for _, case in ipairs(cases) do
    luaunit.assertEquals(Magic.simulateClayGuardian(case[1]), case[2],
      string.format("seed 0x%08x", case[1]))
  end
end

TestCopperFlesh = {}

-- Zero RNG; the effect is apply_status_effect(target, 8) on phase 4's first tick.
function TestCopperFlesh:testFixedTotal()
  luaunit.assertEquals(Magic.simulateCopperFlesh(), 0)
end

TestGuardianOfEarth = {}

-- McDohl's Mother Earth Rune (id 30, slot 4 = Guardian of Earth, id 33) on SpellDuration.State, party-wide.
-- 20 injected seeds (scripts/CaptureGuardianOfEarthSeeds.lua): the real rand() count from
-- spell_guardianofearth_vfx_setup (0x80112070) to the end handler (0x801129ec). Each case is
-- { RNG at setup, calls }. The first seed's per-tick counts matched too (40 at setup, 2 per sparkle
-- activation, 2 at phase 3's last tick).
function TestGuardianOfEarth:testKnownSeed()
  luaunit.assertEquals(Magic.simulateGuardianOfEarth(0x58dbd149), 408)
end

function TestGuardianOfEarth:testValidatedSeeds()
  local cases = {
    { 0x58dbd149, 408 }, -- injected seed 0x11111111
    { 0xb4a56396, 404 }, -- injected seed 0xcafebabe
    { 0xf0289ce7, 396 }, -- injected seed 0xdeadbeef
    { 0x9cfbae39, 400 }, -- injected seed 0x00000001
    { 0x7d3feff7, 402 }, -- injected seed 0x7fffffff
    { 0x3101a6f1, 408 }, -- injected seed 0x9e3779b9
    { 0x6ac77c90, 396 }, -- injected seed 0x12345678
    { 0xdd33e45d, 380 }, -- injected seed 0xa5a5a5a5
    { 0x67651ec6, 408 }, -- injected seed 0x00c0ffee
    { 0x3a8d3d5a, 384 }, -- injected seed 0x1badb002
    { 0x70289ce7, 396 }, -- injected seed 0x5eadbeef
    { 0x10de13c5, 402 }, -- injected seed 0x8badf00d
    { 0x0d1a95a6, 392 }, -- injected seed 0xfeedface
    { 0x4c3e8ca5, 380 }, -- injected seed 0x0defaced
    { 0xc47f8042, 390 }, -- injected seed 0xabad1dea
    { 0xa34f3f18, 398 }, -- injected seed 0x31337000
    { 0xa059d79a, 384 }, -- injected seed 0x42424242
    { 0x87d3da0d, 400 }, -- injected seed 0x55555555
    { 0x4289e502, 398 }, -- injected seed 0xaaaaaaaa
    { 0x2d6210d6, 394 }, -- injected seed 0xfffffffe
  }
  for _, case in ipairs(cases) do
    luaunit.assertEquals(Magic.simulateGuardianOfEarth(case[1]), case[2],
      string.format("seed 0x%08x", case[1]))
  end
end

TestThunderGod = {}

-- 96 (setup) + 16 (8 bolts x 2) + 360 (24 flicker particles x 3 x 5 activations); static only,
-- see spell_thundergod_tick_state_machine's plate comment.
function TestThunderGod:testFixedTotal()
  luaunit.assertEquals(Magic.simulateThunderGod(), 472)
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

TestExplosion = {}

-- These assert the REAL, live-captured total the game actually produces - NOT whatever
-- simulateExplosion happens to output. Both values verified via direct LCG-step count from
-- seed to the settled post-cast RNG value, AND via an exact tick-by-tick match of every
-- single case2/case3 tick's own RNG delta (not just matching totals) - case2's Pool C and
-- case3's Pool A/B fire+re-fire model are both validated EXACT PER-TICK against both seeds
-- below, a stronger bar than this file's usual total-only broad-seed checks. Per project
-- convention, tests assert game-verified truth, not the simulator's output - if a future
-- change to simulateExplosion breaks either of these, the simulator is wrong, not the test.
function TestExplosion:testKnownCapturedSeed()
  luaunit.assertEquals(Magic.simulateExplosion(0x1b65fc6a), 1220)
end

function TestExplosion:testFreshSeed()
  luaunit.assertEquals(Magic.simulateExplosion(0x11111111), 1271)
end

-- 20 more seeds (the same list used for every other multi-seed spell in this file), each
-- injected directly into Explosion.State and measured live via the same frame-640
-- handoff-to-case4 method (case4/case5 are confirmed zero-RNG, so the RNG value there is the
-- final settled total) - all matched the simulator exactly (0 discrepancies), confirming the
-- Pool A/B re-fire model generalizes beyond the two seeds it was derived from.
function TestExplosion:testValidatedSeeds()
  local cases = {
    { 0x11111111, 1271 },
    { 0xcafebabe, 1280 },
    { 0xdeadbeef, 1259 },
    { 0x00000001, 1284 },
    { 0x7fffffff, 1233 },
    { 0x9e3779b9, 1220 },
    { 0x12345678, 1223 },
    { 0xa5a5a5a5, 1238 },
    { 0x00c0ffee, 1216 },
    { 0x1badb002, 1220 },
    { 0x5eadbeef, 1259 },
    { 0x8badf00d, 1202 },
    { 0xfeedface, 1260 },
    { 0x0defaced, 1257 },
    { 0xabad1dea, 1179 },
    { 0x31337000, 1200 },
    { 0x42424242, 1239 },
    { 0x55555555, 1226 },
    { 0xaaaaaaaa, 1258 },
    { 0xfffffffe, 1252 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateExplosion(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

TestJudgment = {}

-- McDohl's Judgment (Soul Eater Lv4) on SpellDuration.State, start seed read in-game on the
-- frame battle+0x14 held spell_judgment_vfx_setup (scripts/CaptureJudgment.lua). Expected is the
-- real number of rand() calls from that frame through the end of the tick machine, summed from the
-- live per-frame capture (setup's 30 + phase 5's calls), not taken from the simulator. Each seed
-- gave a different setup roll, so these also cover the 161 / 167 spread.
function TestJudgment:testKnownCapturedSeeds()
  luaunit.assertEquals(Magic.simulateJudgment(0xfd5ecce9), 167)
  luaunit.assertEquals(Magic.simulateJudgment(0x60d0e275), 161)
  luaunit.assertEquals(Magic.simulateJudgment(0x72bc8dbc), 167)
end

-- 20 more seeds, injected into SpellDuration.State (scripts/CaptureJudgmentSeeds.lua); the start
-- value is what the RNG held when setup ran (ambient calls before the cast shift it away from the
-- injected one), and the count is the LCG-step distance from it to the RNG value on the first frame
-- of spell_judgment_cleanup. All matched the simulator exactly (0 discrepancies).
function TestJudgment:testValidatedSeeds()
  local cases = {
    { 0x58dbd149, 167 },
    { 0xb4a56396, 173 },
    { 0xf0289ce7, 158 },
    { 0x9cfbae39, 152 },
    { 0x7d3feff7, 170 },
    { 0x3101a6f1, 167 },
    { 0x6ac77c90, 158 },
    { 0xdd33e45d, 164 },
    { 0x67651ec6, 167 },
    { 0x3a8d3d5a, 167 },
    { 0x70289ce7, 158 },
    { 0x10de13c5, 170 },
    { 0x0d1a95a6, 173 },
    { 0x4c3e8ca5, 170 },
    { 0xc47f8042, 164 },
    { 0xa34f3f18, 173 },
    { 0xa059d79a, 155 },
    { 0x87d3da0d, 176 },
    { 0x4289e502, 167 },
    { 0x2d6210d6, 164 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateJudgment(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

TestDropsOfKindness = {}

-- Like Dancing Flames, a fixed total: McDohl's Water Lv1 (Drops of Kindness, on himself) gave exactly 18
-- rand() calls from spell_drops_of_kindness_vfx_setup to the tick machine's end on all 20 injected seeds
-- (scripts/CaptureDropsSeeds.lua, LCG-step distance between the real RNG values), so one case to pin.
function TestDropsOfKindness:testFixedTotal()
  luaunit.assertEquals(Magic.simulateDropsOfKindness(), 18)
end

TestFogOfDeception = {}

-- McDohl's Water Lv2 (Fog of Deception, on the lone enemy of SpellDuration.State) cost exactly 0
-- rand() calls from spell_fog_of_deception_vfx_setup through the tick machine's end handler on all 20
-- injected seeds (scripts/CaptureFogSeeds.lua, LCG-step distance between the real RNG values). The 6
-- calls seen after it come right before the next actor is picked, not from the spell.
function TestFogOfDeception:testFixedTotal()
  luaunit.assertEquals(Magic.simulateFogOfDeception(), 0)
end

TestRainOfKindness = {}

-- McDohl's Water Lv4 (Rain of Kindness; id 12 is Water slot 4, not slot 3) on SpellDuration.State, a
-- party of 6. Start seed = the RNG value read in-game on the frame battle+0x14 held
-- spell_rain_of_kindness_vfx_setup (ambient calls before the cast shift it away from the injected
-- seed); expected = LCG-step distance from it to the RNG value on the first frame of the end handler
-- (0x80107ea4), from scripts/CaptureRainSeeds.lua - not the simulator's output. All 20 matched
-- exactly. Every total is 72 (setup) + 5 per rain-line spawn, and ranges 1527-1572.
function TestRainOfKindness:testValidatedSeeds()
  local cases = {
    { 0x58dbd149, 1562 },
    { 0xb4a56396, 1562 },
    { 0xf0289ce7, 1527 },
    { 0x9cfbae39, 1547 },
    { 0x7d3feff7, 1562 },
    { 0x3101a6f1, 1552 },
    { 0x6ac77c90, 1562 },
    { 0xdd33e45d, 1572 },
    { 0x67651ec6, 1567 },
    { 0x3a8d3d5a, 1547 },
    { 0x70289ce7, 1527 },
    { 0x10de13c5, 1562 },
    { 0x0d1a95a6, 1542 },
    { 0x4c3e8ca5, 1552 },
    { 0xc47f8042, 1537 },
    { 0xa34f3f18, 1527 },
    { 0xa059d79a, 1547 },
    { 0x87d3da0d, 1547 },
    { 0x4289e502, 1532 },
    { 0x2d6210d6, 1552 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateRainOfKindness(seed, 6), expected,
      string.format("seed 0x%08x", seed))
  end
end

-- Same spell with a party of 5 (RainOfKindness.State: McDohl slot 1, Water rune, Lv4 available, nothing
-- edited), same method (scripts/CaptureRainSeeds5.lua). Setup drops to 60 and the totals to 1515-1570,
-- each 60 + 5 per rain-line spawn; 0 mismatches.
function TestRainOfKindness:testValidatedSeedsPartyOfFive()
  local cases = {
    { 0xf0103b50, 1520 },
    { 0x7f88a2b1, 1545 },
    { 0x29749aa6, 1535 },
    { 0xd9e2b600, 1515 },
    { 0x23780ff6, 1535 },
    { 0x8886be98, 1530 },
    { 0x2093fb53, 1570 },
    { 0x61c71e34, 1545 },
    { 0xebb28ca1, 1545 },
    { 0xbf8c7905, 1565 },
    { 0xa9749aa6, 1535 },
    { 0xef984a3c, 1545 },
    { 0x084a1301, 1550 },
    { 0x857d9a9c, 1550 },
    { 0x9933d68d, 1535 },
    { 0x11fe92fb, 1550 },
    { 0xb31e1445, 1540 },
    { 0xb59b9ca4, 1540 },
    { 0x2c89d64d, 1540 },
    { 0x0842bcf1, 1535 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateRainOfKindness(seed, 5), expected,
      string.format("seed 0x%08x", seed))
  end
end

TestWaterOfKindness = {}

-- McDohl's Water Lv3 (Water of Kindness, id 11) on SpellDuration.State, a party of 6: exactly 72 rand()
-- calls from spell_water_of_kindness_vfx_setup to the tick machine's end handler (0x801071b4) on all 20
-- injected seeds (scripts/CaptureWaterOfKindnessSeeds.lua, LCG-step distance between the real RNG
-- values). The cost is 12 per party member, independent of the seed.
function TestWaterOfKindness:testFixedTotalPartyOfSix()
  luaunit.assertEquals(Magic.simulateWaterOfKindness(6), 72)
end

-- Observed in-game by the user with a party of 5 (not captured by a script).
function TestWaterOfKindness:testPartyOfFive()
  luaunit.assertEquals(Magic.simulateWaterOfKindness(5), 60)
end

TestWindOfSleep = {}

-- McDohl's Wind Lv1 (Wind of Sleep, id 13) on WindOfSleep.State (5 enemies, all eligible for the Sleep roll;
-- the rune and MP were edited, see scripts/CaptureWindOfSleep.lua). Native-seed per-frame capture, start
-- seed read on the frame battle+0x14 held spell_wind_of_sleep_vfx_setup: 100 setup + 200 on the first
-- spawn tick + 8 for two life rolls of 0 (one frame, the tick after) + 5 Sleep rolls (one frame, machine
-- tick 360) = 313.
function TestWindOfSleep:testKnownCapturedSeed()
  luaunit.assertEquals(Magic.simulateWindOfSleep(0x96b9137b, 5), 313)
end

-- 20 injected seeds, same state. The start value is what the RNG held when setup ran (ambient calls shift
-- it from the injected one); the count is the LCG-step distance from it to the RNG value on the first
-- frame of the end handler (0x80109358). Every total is 305 (the 300 fixed + 5 enemies) plus 4 per life
-- roll of 0, so 305-317 here. All matched exactly (0 discrepancies).
function TestWindOfSleep:testValidatedSeeds()
  local cases = {
    { 0x8f873905, 309 },
    { 0xab4c2322, 309 },
    { 0x5e582083, 305 },
    { 0x31dff4f5, 305 },
    { 0x21799493, 313 },
    { 0xe0f8c12d, 309 },
    { 0xafcfd1bc, 309 },
    { 0x154f6959, 305 },
    { 0xab046152, 305 },
    { 0xe751d526, 305 },
    { 0xde582083, 305 },
    { 0xbd912741, 305 },
    { 0xbb4a6632, 305 },
    { 0xa0304e21, 305 },
    { 0x81095e8e, 317 },
    { 0xc98534c4, 305 },
    { 0x47edd366, 305 },
    { 0x26f10a09, 309 },
    { 0xe4354f4e, 305 },
    { 0xd9466462, 305 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateWindOfSleep(seed, 5), expected,
      string.format("seed 0x%08x", seed))
  end
end

-- Same spell against SpellDuration.State's lone enemy, Ain Gide: his attack data (battle+0x1344 table,
-- enemy id * 4) has u16 +0x26 = 0x4003, so the 0x4000 (immune to Sleep) bit is set and the case-3 loop
-- never runs the hit script on him: no Sleep roll. Native-seed per-frame capture
-- (scripts/CaptureWindOfSleepAinGide.lua): 100 setup + 200 on the first spawn tick and nothing else = 300.
function TestWindOfSleep:testImmuneEnemyKnownCapturedSeed()
  luaunit.assertEquals(Magic.simulateWindOfSleep(0xfd5ecce9, 0), 300)
end

-- 20 injected seeds vs the immune enemy, measured like testValidatedSeeds: 300 + 4 per life roll of 0
-- (300-304 here), all matched exactly.
function TestWindOfSleep:testValidatedSeedsImmuneEnemy()
  local cases = {
    { 0x58dbd149, 304 },
    { 0xb4a56396, 304 },
    { 0xf0289ce7, 300 },
    { 0x9cfbae39, 300 },
    { 0x7d3feff7, 308 },
    { 0x3101a6f1, 304 },
    { 0x6ac77c90, 304 },
    { 0xdd33e45d, 304 },
    { 0x67651ec6, 300 },
    { 0x3a8d3d5a, 300 },
    { 0x70289ce7, 300 },
    { 0x10de13c5, 300 },
    { 0x0d1a95a6, 300 },
    { 0x4c3e8ca5, 300 },
    { 0xc47f8042, 312 },
    { 0xa34f3f18, 300 },
    { 0xa059d79a, 300 },
    { 0x87d3da0d, 304 },
    { 0x4289e502, 300 },
    { 0x2d6210d6, 300 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Magic.simulateWindOfSleep(seed, 0), expected,
      string.format("seed 0x%08x", seed))
  end
end

os.exit(luaunit.LuaUnit.run())
