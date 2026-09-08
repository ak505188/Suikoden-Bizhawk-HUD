-- Run several full rounds on QueenAnt.State (start of the Mt. Seifu Queen Ant fight, no actions
-- taken - user-supplied), leaving every party action to Free Will/AI, to catch Queen Ant's
-- reported-but-undocumented AoE Earth attack ("looks similar to Voice of Earth", hits all
-- characters). Logs per-round HP deltas for every party member plus RNG before/after, so an
-- all-party simultaneous HP drop in one round (vs a single-target drop from an ant, vs no drop
-- at all from Queen Ant's previously-assumed "visual only" attack) identifies which round/branch
-- is the AoE.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CaptureQueenAntRounds.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CaptureQueenAntRounds.json"
local ROUNDS = 12

local results = {}

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  for i = 1, 60 do emu.frameadvance() end

  for r = 1, ROUNDS do
    local result, reason = BattleRoundInput:runTurn({})
    if not result then
      table.insert(results, { round = r, error = reason })
      break
    end
    table.insert(results, result)
    if result.Outcome ~= "ongoing" then break end
  end

  local f = io.open(OUT, "w")
  f:write(json.encode(results))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write(json.encode({ error = tostring(err), partial = results }))
  f:close()
end

client.exit()
