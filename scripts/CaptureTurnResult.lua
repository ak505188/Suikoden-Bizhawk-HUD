-- Demo/validation for lib.BattleRoundInput:runTurn() - the emulator-side TurnResult capture,
-- the natural counterpart to lib.BattleSnapshot's InitialState capture (see
-- docs/game_mechanics/Scripted_Battle_Actions.md's "InitialState snapshot" section).
--
-- Runs one full round on ZombieDragonStart.State (everyone's action left to Free Will's AI -
-- an empty actions table), then dumps the resulting TurnResult as JSON.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CaptureTurnResult.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local BattleRoundInput = require "lib.BattleRoundInput"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/ZombieDragonStart.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CaptureTurnResult.json"

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  for i = 1, 200 do emu.frameadvance() end

  local result, reason = BattleRoundInput:runTurn({})
  if not result then
    error("runTurn failed: " .. tostring(reason))
  end

  local f = io.open(OUT, "w")
  f:write(json.encode(result))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write("ERROR: " .. tostring(err))
  f:close()
end

client.exit()
