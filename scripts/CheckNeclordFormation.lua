package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckNeclordFormation.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function traceOne(savestatePath, label)
  savestate.load(savestatePath)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  log(string.format("=== %s ===", label))
  for i = 0, 6 do
    local c = base + 0xb94 + i * 0x54
    local e = base + 0xdc + i * 0x8c
    log(string.format("slot %d: alive_gate(+0x45)=%d formationPos(+0x44)=%d busy(enemy_data+5)=%d",
      i, mainmemory.read_u8(c + 0x45), mainmemory.read_u8(c + 0x44), mainmemory.read_u8(e + 5)))
  end
end

local ok, err = pcall(function()
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/Neclord.State", "Neclord(Wind)")
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/NeclordBats.State", "NeclordBats")
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
