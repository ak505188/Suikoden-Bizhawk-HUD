-- Re-run QueenAnt.State's round 1 (CommandAnts) + round 2 (AoeEarth) exactly as
-- TraceQueenAntMoveSelection.lua did, but this time boost party HP right at the moment Queen
-- Ant's own attack reaches queen_ant_own_attack_wait_and_arm (cursor==0x80010e0c) - AFTER
-- everything that already happened this run (round 1's CommandAnts damage, the earlier
-- ant-inflicted death of party slot 2) has played out identically, but BEFORE the AoE's own
-- damage rolls fire (~230 frames later, confirmed stable/idle in between via the earlier trace).
--
-- FIRST ATTEMPT boosted everyone to a flat 9999 - this overshot every target's own real HPMax and
-- triggered some OTHER "clamp current HP to max" correction that overwrote the AoE's own damage
-- application entirely (all 4 targets ended up EXACTLY at their own HPMax, not HPMax-minus-
-- damage - an artifact of putting current>max out-of-spec, not real data). CORRECTED: boost each
-- target to (their own real HPMax - 1) instead, staying in-spec so no such clamp fires, while
-- still comfortably surviving the AoE (predicted damage for both previously-lethal targets was
-- well under their own max HP).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckQueenAntAoeDamageNoDeath.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local Gamestate = require "lib.Enums.Gamestate"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckQueenAntAoeDamageNoDeath.json"
local WAIT_AND_ARM = 0x80010e0c
local NUM_COMBATANTS = 9
local NUM_PARTY = 5

local rows = {}
local boosted = false
local boostFrame = nil
local hpAtBoost = nil

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local function readHp()
    local hp = {}
    for i = 1, NUM_COMBATANTS do
      hp[i] = mainmemory.read_u16_le(base + 0xb40 + i * 0x54 + 0x12)
    end
    return hp
  end

  local function readHpMax()
    local hpMax = {}
    for i = 1, NUM_COMBATANTS do
      hpMax[i] = mainmemory.read_u16_le(base + 0xb40 + i * 0x54 + 0x10)
    end
    return hpMax
  end

  local prevHp, prevCursor, prevRng = nil, nil, nil
  local function traceFrames(n)
    for _ = 1, n do
      local cursor = mainmemory.read_u32_le(base + 0xc)
      local rng = mainmemory.read_u32_le(Address.RNG)
      local hp = readHp()

      if not boosted and cursor == WAIT_AND_ARM then
        hpAtBoost = readHp()
        local hpMax = readHpMax()
        for i = 1, NUM_PARTY do
          if hpAtBoost[i] > 0 then
            mainmemory.write_u16_le(base + 0xb40 + i * 0x54 + 0x12, hpMax[i] - 1)
          end
        end
        boosted = true
        boostFrame = true
        hp = readHp()
      end

      local changed = prevHp == nil or cursor ~= prevCursor or rng ~= prevRng
      if not changed then
        for i = 1, NUM_COMBATANTS do
          if hp[i] ~= prevHp[i] then changed = true break end
        end
      end
      if changed then
        table.insert(rows, { rng = rng, cursor = cursor, hp = hp })
        prevHp, prevCursor, prevRng = hp, cursor, rng
      end
      emu.frameadvance()
    end
  end

  for round = 1, 2 do
    local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
    if not newBase then break end
    BattleRoundInput:confirmRound()
    traceFrames(4500)
    if mainmemory.read_u8(Address.GAMESTATE) ~= Gamestate.BATTLE then break end
  end

  local f = io.open(OUT, "w")
  f:write(json.encode({ boosted = boosted, hpAtBoost = hpAtBoost, rows = rows }))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write(json.encode({ error = tostring(err), partial = rows }))
  f:close()
end

client.exit()
