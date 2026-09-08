-- Simplest, most reliable outcome check: read all 6 party HP before/after. AOE (Wind/Lightning)
-- hits everyone; Bats (single-target) hits exactly one.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckNeclordDamagePattern.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function readHp(base, i)
  return mainmemory.read_u16_le(base + 0xb94 + i * 0x54 + 0x12)
end

local function traceOne(savestatePath, label)
  savestate.load(savestatePath)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  local baseline = {}
  for i = 0, 5 do baseline[i] = readHp(base, i) end
  for frame = 1, 600 do emu.frameadvance() end
  local hits = 0
  local dmgStr = {}
  for i = 0, 5 do
    local finalHp = readHp(base, i)
    if finalHp ~= baseline[i] then
      hits = hits + 1
      table.insert(dmgStr, string.format("slot%d:%d->%d", i, baseline[i], finalHp))
    end
  end
  log(string.format("%s: hits=%d [%s]", label, hits, table.concat(dmgStr, ",")))
end

local ok, err = pcall(function()
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/Neclord.State", "Neclord(Wind?)")
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/NeclordBats.State", "NeclordBats")
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
