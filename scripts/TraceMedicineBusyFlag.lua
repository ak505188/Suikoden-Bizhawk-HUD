-- Traces exactly what happens to Cleo's busy mutex (enemy_data+5) when McDohl uses Medicine
-- on her, and correlates it against the turn-order roll-gate (+0x1264) and pending/current
-- actor fields, to see whether/how it delays her turn. Cleo is given a real action (Attack,
-- not Defend) so her own turn's timing is observable.
--
-- User-provided setup: ZombieDragon.State, McDohl uses Item(Medicine) on Cleo, Cleo Attacks
-- the Dragon. Actor indices/AbilitySlot are resolved dynamically at runtime (not hardcoded)
-- via ActionEnumerator/Battle.getItemName, since this savestate's formation order isn't yet
-- known from a static read.
--
-- Also registers event.onmemorywrite on Cleo's own busy byte to catch the exact PC that
-- writes it - memory.registerwrite doesn't exist in this BizHawk build (confirmed via
-- scripts/CheckMemoryHookAPI.lua's dump), event.onmemorywrite does.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local ActionEnumerator = require "lib.ActionEnumerator"
local Battle = require "lib.Battle"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/ZombieDragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceMedicineBusyFlag.txt"
local MAX_FRAMES = 400

local HERO_ID = 8   -- McDohl
local CLEO_ID = 1

-- Writes and flushes immediately (not just at the end) so a killed/closed process still
-- leaves a readable partial log - the previous two runs left nothing on disk because the
-- only write happened after the full frame loop, and the process got killed before reaching it.
local lines = {}
local outFile = io.open(OUTPUT_FILE, "w")
local function log(s)
  table.insert(lines, s)
  console.log(s)
  if outFile then outFile:write(s .. "\n"); outFile:flush() end
end

local function findActorByRosterId(ctx, rosterId)
  for idx = 1, ctx.PartyCount do
    if ctx.Combatants[idx].Id == rosterId then return idx end
  end
  return nil
end

local function findMedicineSlot(base, actorIdx)
  local rec = base + 0xf84 + actorIdx * 0xc
  local classPtr0 = memory.read_u32_le(rec)
  if not Address.isValidPointer(classPtr0) then return nil end
  classPtr0 = Address.sanitize(classPtr0)
  local statsAddr = memory.read_u32_le(classPtr0 + 0x1c)
  if not Address.isValidPointer(statsAddr) then return nil end
  statsAddr = Address.sanitize(statsAddr)
  for slot = 0, 8 do
    local entryAddr = statsAddr + 0x20 + slot * 4
    local itemId = memory.read_u16_le(entryAddr + 0x0)
    local quantity = memory.read_u8(entryAddr + 0x3)
    if itemId ~= 0 and quantity > 0 then
      local ok, name = pcall(Battle.getItemName, itemId)
      log(string.format("  McDohl inv slot %d: itemId=%d qty=%d name=%s", slot, itemId, quantity, tostring(ok and name or "?")))
      if ok and name == "Medicine" then return slot end
    end
  end
  return nil
end

local ok, err = pcall(function()
  savestate.load(BASE_SAVE)

  local ctx, reason = ActionEnumerator:readBattleContext()
  if not ctx then error("readBattleContext failed: " .. tostring(reason)) end

  log(string.format("PartyCount=%d TotalCombatants=%d", ctx.PartyCount, ctx.TotalCombatants))
  for idx = 1, ctx.TotalCombatants do
    log(string.format("  actor%d Id=%d HP=%d/%d", idx, ctx.Combatants[idx].Id, ctx.Combatants[idx].HPCurrent, ctx.Combatants[idx].HPMax))
  end

  local hero = findActorByRosterId(ctx, HERO_ID)
  local cleo = findActorByRosterId(ctx, CLEO_ID)
  if not hero then error("McDohl not found in party") end
  if not cleo then error("Cleo not found in party") end
  log(string.format("McDohl=actor%d Cleo=actor%d", hero, cleo))

  local medicineSlot = findMedicineSlot(ctx.Base, hero)
  if not medicineSlot then error("Medicine not found in McDohl's inventory") end
  log(string.format("Medicine is McDohl's inventory slot %d", medicineSlot))

  local dragon = ctx.PartyCount + 1 -- first/only enemy

  local base = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not base then error("round-start menu never became ready") end

  local function logActionFields(label, idx)
    local rec = base + 0xb40 + idx * 0x54
    log(string.format("  [%s] actor%d ActionType=%d AbilitySlot=%d TargetIdx=%d",
      label, idx, memory.read_u8(rec + 0x47), memory.read_u8(rec + 0x48), memory.read_u8(rec + 0x49)))
  end

  log("Free Will's own picks, before any override:")
  logActionFields("pre-override", hero)
  logActionFields("pre-override", cleo)

  BattleRoundInput:setActions({
    [hero] = { 3, medicineSlot, cleo }, -- Item: Medicine on Cleo
    [cleo] = { 0, 0, dragon },          -- Attack the Dragon
  })

  log("Immediately after setActions():")
  logActionFields("post-override", hero)
  logActionFields("post-override", cleo)

  -- Watch Cleo's busy byte for the exact write, via event.onmemorywrite (memory.registerwrite
  -- doesn't exist in this build).
  local cleoBusyAddr = base + 0x50 + cleo * 0x8c + 5
  local writeLog = {}
  local regOk, regErr = pcall(function()
    event.onmemorywrite(function()
      local v = memory.read_u8(cleoBusyAddr)
      local pcOk, pc = pcall(function() return emu.getregister("pc") end)
      table.insert(writeLog, string.format("frame=%d value=%d pc_ok=%s pc=%s",
        emu.framecount(), v, tostring(pcOk), pcOk and string.format("0x%x", pc) or tostring(pc)))
    end, cleoBusyAddr, "CleoBusyWatch")
  end)
  log(string.format("event.onmemorywrite registration ok=%s err=%s", tostring(regOk), tostring(regErr)))

  -- confirmRound() waits 10 frames then taps Cross - check right before that tap whether
  -- anything (e.g. Free Will's own AI recomputing on a later frame) clobbered our override.
  for i = 1, 10 do emu.frameadvance() end
  log("10 frames later, right before the confirm tap:")
  logActionFields("pre-confirm", hero)
  logActionFields("pre-confirm", cleo)
  local Buttons = require "lib.Buttons"
  Buttons.Cross:press()
  emu.frameadvance()
  Buttons.Cross:press()
  emu.frameadvance()
  Buttons:clear()
  for i = 1, 15 do emu.frameadvance() end

  log("Right after the confirm tap:")
  logActionFields("post-confirm", hero)
  logActionFields("post-confirm", cleo)

  log("--- per-frame trace (only frames where something tracked changes) ---")
  local last = {}
  local function readAll()
    local snap = {
      CurrentActor = memory.read_u32_le(base + 0x8),
      PendingActor = memory.read_u32_le(base + 0x3420),
      RollGate = memory.read_u32_le(base + 0x1264),
      RoundNumber = memory.read_u32_le(base + 0x4),
    }
    for idx = 1, ctx.TotalCombatants do
      snap["busy" .. idx] = memory.read_u8(base + 0x50 + idx * 0x8c + 5)
      snap["tag" .. idx] = memory.read_u8(base + 0xb40 + idx * 0x54 + 0x46)
    end
    return snap
  end
  last = readAll()
  log("frame=0 (post-confirm) initial state:")
  for k, v in pairs(last) do log(string.format("  init %s=%s", k, tostring(v))) end

  local startFrame = emu.framecount()
  for i = 1, MAX_FRAMES do
    emu.frameadvance()
    local cur = readAll()
    local changed = {}
    for k, v in pairs(cur) do
      if last[k] ~= v then table.insert(changed, string.format("%s: %s -> %s", k, tostring(last[k]), tostring(v))) end
    end
    if #changed > 0 then
      table.sort(changed)
      log(string.format("frame=%d (t+%d) %s", emu.framecount(), emu.framecount() - startFrame, table.concat(changed, " | ")))
    end
    last = cur
  end

  log("--- event.onmemorywrite hits on Cleo's busy byte ---")
  for _, l in ipairs(writeLog) do log(l) end
end)

if not ok then log("ERROR: " .. tostring(err)) end

if outFile then outFile:close() end
client.exit()
