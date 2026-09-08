-- Check the user's hypothesis: "Soldier ants are faster than Queen Ant (SPD 22 vs 20) - could
-- it be running its command-ants attack after the ants have already gone?"
--
-- Turn_Order.md documents +0x1264 (nRollGateCountdown) as the SHARED countdown
-- battle_advance_turn decrements every tick before picking the next actor (highest SPD*10+jitter
-- among everyone with ActionTag==0) - and Queen Ant's own AI (queen_ant_ai_self_heal_and_select_
-- move/_command_ants_gate/_command_all_ants_attack) directly resets/decrements/re-arms this SAME
-- field as part of her own gating. If her AI holds that field low/zero throughout her own
-- decision window, the shared "pick next actor" roll may never get a chance to select anyone
-- else (including the faster ants) until she's done - meaning the ants wouldn't actually have
-- taken an independent turn yet when she commands them, despite their higher raw SPD.
--
-- Traces: +0x1264 (roll-gate countdown), +0x8 (CURRENT_ACTOR), +0x3420 (PENDING_INDEX), each
-- ant's own ActionTag (combatant_rec+0x46) and busy (AI-struct+5), and each combatant's own
-- bAnimTargetIdx (AI-struct+4) - so if a specific ant DOES get selected as CURRENT_ACTOR and take
-- its own independent turn, we'll see it directly (not just infer from HP/busy timing).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/TraceQueenAntTurnOrder.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceQueenAntTurnOrder.json"
local NUM_COMBATANTS = 9

local rows = {}

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local function readState()
    local actionTag = {}
    local busy = {}
    for i = 1, NUM_COMBATANTS do
      actionTag[i] = mainmemory.read_u8(base + 0xb40 + i * 0x54 + 0x46)
      busy[i] = mainmemory.read_u8(base + 0x50 + i * 0x8c + 5)
    end
    return {
      rollGate = mainmemory.read_u32_le(base + 0x1264),
      currentActor = mainmemory.read_u32_le(base + 0x8),
      pendingIndex = mainmemory.read_u32_le(base + 0x3420),
      cursor = mainmemory.read_u32_le(base + 0xc),
      actionTag = actionTag,
      busy = busy,
    }
  end

  local prev = nil
  local function changed(a, b)
    if a.rollGate ~= b.rollGate or a.currentActor ~= b.currentActor
      or a.pendingIndex ~= b.pendingIndex or a.cursor ~= b.cursor then return true end
    for i = 1, NUM_COMBATANTS do
      if a.actionTag[i] ~= b.actionTag[i] or a.busy[i] ~= b.busy[i] then return true end
    end
    return false
  end

  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  BattleRoundInput:confirmRound()

  for frame = 0, 4200 do
    local cur = readState()
    if prev == nil or changed(cur, prev) then
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
