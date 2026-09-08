-- Re-run the SAME deterministic replay as HuntSoldierAntDoubleStrike.lua (identical savestate,
-- identical Free Will rounds - so the same 2 DoubleStrike instances occur: ant6->party slot 2,
-- ant8->party slot 3), but this time boost each target's HP to (their own real HPMax - 1) the
-- instant that ant's own continuation pointer (combatant_rec+0x50) flips to
-- soldier_ant_special_double_strike (0x80010524) - well before the actual damage roll resolves -
-- so the real (unclamped) damage can be read instead of a death-clamped lower bound. Uses the
-- HPMax-1 (not a flat large number) convention already learned the hard way for Queen Ant's own
-- AoE damage capture (a flat 9999 overshoot triggered an unrelated "clamp to max" correction that
-- erased the real damage).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckSoldierAntDoubleStrikeDamage.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local Gamestate = require "lib.Enums.Gamestate"
local json = require "lib.json"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckSoldierAntDoubleStrikeDamage.json"
local DOUBLE_STRIKE = 0x80010524
local ROUNDS = 8
local FRAMES_PER_ROUND = 4500
local NUM_COMBATANTS = 9

local boosted = {} -- ant slot -> true once its target has been boosted
local results = {}
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

  local seenCont = { [6] = false, [7] = false, [8] = false }
  local lastCurActor = nil
  local prevHp, prevRng = nil, nil
  local globalFrame = 0

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
        if cont == DOUBLE_STRIKE and not seenCont[curActor] and not boosted[curActor] then
          seenCont[curActor] = true
          local targetIdx = mainmemory.read_u8(rec + 0x49)
          if targetIdx >= 1 and targetIdx <= 5 then
            local tRec = base + 0xb40 + targetIdx * 0x54
            local hpMax = mainmemory.read_u16_le(tRec + 0x10)
            local hpBefore = mainmemory.read_u16_le(tRec + 0x12)
            local def = mainmemory.read_u16_le(tRec + 0x32)
            -- Doubled damage can exceed the target's OWN real HPMax entirely (confirmed: a
            -- HPMax-1 boost for ant6's first target still died) - raise HPMax itself first, then
            -- set current just under THAT, so current never exceeds max (avoiding the "clamp to
            -- max" bug from boosting current alone past a stale max) while comfortably surviving
            -- any plausible variance on a doubled roll.
            local boostedMax = 300
            mainmemory.write_u16_le(tRec + 0x10, boostedMax)
            mainmemory.write_u16_le(tRec + 0x12, boostedMax - 1)
            boosted[curActor] = true
            table.insert(results, {
              ant = curActor, targetIdx = targetIdx, targetDef = def,
              hpMaxAtBoost = hpMax, hpBeforeBoost = hpBefore, boostedTo = boostedMax - 1,
              frame = globalFrame,
            })
          end
        end
      end

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
  f:write(json.encode({ results = results, rows = rows }))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write(json.encode({ error = tostring(err), results = results, partial = rows }))
  f:close()
end

client.exit()
