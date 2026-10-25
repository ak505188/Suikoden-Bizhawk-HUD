-- Resolves the 3 characters left ambiguous by the disc_extract/ opcode-26 batch trace:
-- Lepant, Pesmerga (share an on-disk file size, psu.bin/rep.bin, couldn't be told apart by
-- size alone), and Ronnie (bel.bin, had 2 distinct mask==0x1 opcode-26 script locations:
-- slot1/+0x04 primary-action=self, slot15=enemy - genuinely ambiguous by disc scan alone).
--
-- User-provided savestate CounterRemainingCharacters.State has these 3 characters present.
--
-- Same collision-proof method as scripts/CheckCounterRangeTest.lua: read the attacker's own
-- per-combatant-instance cached script table (EnemyData+0x08), not pAttackDataTable[bId]
-- (unsafe for party members - roster Id collides with monster species Id in that shared table).
--
-- For Lepant/Pesmerga: this also resolves the file-size ambiguity directly, since each live
-- combatant's own resolved script-table slot COUNT (terminated by a null u32) structurally
-- matches exactly one of the two disc candidates (psu.bin=9 slots, rep.bin=16 slots, confirmed
-- via disc_extract/extract_opcode26.py psu.bin / rep.bin beforehand).
--
-- For Ronnie: reads and scans ALL script-table slots (not just primary+hit) so we see every
-- mask==0x1 hit live, same shape disc scan found (slot1=self, slot15=enemy), and confirms
-- which one `battle_execute_enemy_attack`'s actual attacker-script read (primaryScript,
-- pAttackScriptTable+0x04) uses in practice - that's the "real" one per this project's own
-- established methodology (CheckCounterRangeTest.lua only ever needed primary+hit for the
-- other 10 characters).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckRemainingCharacters.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local CharAddresses = require "lib.Characters.Addresses"
local Names = require "lib.Characters.NamesList"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/CounterRemainingCharacters.State"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckRemainingCharacters.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local idToName = {}
for _, name in ipairs(Names) do
  local rec = CharAddresses[name]
  if rec and rec.Id then idToName[rec.Id] = name end
end

local function findOpcode26Calls(scriptAddr, maxBytes)
  local hits = {}
  local addr = Address.sanitize(scriptAddr)
  for off = 0, maxBytes - 6 do
    local b0 = mainmemory.read_u8(addr + off)
    local b1 = mainmemory.read_u8(addr + off + 1)
    if b0 == 0x1A and b1 == 0x00 then
      local target = mainmemory.read_u16_le(addr + off + 2)
      local mask = mainmemory.read_u16_le(addr + off + 4)
      table.insert(hits, { offset = off, target = target, mask = mask })
    end
  end
  return hits
end

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 100 do emu.frameadvance() end -- settle, per project convention

  local gamestate = mainmemory.read_u8(Address.GAMESTATE)
  local prevGamestate = mainmemory.read_u8(Address.PREV_GAMESTATE)
  log(string.format("gamestate=%d prevGamestate=%d (BATTLE=3)", gamestate, prevGamestate))

  local basePtrRaw = mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)
  log(string.format("raw BattleState ptr = 0x%08x, isValidPointer=%s",
    basePtrRaw, tostring(Address.isValidPointer(basePtrRaw))))
  if not Address.isValidPointer(basePtrRaw) then
    log("Not in an active battle (invalid BattleState pointer) - aborting, no loop run.")
    return
  end
  local base = Address.sanitize(basePtrRaw)
  local partyCount = mainmemory.read_u32_le(base + 0x1c)
  local totalCombatants = mainmemory.read_u32_le(base + 0x24)
  log(string.format("BattleState base=0x%06x partyCount=%d total=%d",
    base, partyCount, totalCombatants))
  if partyCount < 1 or partyCount > 6 or totalCombatants < partyCount or totalCombatants > 16 then
    log("partyCount/totalCombatants out of sane range - aborting, no loop run (likely not " ..
      "a stable in-battle savestate, or BattleState pointer resolved to garbage).")
    return
  end

  for idx = 1, partyCount do
    local enemyDataAddr = base + 0x50 + idx * 0x8c
    local bId = mainmemory.read_u8(enemyDataAddr)
    local charName = idToName[bId] or "UNKNOWN"

    local pAttackScriptTableRaw = mainmemory.read_u32_le(enemyDataAddr + 0x08)
    if not Address.isValidPointer(pAttackScriptTableRaw) then
      log(string.format("idx=%d bId=%d name=%s -- invalid pAttackScriptTable pointer 0x%08x",
        idx, bId, charName, pAttackScriptTableRaw))
      goto continue
    end
    local pAttackScriptTable = Address.sanitize(pAttackScriptTableRaw)

    -- Walk the full slot array (u32 entries) until a 0 terminator, like disc_extract's
    -- get_script_table(), to get the slot count for file-attribution and to scan every slot.
    local slots = {}
    local p = pAttackScriptTable
    while true do
      local v = mainmemory.read_u32_le(p)
      if v == 0 then break end
      table.insert(slots, v)
      p = p + 4
      if #slots > 64 then break end -- safety
    end

    log(string.format("idx=%d bId=%d name=%s pAttackScriptTable=0x%08x slotCount=%d",
      idx, bId, charName, pAttackScriptTable, #slots))

    for slotIdx, slotAddrRaw in ipairs(slots) do
      if Address.isValidPointer(slotAddrRaw) then
        local hits = findOpcode26Calls(slotAddrRaw, 200)
        for _, h in ipairs(hits) do
          local counterArm = (h.mask & 0x0001) ~= 0
          local who = (h.target == 1) and "ENEMY" or "self"
          log(string.format(
            "  slot%d(0x%08x)+0x%02x: opcode26 target=%d(%s) mask=0x%04x%s",
            slotIdx - 1, slotAddrRaw, h.offset, h.target, who, h.mask,
            counterArm and " <-- COUNTER-ARM BIT (0x0001)" or ""))
        end
      end
    end

    -- Explicitly call out what battle_execute_enemy_attack's real read path sees:
    -- pAttackScriptTable+0x04 (primary action script) is slots[2] (1-indexed Lua: slot index
    -- 1 = +0x04, since slots[1] = +0x00).
    if slots[2] and Address.isValidPointer(slots[2]) then
      local hits = findOpcode26Calls(slots[2], 200)
      local armSelf, armEnemy = false, false
      for _, h in ipairs(hits) do
        if (h.mask & 0x0001) ~= 0 then
          if h.target == 1 then armEnemy = true else armSelf = true end
        end
      end
      log(string.format("  ==> primary-action-script (+0x04) mask=0x1 verdict: %s",
        armEnemy and "ENEMY" or (armSelf and "self" or "no mask=0x1 hit in primary script")))
    end

    ::continue::
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
