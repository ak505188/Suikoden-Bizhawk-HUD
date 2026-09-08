-- Live validation of lib/Enemies/QueenAnt.lua against QueenAnt.State (start-of-fight savestate).
-- Watches BattleState+0xc (the single global "current decision-node" cursor - CONFIRMED shared
-- by queen_ant_ai_self_heal_and_select_move/_own_attack_windup/_command_ants_gate, all of which
-- write to this SAME param_1+0xc field, not a per-combatant slot) alongside Address.RNG and every
-- combatant's HP + every party member's bBusyMutex flag (AI-struct+5), logging a row whenever any
-- of these changes. This lets us:
--   1. Find the exact RNG value immediately before each move-selection roll (the frame right
--      before the cursor transitions away from queen_ant_ai_self_heal_and_select_move) and which
--      branch it produced (which address the cursor becomes), to bit-exact validate
--      QueenAnt.simulateMoveSelection's 51%/49% threshold.
--   2. Watch each party member's bBusyMutex flip to confirm the commanded-ant cascade mechanism
--      (busy flag set as a side effect of being hit, excluding that target from the next
--      commanded ant's scan).
--   3. Correlate HP changes with which branch just fired, to distinguish AoeEarth (all living
--      party members hit) from CommandAnts (a subset, decreasing index order) rounds.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/TraceQueenAntMoveSelection.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local Gamestate = require "lib.Enums.Gamestate"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceQueenAntMoveSelection.json"
local FRAMES_PER_ROUND = 4000
local ROUNDS = 4
local NUM_COMBATANTS = 9 -- 5 party + 3 ants + Queen Ant (confirmed via CaptureQueenAntRounds.lua)
local NUM_PARTY = 5

local rows = {}

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local function readState()
    local hp = {}
    for i = 1, NUM_COMBATANTS do
      hp[i] = mainmemory.read_u16_le(base + 0xb40 + i * 0x54 + 0x12)
    end
    local busy = {}
    for i = 1, NUM_PARTY do
      busy[i] = mainmemory.read_u8(base + 0x50 + i * 0x8c + 5)
    end
    return {
      rng = mainmemory.read_u32_le(Address.RNG),
      cursor = mainmemory.read_u32_le(base + 0xc),
      hp = hp,
      busy = busy,
    }
  end

  local prev = nil
  local function changed(a, b)
    if a.rng ~= b.rng or a.cursor ~= b.cursor then return true end
    for i = 1, NUM_COMBATANTS do
      if a.hp[i] ~= b.hp[i] then return true end
    end
    for i = 1, NUM_PARTY do
      if a.busy[i] ~= b.busy[i] then return true end
    end
    return false
  end

  local globalFrame = 0
  local function traceFrames(n)
    for _ = 1, n do
      local cur = readState()
      if prev == nil or changed(cur, prev) then
        cur.frame = globalFrame
        table.insert(rows, cur)
        prev = cur
      end
      emu.frameadvance()
      globalFrame = globalFrame + 1
    end
  end

  -- Drive the round the same way BattleRoundInput:runTurn does (Free Will, no overrides - let
  -- every combatant's own AI, including Queen Ant's, decide), but trace every frame ourselves
  -- instead of blindly waiting, so we capture the RNG/cursor/HP/busy transitions in between.
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
