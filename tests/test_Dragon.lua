-- Run with: lua5.4 tests/test_Dragon.lua (from the project root)
--
-- Every expected value here was independently confirmed against a live BizHawk capture
-- (savestate + injected RNG seed), not just derived from the simulator itself - see
-- docs/game_mechanics/Battle_Damage_Formula.md's "Dragon's move selection" and "How much RNG
-- does a Lightning attack advance?" sections for the full derivation and validation
-- methodology.

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local RNGLib = require "lib.RNG"
local Dragon = require "lib.Enemies.Dragon"

TestDragonMoveSelection = {}

-- 50 live-captured seeds (scripts/SweepDragonMove.lua, TurnOrderRNGCall.State - a standard
-- 3-front-row formation, so numCandidates=3 throughout) - a third, independent sweep on top of
-- two earlier batches (12 + 30 seeds, not preserved on disk) that combined for a 92/92 perfect
-- record overall. Target is recorded as the absolute party slot Dragon's Lightning hit (0-2,
-- since the front-row candidates are formation slots 0/1/2 in order) - simulateMoveSelection's
-- own 1-indexed target is slot-1 for comparison; FireBreath ignores target entirely (AOE).
function TestDragonMoveSelection:testValidatedSeeds()
  local cases = {
    { seed = 0x6aa79987, move = "FireBreath" },
    { seed = 0xbb91433a, move = "Lightning", slot = 0 },
    { seed = 0x029a7245, move = "FireBreath" },
    { seed = 0xd1f6f86c, move = "Lightning", slot = 0 },
    { seed = 0xd340bbcd, move = "Lightning", slot = 0 },
    { seed = 0xcd8778e7, move = "Lightning", slot = 0 },
    { seed = 0x4c73a942, move = "FireBreath" },
    { seed = 0xdaea58ba, move = "Lightning", slot = 0 },
    { seed = 0x5e503a67, move = "Lightning", slot = 0 },
    { seed = 0xee897110, move = "FireBreath" },
    { seed = 0x3193ca54, move = "Lightning", slot = 1 },
    { seed = 0x452ec40a, move = "FireBreath" },
    { seed = 0x90e5e945, move = "FireBreath" },
    { seed = 0x6facaa50, move = "FireBreath" },
    { seed = 0x29645f8b, move = "Lightning", slot = 2 },
    { seed = 0x5f811cb9, move = "Lightning", slot = 0 },
    { seed = 0x1fcff454, move = "Lightning", slot = 0 },
    { seed = 0xdfc9e3b1, move = "FireBreath" },
    { seed = 0x6ed4e94b, move = "FireBreath" },
    { seed = 0x42d6cb5c, move = "FireBreath" },
    { seed = 0x8fe46024, move = "FireBreath" },
    { seed = 0xa091250e, move = "Lightning", slot = 1 },
    { seed = 0x2ca1c789, move = "Lightning", slot = 0 },
    { seed = 0x9c9cea0c, move = "FireBreath" },
    { seed = 0x8d9fe5b9, move = "FireBreath" },
    { seed = 0x2fd2b7a4, move = "FireBreath" },
    { seed = 0x5adad121, move = "Lightning", slot = 0 },
    { seed = 0xbcf74d7a, move = "FireBreath" },
    { seed = 0xf543bbcf, move = "Lightning", slot = 2 },
    { seed = 0xbb9d58e4, move = "FireBreath" },
    { seed = 0x175f0cd2, move = "FireBreath" },
    { seed = 0x87f26aee, move = "Lightning", slot = 1 },
    { seed = 0xfa882692, move = "Lightning", slot = 1 },
    { seed = 0xbc428d42, move = "FireBreath" },
    { seed = 0x6980a81f, move = "FireBreath" },
    { seed = 0x95c5fb98, move = "FireBreath" },
    { seed = 0x8101e89a, move = "FireBreath" },
    { seed = 0x2aa4857e, move = "Lightning", slot = 0 },
    { seed = 0x25ece845, move = "FireBreath" },
    { seed = 0x34a9af41, move = "Lightning", slot = 0 },
    { seed = 0xb80e3b0d, move = "Lightning", slot = 2 },
    { seed = 0x13ed748b, move = "FireBreath" },
    { seed = 0x30a1f6d5, move = "Lightning", slot = 1 },
    { seed = 0xd64a3ce0, move = "FireBreath" },
    { seed = 0x57708107, move = "FireBreath" },
    { seed = 0x527122dc, move = "FireBreath" },
    { seed = 0x06057c82, move = "FireBreath" },
    { seed = 0x7576714a, move = "Lightning", slot = 2 },
    { seed = 0x56eaa301, move = "FireBreath" },
    { seed = 0x06e0f458, move = "FireBreath" },
  }
  for _, case in ipairs(cases) do
    local move, target = Dragon.simulateMoveSelection(case.seed, 3)
    luaunit.assertEquals(move, case.move, string.format("seed 0x%08x move", case.seed))
    if case.move == "Lightning" then
      luaunit.assertEquals(target - 1, case.slot, string.format("seed 0x%08x target", case.seed))
    end
  end
end

TestDragonLightning = {}

-- Not a player spell - Dragon's own enemy-AI Lightning attack (see simulateLightning's own
-- comment above and dragon_lightning_tick_state_machine's plate comment, dragon_overlay.bin @
-- 0x80013690, for the full derivation). Unlike every simulate<Spell> in lib/Magic.lua,
-- simulateLightning's seed parameter is NOT the battle's live seed at move-selection time -
-- it's the RNG state simulateMoveSelection returns once it's resolved to Lightning (i.e. right
-- after Dragon's target-scan-with-retry and Lightning-vs-Fire-Breath move-choice roll have
-- already resolved), matching every simulate<X> function's own convention of starting at the
-- effect's first rand() call. Ground truth was captured via LCG-step-counting (settle the live
-- RNG after the attack fully resolves, then forward-simulate from the seed to find the exact
-- call count that reaches that settled state) rather than per-frame polling, since naive
-- per-frame "did it change" counting undercounts by an order of magnitude when many rand()
-- calls land within a single frame (see scripts/SettleLightningRNG.lua). 16 live-captured seeds
-- across two independent sweeps all match the simulator exactly (0 discrepancies).
function TestDragonLightning:testValidatedSeeds()
  local cases = {
    { 0x9e68560c, 681 },
    { 0x2781e494, 716 },
    { 0xa078995f, 686 },
    { 0x8ff0f2ca, 711 },
    { 0x0a2a285f, 651 },
    { 0x8af157af, 656 },
    { 0x843603c9, 701 },
    { 0x0c815ed7, 711 },
    { 0x08087bfc, 706 },
    { 0x133b08b9, 666 },
    { 0x3f3b291f, 736 },
    { 0xa53cf772, 736 },
    { 0x1ddcd542, 736 },
    { 0x19b260fd, 686 },
    { 0x8312ec9f, 756 },
    { 0x926f56d7, 711 },
  }
  for _, case in ipairs(cases) do
    local seed, expected = case[1], case[2]
    luaunit.assertEquals(Dragon.simulateLightning(seed), expected,
      string.format("seed 0x%08x", seed))
  end
end

TestDragonDamage = {}

-- Both Lightning and Fire Breath's damage formula: MGC-based (`attacker.MGC - target.MGC` via
-- the shared calc_rune_element_attack_damage, the SAME function Zombie Dragon's own Fire
-- Breath uses - see lib/EnemyElementalAttack.lua), NOT ATK-based - confirmed live three ways:
-- the decompile itself reads `wMGC` for both sides; a live memory check of Dragon.State shows
-- her CombatantRec has genuinely distinct ATK=250/MGC=150 (not aliased); and every observed
-- live damage value below matches the MGC-based prediction exactly, while an ATK-based guess
-- (`250 - target.DEF`) would be 3-7x too high. See Dragon.calculateLightningDamage/
-- calculateFireBreathDamage's own comments in lib/Enemies/Dragon.lua for the full derivation,
-- including Fire Breath's own "slot 1" resistance bug (same class as Zombie Dragon's "slot 6").
--
-- The damage roll itself is Dragon.simulateLightning's own LAST rand() call - since
-- simulateLightning's returned call count is already bit-exact validated (TestDragonLightning
-- above), the roll's raw value is recovered by fast-forwarding that many LCG steps from the
-- same starting seed, rather than re-deriving the whole particle simulation just to read one
-- value back out.
local function rollAfterCalls(startSeed, calls)
  local seed = startSeed
  for _ = 1, calls do seed = RNGLib.nextRNG(seed) end
  return RNGLib.getRNG2(seed)
end

local DRAGON_MGC = 150
-- Dragon.State's own 6 party members' MGC, read live (scripts/CheckDragonStats.lua).
local TARGET_MGC = { 86, 51, 40, 67, 65, 42 }

-- 8 live-captured Lightning seeds (scripts/SweepDragonMove.lua's own DragonSweepResults.txt) -
-- 4 landing on slot 0 (whose target has a matching rune, category RESIST-equivalent - see
-- EnemyElementalAttack.RUNE_CATEGORY), 4 on slots 1/2 (no match, full unscaled damage) - both
-- branches matched exactly, 8/8.
function TestDragonDamage:testLightningValidatedSeeds()
  local cases = {
    { seed = 0xbb91433a, slot = 0, category = 4, damage = 30 },
    { seed = 0xd1f6f86c, slot = 0, category = 4, damage = 32 },
    { seed = 0xd340bbcd, slot = 0, category = 4, damage = 31 },
    { seed = 0xcd8778e7, slot = 0, category = 4, damage = 29 },
    { seed = 0x3193ca54, slot = 1, category = nil, damage = 102 },
    { seed = 0x29645f8b, slot = 2, category = nil, damage = 117 },
    { seed = 0xa091250e, slot = 1, category = nil, damage = 93 },
    { seed = 0xf543bbcf, slot = 2, category = nil, damage = 113 },
  }
  for _, case in ipairs(cases) do
    local move, target, postMoveSeed = Dragon.simulateMoveSelection(case.seed, 3, 2)
    luaunit.assertEquals(move, "Lightning", string.format("seed 0x%08x", case.seed))
    local calls = Dragon.simulateLightning(postMoveSeed)
    local roll = rollAfterCalls(postMoveSeed, calls)
    local damage = Dragon.calculateLightningDamage(DRAGON_MGC, TARGET_MGC[case.slot + 1],
      case.category, function() return roll end)
    luaunit.assertEquals(damage, case.damage, string.format("seed 0x%08x damage", case.seed))
  end
end

-- One live-captured Fire Breath seed, all 6 targets - 5/6 matched the plain formula exactly;
-- the 6th (slot 1) only matched once the register-reuse bug's extra halving was included,
-- confirming the bug rather than breaking the formula.
function TestDragonDamage:testFireBreathValidatedSeed()
  local seed = 0x6aa79987
  local observed = { 15, 50, 55, 41, 42, 49 }
  local move, _, postMoveSeed = Dragon.simulateMoveSelection(seed, 3, 2)
  luaunit.assertEquals(move, "FireBreath")
  local rngSeed = postMoveSeed
  for i = 1, 6 do
    rngSeed = RNGLib.nextRNG(rngSeed)
    local roll = RNGLib.getRNG2(rngSeed)
    local damage = Dragon.calculateFireBreathDamage(DRAGON_MGC, TARGET_MGC[i], nil, i,
      function() return roll end)
    luaunit.assertEquals(damage, observed[i], string.format("target slot %d", i - 1))
  end
end

os.exit(luaunit.LuaUnit.run())
