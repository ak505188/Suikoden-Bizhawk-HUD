-- Exercises the full pipeline for all 6 living party members at once, not just one character
-- overridden while the rest auto-attack: enumerate every character's legal actions
-- (lib.ActionEnumerator, with McDohl's known story-lock applied - see
-- docs/game_mechanics/Scripted_Battle_Actions.md), hand-pick one legal action per character to
-- exercise every ActionType at least once, apply ALL 6 via lib.BattleRoundInput, confirm the
-- round, and report what actually executed plus HP before/after.
--
-- USAGE: edit BASE_SAVE below, run via
--   scripts/spawn-headless-emuhawk.sh scripts/SimulateFullPartyRound.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"
local ActionEnumerator = require "lib.ActionEnumerator"
local BattleRoundInput = require "lib.BattleRoundInput"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/ZombieDragonStart.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/SimulateFullPartyRound.txt"

local lines = {}
local function log(s) table.insert(lines, s) end
local function sanitize(addr) return addr & 0x1fffff end

local ActionTypeNames = { [0] = "Attack", [1] = "Defend", [2] = "Rune", [3] = "Item", [4] = "Unite" }

-- Finds the first action in `actions` matching actionType (and, if given, slot). Used below
-- to hand-pick one legal action per character from the enumerator's own output, rather than
-- inventing anything not actually confirmed legal.
local function findAction(actions, actionType, slot)
  for _, a in ipairs(actions) do
    if a[1] == actionType and (slot == nil or a[2] == slot) then return a end
  end
  return nil
end

local function dumpState(tag, ctx)
  local base = ctx.Base
  local currentActor = memory.read_u32_le(base + 0x8)
  log(string.format("[%s] currentActor=%d", tag, currentActor))
  for idx = 1, ctx.TotalCombatants do
    local rec = base + 0xb40 + idx * 0x54
    local hp = memory.read_u16_le(rec + 0x12)
    local hpMax = memory.read_u16_le(rec + 0x10)
    local tag_ = memory.read_u8(rec + 0x46)
    local aType = memory.read_u8(rec + 0x47)
    local slot = memory.read_u8(rec + 0x48)
    local target = memory.read_u8(rec + 0x49)
    log(string.format("  actor%d hp=%d/%d ActionTag=%d ActionType=%s slot=%d target=%d",
      idx, hp, hpMax, tag_, ActionTypeNames[aType] or tostring(aType), slot, target))
  end
end

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)
  for i = 1, 200 do emu.frameadvance() end -- into BATTLE gamestate, struct populated

  -- McDohl (actor 3) only has his Lv1 spell story-unlocked in this battle - see
  -- lib/ActionEnumerator.lua's enumerateRune comment on why this is a caller-supplied
  -- override rather than something auto-detected.
  local lockedLevelsByActor = { [3] = { [2] = true, [3] = true } }
  local perActor, ctx = ActionEnumerator:enumerateRound(lockedLevelsByActor)
  if not perActor then
    log("ERROR enumerating round: " .. tostring(ctx))
    return
  end

  log("=== Before round ===")
  dumpState("before", ctx)

  -- Hand-pick one legal action per character, deliberately exercising every ActionType at
  -- least once across the party (all chosen from the enumerator's own confirmed-legal list,
  -- not invented):
  --   actor1 Viktor : Attack the dragon
  --   actor2 Gremio : Item (Medicine) on actor5 (Camille, lowest HP)
  --   actor3 McDohl : Rune slot1 (Deadly Fingertips) on the dragon
  --   actor4 Cleo   : Rune slot2 (Firestorm, AOE - no specific target)
  --   actor5 Camille: Defend
  --   actor6 Tai Ho : Attack the dragon
  local chosen = {
    [1] = findAction(perActor[1], ActionEnumerator.ActionType.ATTACK),
    [2] = findAction(perActor[2], ActionEnumerator.ActionType.ITEM),
    [3] = findAction(perActor[3], ActionEnumerator.ActionType.RUNE, 1),
    [4] = findAction(perActor[4], ActionEnumerator.ActionType.RUNE, 2),
    [5] = findAction(perActor[5], ActionEnumerator.ActionType.DEFEND),
    [6] = findAction(perActor[6], ActionEnumerator.ActionType.ATTACK),
  }
  -- Prefer targeting actor5 (Camille) with Gremio's item, if that specific target is legal;
  -- otherwise fall back to whatever findAction already picked.
  for _, a in ipairs(perActor[2]) do
    if a[1] == ActionEnumerator.ActionType.ITEM and a[3] == 5 then chosen[2] = a; break end
  end

  log("\n=== Chosen actions (one per character, from the enumerator's own legal list) ===")
  for idx = 1, 6 do
    local a = chosen[idx]
    if not a then
      log(string.format("actor%d: ERROR - no matching legal action found", idx))
    else
      log(string.format("actor%d: %s slot=%d target=%d", idx, ActionTypeNames[a[1]], a[2], a[3]))
    end
  end

  local base = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not base then
    log("ERROR: round-start menu never became ready")
    return
  end

  for idx = 1, 6 do
    local a = chosen[idx]
    if a then
      BattleRoundInput:setAction(idx, a[1], a[2], a[3])
    end
  end

  BattleRoundInput:confirmRound()

  -- Checkpoint every 200 frames for a while, to see whether the round is just slow
  -- (animation durations) or genuinely stalled (e.g. a dismiss-needed message box our tap()
  -- calls never simulate input for).
  for i = 1, 15 do
    for j = 1, 200 do emu.frameadvance() end
    log(string.format("\n=== checkpoint %d (%d frames after confirm) ===", i, i * 200))
    dumpState(string.format("checkpoint_%d", i), ctx)
  end
end)

if not ok then
  log("ERROR: " .. tostring(err))
end

local f = io.open(OUT, "w")
f:write(table.concat(lines, "\n"))
f:close()

client.exit()
