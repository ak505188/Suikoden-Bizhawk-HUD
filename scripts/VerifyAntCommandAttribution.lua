-- DEFINITIVE check: were ants 6/7/8 actually eligible (ActionTag==0) when
-- queen_ant_command_all_ants_attack ran in round 1, or had they already acted via their OWN
-- independent turn (soldier_ant_ai_select_target_and_move, which fires earlier since ants have
-- SPD 22 > Queen's SPD 20)? If already ineligible, the damage previously attributed to
-- ant_commanded_attack_damage may actually be the delayed resolution of their OWN independent
-- attacks (via the generic battle_execute_player_attack fallback for the ~77% plain-Attack
-- branch), not a real command from Queen at all.
--
-- Reads, every frame: each ant's ActionTag (combatant_rec+0x46), busy (AI-struct+5), TargetIdx
-- (combatant_rec+0x49 - the field soldier_ant_ai_select_target_and_move itself sets), the shared
-- continuation pointer (combatant_rec+0x50), bAnimTargetIdx (AI-struct+4), and the
-- ant_commanded_attack_damage-specific gate flag (AI-struct+0x40 bit 0x2).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/VerifyAntCommandAttribution.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/VerifyAntCommandAttribution.json"

local rows = {}

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local function readAnt(i)
    local rec = base + 0xb40 + i * 0x54
    local ai = base + 0x50 + i * 0x8c
    return {
      actionTag = mainmemory.read_u8(rec + 0x46),
      targetIdx49 = mainmemory.read_u8(rec + 0x49),
      cont50 = mainmemory.read_u32_le(rec + 0x50),
      busy = mainmemory.read_u8(ai + 5),
      bAnimTarget = mainmemory.read_u8(ai + 4),
      gateFlag40 = mainmemory.read_u16_le(ai + 0x40),
    }
  end

  local prev = nil
  local function snapshot()
    return {
      ant6 = readAnt(6), ant7 = readAnt(7), ant8 = readAnt(8),
      cursor = mainmemory.read_u32_le(base + 0xc),
      hp2 = mainmemory.read_u16_le(base + 0xb40 + 2 * 0x54 + 0x12),
      hp1 = mainmemory.read_u16_le(base + 0xb40 + 1 * 0x54 + 0x12),
      hp3 = mainmemory.read_u16_le(base + 0xb40 + 3 * 0x54 + 0x12),
    }
  end

  local function eq(a, b)
    if a == nil or b == nil then return a == b end
    for k, v in pairs(a) do
      if type(v) == "table" then
        for k2, v2 in pairs(v) do
          if b[k][k2] ~= v2 then return false end
        end
      else
        if b[k] ~= v then return false end
      end
    end
    return true
  end

  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  BattleRoundInput:confirmRound()

  for frame = 0, 300 do
    local cur = snapshot()
    if prev == nil or not eq(cur, prev) then
      cur.frame = frame
      table.insert(rows, cur)
      prev = cur
    end
    emu.frameadvance()
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
