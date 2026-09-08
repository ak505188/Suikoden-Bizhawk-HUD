-- Isolate exactly which ant targets which party member during QueenAnt.State's round 1
-- (CommandAnts branch, confirmed from the savestate's own native seed - reproducible), and
-- validate ant_commanded_attack_damage's formula bit-exact.
--
-- Key insight: play_attack_animation (main.exe 0x800e3820) writes
-- EnemyDataArray[attacker_idx].bAnimTargetIdx = target_idx as part of dispatch - this is a
-- DIRECT, per-attacker record of who it targeted, readable any time after dispatch. No need to
-- infer attribution from timing - just read each ant's own AI-struct+4 field (base+0x50+i*0x8c+4)
-- once queen_ant_command_all_ants_attack has run.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/TraceQueenAntCommandedAnts.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceQueenAntCommandedAnts.json"
local COMMAND_ALL_ANTS_ATTACK = 0x80010edc
local NUM_COMBATANTS = 9
local NUM_PARTY = 5

local rows = {}
local targetSnapshot = nil
local defSnapshot = nil

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

  local function readDef()
    local def = {}
    for i = 1, NUM_PARTY do
      def[i] = mainmemory.read_u16_le(base + 0xb40 + i * 0x54 + 0x32)
    end
    return def
  end

  local function readAntTargets()
    -- bAnimTargetIdx = AI-struct+4, AI-struct base = base+0x50+i*0x8c
    return {
      ant6 = mainmemory.read_u8(base + 0x50 + 6 * 0x8c + 4),
      ant7 = mainmemory.read_u8(base + 0x50 + 7 * 0x8c + 4),
      ant8 = mainmemory.read_u8(base + 0x50 + 8 * 0x8c + 4),
    }
  end

  local prevHp, prevCursor, prevRng = nil, nil, nil
  local function traceFrames(n)
    for _ = 1, n do
      local cursor = mainmemory.read_u32_le(base + 0xc)
      local rng = mainmemory.read_u32_le(Address.RNG)
      local hp = readHp()

      if targetSnapshot == nil and cursor == COMMAND_ALL_ANTS_ATTACK then
        targetSnapshot = readAntTargets()
        defSnapshot = readDef()
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

  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  BattleRoundInput:confirmRound()
  traceFrames(4200)

  local result = {
    antTargets = targetSnapshot,
    partyDef = defSnapshot,
    partyDefAtEnd = readDef(),
    rows = rows,
  }
  local f = io.open(OUT, "w")
  f:write(json.encode(result))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write(json.encode({ error = tostring(err), partial = rows, antTargets = targetSnapshot }))
  f:close()
end

client.exit()
