-- Same technique as ScanForUnk36Cache.lua, applied to Killer Rabbit's unk0x38/unk0x3a pair
-- (MonsterRecord+0x38 = 1660, +0x3a = 638) to cross-check whether the "trailing 10 bytes" region
-- (+0x36..+0x3f) is EVER copied into live battle state for any monster, not just Zombie Dragon.
-- Searches for the adjacent 4-byte pattern (u16 1660 followed by u16 638) as a single distinctive
-- unit - much lower collision risk than either value alone.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/ScanForUnk38Cache.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/KillerRabbit.State"
local TARGET_38 = 1660
local TARGET_3A = 638

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/ScanForUnk38Cache.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  console.log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

local function u16le(bytes, i)
  local lo = bytes[i]
  local hi = bytes[i + 1]
  if lo == nil or hi == nil then return nil end
  return lo + hi * 256
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
  local rowArray = Address.sanitize(mainmemory.read_u32_le(base + 0x1344))

  local rabbitIdx = nil
  for idx = partyCount + 1, totalCombatants do
    local enemyDataAddr = base + 0x50 + idx * 0x8c
    local speciesId = mainmemory.read_u8(enemyDataAddr)
    local recordAddr = Address.sanitize(mainmemory.read_u32_le(rowArray + speciesId * 4))
    local name = Charmap.readStringFromMemory(recordAddr, 16)
    log(string.format("slot %d speciesId=%d name=%q", idx, speciesId, name))
    if name:match("^Killer Rabbit") then
      rabbitIdx = idx
    end
  end
  if not rabbitIdx then
    error("Killer Rabbit not found among enemy slots")
  end
  local enemyDataAddr = base + 0x50 + rabbitIdx * 0x8c
  log(string.format("Killer Rabbit is enemy slot %d, EnemyData at relative 0x%06x", rabbitIdx, enemyDataAddr))

  log(string.format("Scanning full main RAM for adjacent u16 pair (%d, %d)...", TARGET_38, TARGET_3A))
  local domainSize = mainmemory.getcurrentmemorydomainsize()
  local CHUNK = 0x10000
  local hits = {}
  local addr = 0
  while addr < domainSize do
    local len = math.min(CHUNK, domainSize - addr)
    local bytes = mainmemory.readbyterange(addr, len)
    for i = 0, len - 4 do
      local a = u16le(bytes, i)
      local b = u16le(bytes, i + 2)
      if a == TARGET_38 and b == TARGET_3A then
        table.insert(hits, addr + i)
      end
    end
    addr = addr + CHUNK
  end

  log(string.format("Total occurrences of the (%d,%d) pair found: %d", TARGET_38, TARGET_3A, #hits))
  for i, h in ipairs(hits) do
    log(string.format("  hit #%d: relative=0x%06x battle_base%+d EnemyData%+d",
      i, h, h - base, h - enemyDataAddr))
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
