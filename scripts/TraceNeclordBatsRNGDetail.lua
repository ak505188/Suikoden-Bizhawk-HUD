-- Full per-frame RNG-change log (like DetailedLightningRNG.lua) for both Neclord savestates,
-- to see the real timeline before committing to a settle-floor value.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceNeclordBatsRNGDetail.txt"
local MAX_FRAMES = 250

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function traceOne(savestatePath, label)
  savestate.load(savestatePath)
  local lastRng = mainmemory.read_u32_le(Address.RNG)
  local changes = {}
  for frame = 0, MAX_FRAMES do
    local curRng = mainmemory.read_u32_le(Address.RNG)
    if curRng ~= lastRng then
      changes[#changes+1] = frame
      lastRng = curRng
    end
    emu.frameadvance()
  end
  log(string.format("=== %s (seed=0x%08x) - %d changes ===", label, mainmemory.read_u32_le(Address.RNG), #changes))
  log(table.concat(changes, ","))
end

local ok, err = pcall(function()
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/Neclord.State", "Neclord(Wind)")
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/NeclordBats.State", "NeclordBats")
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
