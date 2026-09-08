-- Follow-up to HuntSoldierAntDoubleStrike.lua: same deterministic replay (same savestate, same
-- Free Will rounds), but this time also traces full RNG+HP history so the 2 confirmed
-- DoubleStrike sightings (ant6->slot2 DEF21, ant8->slot3 DEF31) can be correlated with their
-- actual damage application (which happens later, once each ant's own windup bit 0x2 flag sets -
-- the move-choice moment captured previously is NOT the damage-roll moment).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/HuntSoldierAntDoubleStrikeDamage.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local Gamestate = require "lib.Enums.Gamestate"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/HuntSoldierAntDoubleStrikeDamage.json"
local ROUNDS = 8
local FRAMES_PER_ROUND = 4500
local NUM_COMBATANTS = 9

local rows = {}

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

  local prevHp, prevRng = nil, nil
  local globalFrame = 0
  local function traceFrames(n)
    for _ = 1, n do
      local rng = mainmemory.read_u32_le(Address.RNG)
      local hp = readHp()
      local changed = prevHp == nil or rng ~= prevRng
      if not changed then
        for i = 1, NUM_COMBATANTS do
          if hp[i] ~= prevHp[i] then changed = true break end
        end
      end
      if changed then
        table.insert(rows, { frame = globalFrame, rng = rng, hp = hp })
        prevHp, prevRng = hp, rng
      end
      emu.frameadvance()
      globalFrame = globalFrame + 1
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
  f:write(json.encode(rows))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write(json.encode({ error = tostring(err), partial = rows }))
  f:close()
end

client.exit()
