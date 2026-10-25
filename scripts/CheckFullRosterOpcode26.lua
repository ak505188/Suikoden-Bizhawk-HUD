-- Full-roster extension of the opcode-26 (anim_op_set_effect_flags) counter-arming
-- investigation. Prior work (scripts/CheckCounterRangeTest.lua) only covered the 6 combatants
-- active in one specific battle. This uses the fact (traced 2026-09-19, static pass) that a
-- character's attack-script table pointer is a SAVE-DATA property, not battle-only:
--   ptr1 = GAMESTATE_BASE + rosterId*4
--   classData = *(ptr1 + 0x1b9c)          -- sanitized pointer
--   scriptTablePtr = *(classData + 0x20)  -- same pAttackScriptTable-shaped pointer
-- This works for ANY recruited character, not just ones in the current active party/battle.
-- Cross-validated against the currently-active battle combatants (read via the already-proven
-- EnemyData+0x08 method) before trusting it on the rest of the roster.
--
-- anim_op_set_effect_flags (0x800e4fd8, opcode 26, confirmed via decompile this pass):
--   bytecode: [opcode:u16=0x001A][target:u16][mask:u16], 6 bytes, cursor advances by 6.
--   target==1 -> OR mask into the CURRENT TARGET's (bAnimTargetIdx) enemy_data+0x40 wEffectFlags.
--   target!=1 -> OR mask into the CASTER'S OWN enemy_data+0x40.
-- Counter-arm bit is mask bit 0x0001. A script can call opcode 26 multiple times for unrelated
-- flags, so this scans all hits in the first 200 bytes of a script and reports the one(s)
-- touching bit 0x0001.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckFullRosterOpcode26.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local CharAddresses = require "lib.Characters.Addresses"
local Names = require "lib.Characters.NamesList"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/CounterRangeTest.State"
local GAMESTATE_BASE = Address.GAMESTATE_BASE -- 0x1B8000

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckFullRosterOpcode26.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function findOpcode26CounterArm(scriptAddr, maxBytes)
  if not Address.isValidPointer(scriptAddr) then return nil end
  local addr = Address.sanitize(scriptAddr)
  for off = 0, maxBytes - 6 do
    local b0 = mainmemory.read_u8(addr + off)
    local b1 = mainmemory.read_u8(addr + off + 1)
    if b0 == 0x1A and b1 == 0x00 then
      local target = mainmemory.read_u16_le(addr + off + 2)
      local mask = mainmemory.read_u16_le(addr + off + 4)
      if (mask & 0x0001) ~= 0 then
        return { offset = off, target = target, mask = mask }
      end
    end
  end
  return nil
end

-- Resolve a roster Id's attack-script-table pointer purely from save data (no battle needed).
local function resolveScriptTableByRosterId(rosterId)
  local ptr1 = GAMESTATE_BASE + rosterId * 4
  local classDataRaw = mainmemory.read_u32_le(ptr1 + 0x1b9c)
  if not Address.isValidPointer(classDataRaw) then return nil, "no classData" end
  local classData = Address.sanitize(classDataRaw)
  local scriptTableRaw = mainmemory.read_u32_le(classData + 0x20)
  if not Address.isValidPointer(scriptTableRaw) then return nil, "no scriptTable" end
  return Address.sanitize(scriptTableRaw), nil
end

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 100 do emu.frameadvance() end -- settle, per project convention

  -- Build roster Id -> name, and vice versa, from Characters.Addresses (only entries with a
  -- combat "Id" are attack-capable; the rest are non-combat townspeople).
  local idToName = {}
  local rosterIds = {}
  for _, name in ipairs(Names) do
    local rec = CharAddresses[name]
    if rec and rec.Id ~= nil then
      idToName[rec.Id] = name
      table.insert(rosterIds, rec.Id)
    end
  end
  table.sort(rosterIds)
  log(string.format("Combat-capable roster entries found: %d", #rosterIds))

  -- Cross-validation: resolve the current battle's active combatants via the already-proven
  -- EnemyData+0x08 method, and compare against the new GAMESTATE_BASE-only method for the same
  -- characters, before trusting the new method on the rest of the roster.
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  local partyCount = mainmemory.read_u32_le(base + 0x1c)
  log(string.format("BattleState base=0x%06x partyCount=%d", base, partyCount))

  -- DIAGNOSTIC: also read the raw classData pointer for each active combatant via the
  -- BattleState+0xf84 ClassPtrsArray (idx-indexed, per lib/Party.lua/BattleSnapshot.lua), then
  -- brute-force search a range of GAMESTATE_BASE offsets for one whose classData pointer
  -- MATCHES it - to empirically determine what "offset" actually means, since assuming
  -- offset==bId (roster Id) failed for most characters.
  local crossValidated = {}
  local crossOk = true
  for idx = 1, partyCount do
    local enemyDataAddr = base + 0x50 + idx * 0x8c
    local bId = mainmemory.read_u8(enemyDataAddr)
    local viaBattle = Address.sanitize(mainmemory.read_u32_le(enemyDataAddr + 0x08))

    -- classData via BattleState+0xf84 (ClassPtrsArray), idx-indexed, stride 0xc.
    local classPtrsSlot = base + 0xf84 + idx * 0xc
    local classDataViaBattleRaw = mainmemory.read_u32_le(classPtrsSlot + 0)
    local classDataViaBattle = Address.isValidPointer(classDataViaBattleRaw)
      and Address.sanitize(classDataViaBattleRaw) or nil

    local viaSave, errMsg = resolveScriptTableByRosterId(bId)
    local match = (viaSave == viaBattle)
    crossValidated[bId] = true

    -- Brute-force: which offset O (0..127) makes GAMESTATE_BASE+O*4+0x1b9c dereference to
    -- classDataViaBattle?
    local foundOffset = nil
    if classDataViaBattle then
      for o = 0, 127 do
        local candRaw = mainmemory.read_u32_le(GAMESTATE_BASE + o * 4 + 0x1b9c)
        if Address.isValidPointer(candRaw) and Address.sanitize(candRaw) == classDataViaBattle then
          foundOffset = o
          break
        end
      end
    end

    log(string.format(
      "CROSS-CHECK idx=%d bId=%d name=%s viaBattle=0x%08x viaSave(offset=bId)=%s match=%s " ..
      "classDataViaBattle=%s trueOffset=%s",
      idx, bId, idToName[bId] or "?", viaBattle,
      viaSave and string.format("0x%08x", viaSave) or ("nil(" .. tostring(errMsg) .. ")"),
      tostring(match),
      classDataViaBattle and string.format("0x%08x", classDataViaBattle) or "nil",
      tostring(foundOffset)))
    if not match then crossOk = false end
  end

  if not crossOk then
    log("CROSS-CHECK FAILED - the GAMESTATE_BASE-only method disagrees with the live battle " ..
        "EnemyData method for at least one active combatant. STOPPING before trusting the " ..
        "rest of the roster.")
    return
  end
  log("CROSS-CHECK PASSED for all active battle combatants - proceeding with full roster.")

  -- Known 10-character sanity targets (from prior sessions' work).
  local expectedSelf = { VIKTOR = true, GREMIO = true, HERO = true, CAMILLE = true,
    TAI_HO = true, KASUMI = true }
  local expectedEnemy = { CLEO = true, KIRKIS = true, KAGE = true, TENGAAR = true }

  local results = {} -- name -> "self"/"enemy"/"none-found"/"unrecruited"
  local sanityFailures = {}

  for _, rid in ipairs(rosterIds) do
    local name = idToName[rid]
    local scriptTable, errMsg = resolveScriptTableByRosterId(rid)
    if not scriptTable then
      results[name] = "unrecruited(" .. tostring(errMsg) .. ")"
    else
      local primaryScript = mainmemory.read_u32_le(scriptTable + 0x04)
      local hitScript = mainmemory.read_u32_le(scriptTable + 0x08)
      local hit = findOpcode26CounterArm(primaryScript, 200)
      local slot = "primary"
      if not hit then
        hit = findOpcode26CounterArm(hitScript, 200)
        slot = "hit"
      end
      if not hit then
        results[name] = "no-opcode26-found"
      else
        local verdict = (hit.target == 1) and "enemy" or "self"
        results[name] = verdict .. " (" .. slot .. " script, +0x" ..
          string.format("%02x", hit.offset) .. ")"
      end
    end

    if expectedSelf[name] then
      local got = results[name]
      if not (got and got:match("^self")) then
        table.insert(sanityFailures, name .. " expected self, got " .. tostring(got))
      end
    elseif expectedEnemy[name] then
      local got = results[name]
      if not (got and got:match("^enemy")) then
        table.insert(sanityFailures, name .. " expected enemy, got " .. tostring(got))
      end
    end
  end

  log("")
  if #sanityFailures > 0 then
    log("SANITY CHECK FAILED:")
    for _, f in ipairs(sanityFailures) do log("  " .. f) end
  else
    log("SANITY CHECK PASSED: all 10 known characters matched expected self/enemy.")
  end

  log("")
  log("FULL RESULTS:")
  local names = {}
  for name, _ in pairs(results) do table.insert(names, name) end
  table.sort(names)
  local selfCount, enemyCount, otherCount = 0, 0, 0
  for _, name in ipairs(names) do
    local r = results[name]
    log(string.format("  %-12s Id=%-3d %s", name, CharAddresses[name].Id, r))
    if r:match("^self") then selfCount = selfCount + 1
    elseif r:match("^enemy") then enemyCount = enemyCount + 1
    else otherCount = otherCount + 1 end
  end
  log("")
  log(string.format("TALLY: self=%d enemy=%d other/unresolved=%d total=%d",
    selfCount, enemyCount, otherCount, #names))
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
