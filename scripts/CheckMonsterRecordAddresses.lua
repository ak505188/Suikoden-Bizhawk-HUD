-- User: "Give me addresses for the example structures. Where can I find all known enemy data
-- structure?" Prints EVERY concrete address in the live pointer chain for QueenAnt.State's own
-- enemies, and confirms the live `pAttackDataTable[bId]` row is the SAME static MonsterRecord
-- scripts/ScanMonsterRecords.py already catalogs (Monster_AI_Static_Catalog.md) - by decoding the
-- name field (offset+0, charmap-encoded) at the live-resolved row address and checking it reads
-- "Queen Ant"/"Soldier Ant".
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckMonsterRecordAddresses.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckMonsterRecordAddresses.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

-- Charmap: 0x10=space, 0x11-0x2a=lowercase a-z, 0x2b+=uppercase A-Z, 0x45+=digits 0-9
local function decodeName(base, addr)
  local out = {}
  for i = 0, 15 do
    local b = mainmemory.read_u8(Address.sanitize(addr + i))
    if b == 0 then break end
    local c
    if b == 0x10 then c = ' '
    elseif b >= 0x11 and b <= 0x2a then c = string.char(string.byte('a') + (b - 0x11))
    elseif b >= 0x2b and b <= 0x44 then c = string.char(string.byte('A') + (b - 0x2b))
    elseif b >= 0x45 and b <= 0x4e then c = string.char(string.byte('0') + (b - 0x45))
    else c = '?' end
    table.insert(out, c)
  end
  return table.concat(out)
end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State")

  local basePtr = mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)
  local base = Address.sanitize(basePtr)
  log(string.format("Address.BATTLE_STATE_PTR (0x%06x) -> live BattleState* = 0x%08x (sanitized base = 0x%06x)",
    Address.BATTLE_STATE_PTR, basePtr, base))

  local rowArrayPtr = mainmemory.read_u32_le(base + 0x1344)
  local rowArray = Address.sanitize(rowArrayPtr)
  log(string.format("BattleState.pAttackDataTable @ 0x%06x -> row-pointer array = 0x%08x", base + 0x1344, rowArrayPtr))

  for _, slot in ipairs({ 6, 7, 8, 9 }) do
    local enemyDataAddr = base + 0x50 + slot * 0x8c
    local bId = mainmemory.read_u8(enemyDataAddr)
    local rowEntryAddr = rowArray + bId * 4
    local speciesRowPtr = mainmemory.read_u32_le(rowEntryAddr)
    local speciesRow = Address.sanitize(speciesRowPtr)
    local aiFuncAddr = mainmemory.read_u32_le(speciesRow + 0x30)
    local name = decodeName(base, speciesRowPtr)
    log(string.format(
      "slot %d: EnemyData @ 0x%06x, bId=%d -> pAttackDataTable[%d] @ 0x%06x = 0x%08x (MonsterRecord) -> name=%q, +0x30 AI fn = 0x%08x",
      slot, enemyDataAddr, bId, bId, rowEntryAddr, speciesRowPtr, name, aiFuncAddr))
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
