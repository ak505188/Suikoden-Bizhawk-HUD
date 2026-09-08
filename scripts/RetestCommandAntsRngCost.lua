-- User: "Retest it. Queen Ant's Command Ants is essentially a dead move, but I still need to know
-- if it pushed RNG." Confirms whether the CommandAnts branch consumes any Address.RNG steps
-- beyond the single shared move-selection roll, even though (per the SPD-guarantee finding) it
-- finds zero eligible ants and does nothing observable.
--
-- Drives QueenAnt.State's own round 1 (confirmed CommandAnts from the native seed) and logs
-- Address.RNG at every cursor (BattleState+0xc) transition from queen_ant_command_ants_gate
-- through queen_ant_command_all_ants_attack to queen_ant_own_attack_finish - if RNG is IDENTICAL
-- across that whole span, the branch (beyond the shared 1-roll move-selection) costs 0 RNG.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/RetestCommandAntsRngCost.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/RetestCommandAntsRngCost.json"

local COMMAND_ANTS_GATE = 0x8001107c
local COMMAND_ALL_ANTS_ATTACK = 0x80010edc
local OWN_ATTACK_FINISH = 0x80010e50

local rows = {}

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  BattleRoundInput:confirmRound()

  local prevCursor = nil
  local rngAtGate, rngAtAllAnts, rngAtFinish = nil, nil, nil

  for frame = 0, 300 do
    local cursorRaw = mainmemory.read_u32_le(base + 0xc)
    local rng = mainmemory.read_u32_le(Address.RNG)

    if cursorRaw ~= prevCursor then
      table.insert(rows, { frame = frame, cursor = cursorRaw, rng = rng })
      prevCursor = cursorRaw
      if cursorRaw == COMMAND_ANTS_GATE and rngAtGate == nil then rngAtGate = rng end
      if cursorRaw == COMMAND_ALL_ANTS_ATTACK and rngAtAllAnts == nil then rngAtAllAnts = rng end
      if cursorRaw == OWN_ATTACK_FINISH and rngAtFinish == nil then rngAtFinish = rng end
    end
    emu.frameadvance()
  end

  local f = io.open(OUT, "w")
  f:write(json.encode({
    rows = rows,
    rngAtGate = rngAtGate,
    rngAtAllAnts = rngAtAllAnts,
    rngAtFinish = rngAtFinish,
  }))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write(json.encode({ error = tostring(err), partial = rows }))
  f:close()
end

client.exit()
