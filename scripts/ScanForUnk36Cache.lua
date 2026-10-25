-- Live value-scan (not a hook, not a pointer search) for MonsterRecord+0x36 ("unk0x36"), the field
-- that's present and nonzero on every single one of 124 scanned monsters but has no known consumer
-- (checked every caller of build_sprite_poly_resource/apply_sprite_texture_coords/
-- queue_texture_clut_upload - none read it; no stat/pointer-distance/checksum correlation found
-- either). Since this is a plain, fairly distinctive NUMBER (not an address, so no risk of
-- colliding with other pointers the way a raw pointer-value search would), a full-RAM literal-value
-- scan right after battle setup is a much higher-signal technique than blindly grepping
-- disassembly: if the game copies it anywhere into live state (the same way it already copies
-- MonsterRecord+0x3c/+0x3e into EnemyData.nSpriteOffsetX/Y), this will find the exact address, and
-- from there get_xrefs_to on writes to that address would find the consuming instruction directly.
--
-- Target: Zombie Dragon, whose MonsterRecord+0x36 = 20545 (0x5041) - a large, distinctive value,
-- low collision risk with legitimate small stat/position numbers. Positive control: her own
-- MonsterRecord+0x3c/+0x3e (8, 15) are ALREADY confirmed to land at EnemyData+0x74/+0x76 - we
-- independently re-verify that first, to prove the scanning methodology itself is sound before
-- trusting a "not found" result for the real target (20545).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/ScanForUnk36Cache.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/ZombieDragonStart.State"
local TARGET_U16 = 20545 -- MonsterRecord+0x36 for Zombie Dragon
local KNOWN_OFFSET_X = 8  -- MonsterRecord+0x3c, already confirmed -> EnemyData+0x74
local KNOWN_OFFSET_Y = 15 -- MonsterRecord+0x3e, already confirmed -> EnemyData+0x76

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/ScanForUnk36Cache.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  console.log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

local function u16le(bytes, i)
  -- bytes is 0-indexed table from readbyterange; i is 0-indexed byte offset
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

  local dragonIdx = nil
  for idx = partyCount + 1, totalCombatants do
    local enemyDataAddr = base + 0x50 + idx * 0x8c
    local speciesId = mainmemory.read_u8(enemyDataAddr)
    local recordAddr = Address.sanitize(mainmemory.read_u32_le(rowArray + speciesId * 4))
    local name = Charmap.readStringFromMemory(recordAddr, 16)
    if name:match("^Zombie Dragon") then
      dragonIdx = idx
    end
  end
  if not dragonIdx then
    error("Zombie Dragon not found among enemy slots")
  end
  local enemyDataAddr = base + 0x50 + dragonIdx * 0x8c
  log(string.format("Zombie Dragon is enemy slot %d, EnemyData at relative 0x%06x", dragonIdx, enemyDataAddr))

  -- Positive control: confirm the already-known sprite-offset cache is where we expect.
  local liveOffsetX = mainmemory.read_s16_le(enemyDataAddr + 0x74)
  local liveOffsetY = mainmemory.read_s16_le(enemyDataAddr + 0x76)
  log(string.format("Sanity check EnemyData+0x74/+0x76 = %d,%d (expected %d,%d) match=%s",
    liveOffsetX, liveOffsetY, KNOWN_OFFSET_X, KNOWN_OFFSET_Y,
    tostring(liveOffsetX == KNOWN_OFFSET_X and liveOffsetY == KNOWN_OFFSET_Y)))

  -- Full main-RAM literal-value scan for TARGET_U16 (0x5041), 2MB.
  log(string.format("Scanning full 0x200000-byte main RAM for u16 value %d (0x%04x)...", TARGET_U16, TARGET_U16))
  local domainSize = mainmemory.getcurrentmemorydomainsize()
  log(string.format("mainmemory domain size = 0x%x", domainSize))

  local CHUNK = 0x10000 -- 64KB chunks
  local hits = {}
  local addr = 0
  while addr < domainSize do
    local len = math.min(CHUNK, domainSize - addr)
    local bytes = mainmemory.readbyterange(addr, len)
    for i = 0, len - 2 do
      local v = u16le(bytes, i)
      if v == TARGET_U16 then
        local absAddr = addr + i
        table.insert(hits, absAddr)
      end
    end
    addr = addr + CHUNK
  end

  log(string.format("Total occurrences of literal u16 %d found in main RAM: %d", TARGET_U16, #hits))
  for i, h in ipairs(hits) do
    if i <= 100 then
      local aligned = (h % 2 == 0)
      local deltaFromEnemyData = h - enemyDataAddr
      local deltaFromBattleBase = h - base
      log(string.format("  hit #%d: relative=0x%06x aligned=%s battle_base%+d EnemyData%+d",
        i, h, tostring(aligned), deltaFromBattleBase, deltaFromEnemyData))
    end
  end
  if #hits > 100 then
    log(string.format("  ... and %d more (truncated)", #hits - 100))
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
