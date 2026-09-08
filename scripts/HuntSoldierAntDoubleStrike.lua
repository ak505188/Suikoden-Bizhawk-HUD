-- Live-validate Soldier Ant's own move-choice threshold (~77% Attack / ~23% DoubleStrike,
-- soldier_ant_ai_select_target_and_move 0x800106b0) and hunt for a live DoubleStrike instance -
-- never observed live yet, only read from the decompile. Every ant turn observed so far
-- (VerifyAntCommandAttribution.lua, 4 samples) happened to land on Attack.
--
-- Drives many rounds via Free Will, watching every combatant's own CURRENT_ACTOR (+0x8) turn: once
-- an ant slot (6/7/8) becomes CURRENT_ACTOR and its own combatant_rec+0x50 continuation pointer
-- becomes non-zero, records which function it resolved to (soldier_ant_special_double_strike =
-- 0x80010524 vs the generic apply_uncovered_attack_damage-family address), plus the RNG state at
-- that moment and the target/DEF, so damage can be validated afterward if a DoubleStrike shows up.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/HuntSoldierAntDoubleStrike.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local Gamestate = require "lib.Enums.Gamestate"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/HuntSoldierAntDoubleStrike.json"
local DOUBLE_STRIKE = 0x80010524
local ROUNDS = 8
local FRAMES_PER_ROUND = 4500

local sightings = {}

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local seenCont = { [6] = false, [7] = false, [8] = false }
  local lastCurActor = nil

  local function traceFrames(n)
    for _ = 1, n do
      local curActor = mainmemory.read_u32_le(base + 0x8)
      if curActor ~= lastCurActor then
        for _, i in ipairs({ 6, 7, 8 }) do seenCont[i] = false end
        lastCurActor = curActor
      end
      if curActor == 6 or curActor == 7 or curActor == 8 then
        local rec = base + 0xb40 + curActor * 0x54
        local cont = mainmemory.read_u32_le(rec + 0x50)
        if cont ~= 0 and not seenCont[curActor] then
          seenCont[curActor] = true
          local targetIdx = mainmemory.read_u8(rec + 0x49)
          local targetDef = targetIdx >= 1 and targetIdx <= 5
            and mainmemory.read_u16_le(base + 0xb40 + targetIdx * 0x54 + 0x32) or nil
          table.insert(sightings, {
            ant = curActor,
            cont = cont,
            isDoubleStrike = (cont == DOUBLE_STRIKE),
            rng = mainmemory.read_u32_le(Address.RNG),
            targetIdx = targetIdx,
            targetDef = targetDef,
          })
        end
      end
      emu.frameadvance()
    end
  end

  for round = 1, ROUNDS do
    local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
    if not newBase then break end
    BattleRoundInput:confirmRound()
    traceFrames(FRAMES_PER_ROUND)
    if mainmemory.read_u8(Address.GAMESTATE) ~= Gamestate.BATTLE then break end
  end

  local f = io.open(OUT, "w")
  f:write(json.encode(sightings))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write(json.encode({ error = tostring(err), partial = sightings }))
  f:close()
end

client.exit()
