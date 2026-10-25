-- Hook-free approach (event.* memory hooks confirmed non-functional on this PSX core - see
-- scripts/verify/VerifyEventAPI.lua's definitive result: RNG genuinely changed value during a live
-- round, yet event.onmemorywrite reported zero hits). Instead: scan Gigantes' live EnemyData
-- record and a generous surrounding window for any 4-byte occurrence of her own statically-known
-- MonsterRecord+0x2c pointer or its 4 sub-pointers, to see if/where it gets cached at battle-init
-- time (the same way MonsterRecord+0x28 is known to get cached into EnemyData+8).
--
-- Gigantes' own static values (vc3.bin, read via Ghidra this session):
--   MonsterRecord+0x28 (primary table) = 0x80048958
--   MonsterRecord+0x2c (secondary/VFX-shaped table) = 0x80048cb4
--   secondary table's own 4 sub-pointers = 0x8004899c, 0x80048b14, 0x80048b98, 0x80048c58
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/ScanForSecondaryTableCache.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Gigantes.State"

local CANDIDATES = {
  { name = "MonsterRecord+0x28 (primary table)", value = 0x80048958 },
  { name = "MonsterRecord+0x2c (secondary table)", value = 0x80048cb4 },
  { name = "secondary table slot0", value = 0x8004899c },
  { name = "secondary table slot1", value = 0x80048b14 },
  { name = "secondary table slot2", value = 0x80048b98 },
  { name = "secondary table slot3", value = 0x80048c58 },
}

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/ScanForSecondaryTableCache.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  console.log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 5 do emu.frameadvance() end

  local baseRaw = mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(baseRaw) then
    error("no battle active: BattleState ptr = " .. string.format("0x%08x", baseRaw))
  end
  local base = Address.sanitize(baseRaw)

  local partyCount = mainmemory.read_u32_le(base + 0x1c)
  local totalCombatants = mainmemory.read_u32_le(base + 0x24)
  log(string.format("partyCount=%d totalCombatants=%d", partyCount, totalCombatants))

  local rowArray = Address.sanitize(mainmemory.read_u32_le(base + 0x1344))

  -- find Gigantes' own enemy slot
  local gigantesIdx = nil
  for idx = partyCount + 1, totalCombatants do
    local enemyDataAddr = base + 0x50 + idx * 0x8c
    local speciesId = mainmemory.read_u8(enemyDataAddr)
    local recordAddr = Address.sanitize(mainmemory.read_u32_le(rowArray + speciesId * 4))
    local name = Charmap.readStringFromMemory(recordAddr, 16)
    log(string.format("slot %d: speciesId=%d name=%q", idx, speciesId, name))
    if name:match("^Gigantes") then
      gigantesIdx = idx
    end
  end

  if not gigantesIdx then
    error("Gigantes not found among enemy slots")
  end
  log(string.format("Gigantes is enemy slot %d", gigantesIdx))

  local enemyDataAddr = base + 0x50 + gigantesIdx * 0x8c
  log(string.format("Her EnemyData record: 0x%08x (relative 0x%06x)", enemyDataAddr + 0x80000000 - base + baseRaw, enemyDataAddr))

  -- Confirm the +0x28 caching pattern first as a sanity check (pActionScriptTable is documented
  -- to live at EnemyData+8)
  local cachedActionTable = mainmemory.read_u32_le(enemyDataAddr + 8)
  log(string.format("EnemyData+8 (pActionScriptTable, should match MonsterRecord+0x28=0x80048958): 0x%08x match=%s",
    cachedActionTable, tostring(cachedActionTable == 0x80048958)))

  -- Scan a generous window: her own EnemyData record (140 bytes) plus surrounding enemy slots
  -- and the shared battle-state header, in case the cache lives in per-battle scratch space
  -- rather than per-actor EnemyData.
  local scanStart = base
  local scanEnd = base + 0x1400 -- covers header, combatant arrays, and enemy_data array generously
  log(string.format("Scanning 0x%06x to 0x%06x (%d bytes) for any of the %d candidate values...",
    scanStart, scanEnd, scanEnd - scanStart, #CANDIDATES))

  local foundAny = false
  for addr = scanStart, scanEnd - 4, 4 do
    local val = mainmemory.read_u32_le(addr)
    for _, cand in ipairs(CANDIDATES) do
      if val == cand.value then
        foundAny = true
        local deltaFromEnemyData = addr - enemyDataAddr
        log(string.format("MATCH: addr=0x%06x (EnemyData%+d, battle_base%+d) == %s (0x%08x)",
          addr, deltaFromEnemyData, addr - base, cand.name, cand.value))
      end
    end
  end

  if not foundAny then
    log("No matches found anywhere in the scanned 0x1400-byte window - none of these values are cached verbatim in live per-battle memory within this range.")
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
