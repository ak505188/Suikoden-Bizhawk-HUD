-- Gather everything needed to bit-exact validate all 3 of Neclord's damage formulas: her own
-- ATK/MGC, and every party member's MGC/DEF/RuneId (for Lightning/Wind's element formula and
-- Bats' physical formula).

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckNeclordFullStats.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function traceOne(savestatePath, label)
  savestate.load(savestatePath)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  log(string.format("=== %s (seed=0x%08x) ===", label, mainmemory.read_u32_le(Address.RNG)))

  local nc = base + 0xb94 + 6 * 0x54
  log(string.format("Neclord: ATK=%d DEF=%d MGC=%d",
    mainmemory.read_u16_le(nc + 0x30), mainmemory.read_u16_le(nc + 0x32), mainmemory.read_u16_le(nc + 0x2c)))

  for i = 0, 5 do
    local c = base + 0xb94 + i * 0x54
    local mgc = mainmemory.read_u16_le(c + 0x2c)
    local def = mainmemory.read_u16_le(c + 0x32)
    local hp = mainmemory.read_u16_le(c + 0x12)
    local classDataPtr = Address.sanitize(mainmemory.read_u32_le(base + 0xf84 + i * 12))
    local runeId = mainmemory.read_u8(classDataPtr + 0x1c + 0x4c)
    log(string.format("slot %d: MGC=%d DEF=%d HP=%d RuneId=%d", i, mgc, def, hp, runeId))
  end
end

local ok, err = pcall(function()
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/Neclord.State", "Neclord(Lightning)")
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/NeclordBats.State", "NeclordBats")
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
