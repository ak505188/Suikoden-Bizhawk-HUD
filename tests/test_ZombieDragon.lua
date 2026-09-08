-- Run with: lua5.4 tests/test_ZombieDragon.lua (from the project root)
--
-- Every expected value here was independently confirmed against a live BizHawk capture
-- (savestate + injected RNG seed), not just derived from the simulator itself - see
-- docs/game_mechanics/Battle_Damage_Formula.md's "Zombie Dragon" section and
-- zombie_dragon_ai_select_target_and_move's own Ghidra plate comment (enemy_ai_overlay.bin @
-- 0x80012968) for the full derivation.

package.path = package.path .. ";./?.lua"

local luaunit = require "tests.luaunit"
local ZombieDragon = require "lib.Enemies.ZombieDragon"

TestZombieDragonMoveSelection = {}

-- scripts/CaptureEnemyMoveResults.lua's 10-seed capture for ZombieDragonT2.State (round
-- counter 2, standard 3-front-row formation). IMPORTANT: the `seed` column here is NOT the
-- raw seed that script injects at savestate load - it's the RNG state at the exact frame
-- Zombie Dragon's own turn begins (captured live via scripts/TraceZombieDragonMove.lua),
-- since other party members take their own turns first that round, each consuming their own
-- rand() calls - matching simulateMoveSelection's own convention (and every other simulate<X>
-- in this project) of starting right at the decision's own first roll, not at the top of the
-- whole turn/battle.
function TestZombieDragonMoveSelection:testValidatedSeeds()
  local cases = {
    { seed = 0xe2319ac4, move = "FireBreath" },              -- orig battle seed 0x00000001
    { seed = 0x4ea86fa7, move = "Attack", slot = 0 },         -- orig 0x12345678
    { seed = 0xb50f7e8a, move = "Attack", slot = 0 },         -- orig 0xdeadbeef
    { seed = 0x229818a5, move = "Attack", slot = 0 },         -- orig 0xcafebabe
    { seed = 0xa2200e93, move = "FireBreath" },               -- orig 0x5eed1234
    { seed = 0xa429e13c, move = "Attack", slot = 0 },         -- orig 0x99999999
    { seed = 0xb3abcf9e, move = "FireBreath" },               -- orig 0x33333333
    { seed = 0x689cf2da, move = "Attack", slot = 2 },         -- orig 0x0000ffff
    { seed = 0xb8d71f14, move = "FireBreath" },               -- orig 0x11111111
    { seed = 0xb6417759, move = "FireBreath" },               -- orig 0x22222222
  }
  for _, case in ipairs(cases) do
    local move, target = ZombieDragon.simulateMoveSelection(case.seed, 3, 2)
    luaunit.assertEquals(move, case.move, string.format("seed 0x%08x move", case.seed))
    if case.move == "Attack" then
      luaunit.assertEquals(target - 1, case.slot, string.format("seed 0x%08x target", case.seed))
    end
  end
end

-- Round 1 is a distinct branch (Fire Breath guaranteed, zero extra roll beyond the target
-- scan) - not exercised by the round-2 capture above, so pinned separately against the
-- decompile's own documented behavior (zombie_dragon_ai_select_target_and_move: `if
-- (roundCounter == 1) { always FireBreath, no move roll }`).
function TestZombieDragonMoveSelection:testRoundOneGuaranteedFireBreath()
  local move, target, seed, calls = ZombieDragon.simulateMoveSelection(0xe2319ac4, 3, 1)
  luaunit.assertEquals(move, "FireBreath")
  luaunit.assertEquals(target, nil)
  luaunit.assertEquals(calls, 1) -- immediate accept, no move-choice roll on round 1
end

os.exit(luaunit.LuaUnit.run())
