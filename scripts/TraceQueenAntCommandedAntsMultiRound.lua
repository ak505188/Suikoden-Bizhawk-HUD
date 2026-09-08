-- Extend TraceQueenAntCommandedAnts.lua across MULTIPLE rounds to gather more CommandAnts
-- samples, checking the user's hypothesis: "Ant has 2 different attacks... perhaps that's the
-- 2nd roll you saw?" - i.e. does the commanded-ant damage formula ever deviate from the plain
-- single-roll calc_damage prediction (e.g. show a doubled result, matching
-- soldier_ant_special_double_strike's shape), which would mean a hidden move-choice is folded
-- into ant_commanded_attack_damage after all, contradicting queen_ant_command_all_ants_attack's
-- own decompile (which unconditionally installs the same continuation function every time).
--
-- Every time cursor==COMMAND_ALL_ANTS_ATTACK, snapshot every commanded ant's own target
-- (bAnimTargetIdx) AND every party member's live DEF at that instant, so later damage events can
-- be attributed and checked against the plain formula without needing to hand-pick per-round
-- constants.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/TraceQueenAntCommandedAntsMultiRound.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local Gamestate = require "lib.Enums.Gamestate"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceQueenAntCommandedAntsMultiRound.json"
local COMMAND_ALL_ANTS_ATTACK = 0x80010edc
local NUM_COMBATANTS = 9
local NUM_PARTY = 5
local ROUNDS = 6
local FRAMES_PER_ROUND = 4500

local dispatchSnapshots = {}
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

  local function readDef()
    local def = {}
    for i = 1, NUM_PARTY do
      def[i] = mainmemory.read_u16_le(base + 0xb40 + i * 0x54 + 0x32)
    end
    return def
  end

  local function readAntTargets()
    return {
      ant6 = mainmemory.read_u8(base + 0x50 + 6 * 0x8c + 4),
      ant7 = mainmemory.read_u8(base + 0x50 + 7 * 0x8c + 4),
      ant8 = mainmemory.read_u8(base + 0x50 + 8 * 0x8c + 4),
    }
  end

  local lastDispatchCursor = nil
  local prevHp, prevCursor, prevRng = nil, nil, nil
  local globalFrame = 0

  local function traceFrames(n)
    for _ = 1, n do
      local cursor = mainmemory.read_u32_le(base + 0xc)
      local rng = mainmemory.read_u32_le(Address.RNG)
      local hp = readHp()

      if cursor == COMMAND_ALL_ANTS_ATTACK and lastDispatchCursor ~= COMMAND_ALL_ANTS_ATTACK then
        table.insert(dispatchSnapshots, {
          frame = globalFrame,
          rng = rng,
          antTargets = readAntTargets(),
          partyDef = readDef(),
        })
      end
      lastDispatchCursor = cursor

      local changed = prevHp == nil or cursor ~= prevCursor or rng ~= prevRng
      if not changed then
        for i = 1, NUM_COMBATANTS do
          if hp[i] ~= prevHp[i] then changed = true break end
        end
      end
      if changed then
        table.insert(rows, { frame = globalFrame, rng = rng, cursor = cursor, hp = hp })
        prevHp, prevCursor, prevRng = hp, cursor, rng
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
  f:write(json.encode({ dispatchSnapshots = dispatchSnapshots, rows = rows }))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write(json.encode({ error = tostring(err), dispatchSnapshots = dispatchSnapshots, partial = rows }))
  f:close()
end

client.exit()
