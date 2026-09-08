-- Example/validation script for lib/BattleRoundInput.lua: loads a savestate positioned at the
-- very start of a battle, picks Free Will (skips per-character command/target navigation
-- entirely - the AI populates every living party member's action in one shot), overrides
-- whichever party members the caller cares about, confirms the round, and reports each
-- combatant's HP before/after. Only 2 simulated taps total, regardless of party size.
--
-- USAGE: edit BASE_SAVE/PARTY_COUNT/ACTIONS below, run via
--   scripts/spawn-headless-emuhawk.sh scripts/SimulateZombieDragonRound.lua
--
-- See docs/game_mechanics/Scripted_Battle_Actions.md for the full investigation this is
-- built from, and modules/RNG/submodules/Combat/ActionEditMenu.lua for the live-editing menu
-- version of the same underlying write (combatant_rec+0x47/0x48/0x49).

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/ZombieDragonStart.State"
local PARTY_COUNT = 6
local DRAGON_ACTOR = 7

-- Sparse, 1-indexed array of {actionType, abilitySlot, target} overrides - only actor 1
-- (Viktor) is overridden here (to Defend); actors 2-6 are left nil, keeping whatever Free
-- Will's AI already picked for them. ActionType: 0=Attack, 1=Defend, 2=Rune, 3=Item, 4=Unite.
local ACTIONS = {
  [1] = { 1, 0, 0 }, -- Viktor: Defend
}

local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/SimulateZombieDragonRound.txt"
local lines = {}
local function log(s) table.insert(lines, s) end

local function readHp(base, idx)
  local rec = base + 0xb40 + idx * 0x54
  return memory.read_u16_le(rec + 0x12), memory.read_u16_le(rec + 0x10)
end

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)

  local base = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not base then
    log("ERROR: round-start menu never became ready")
  else
    log("HP before:")
    for idx = 1, PARTY_COUNT + 1 do
      local cur, max = readHp(base, idx)
      log(string.format("  actor%d %d/%d", idx, cur, max))
    end

    BattleRoundInput:setActions(ACTIONS)
    BattleRoundInput:confirmRound()

    -- Let the round play out. No completion flag is polled here (a real sim script would poll
    -- e.g. every combatant's ActionTag==1 or a settle-detector, see
    -- docs/game_mechanics/Spell_RNG_Tracing_Methodology.md's gotchas) - fixed frame budget
    -- only, for this example.
    for i = 1, 900 do emu.frameadvance() end

    log("HP after (900 frames later):")
    for idx = 1, PARTY_COUNT + 1 do
      local cur, max = readHp(base, idx)
      log(string.format("  actor%d %d/%d", idx, cur, max))
    end
  end
end)

if not ok then
  log("ERROR: " .. tostring(err))
end

local f = io.open(OUT, "w")
f:write(table.concat(lines, "\n"))
f:close()

client.exit()
