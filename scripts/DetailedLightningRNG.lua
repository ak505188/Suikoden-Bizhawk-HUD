-- Logs every single frame where Address.RNG changes (and how many times, if more than once
-- per frame) for 2 known-Lightning seeds, to compare the exact roll schedule and find the
-- variable component.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DetailedLightningRNG.txt"
local MAX_FRAMES = 310

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local SEEDS = {
  {seed = 0x29c7855e, label = "L_target0_A"},
  {seed = 0xd1f6f86c, label = "L_target0_B"},
}

local function traceOne(seed, label)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)

  local lastRng = mainmemory.read_u32_le(Address.RNG)
  local frames = {}
  for frame = 0, MAX_FRAMES do
    local curRng = mainmemory.read_u32_le(Address.RNG)
    if curRng ~= lastRng then
      frames[#frames+1] = frame
      lastRng = curRng
    end
    emu.frameadvance()
  end
  log(string.format("=== %s seed=0x%08x count=%d ===", label, seed, #frames))
  log(table.concat(frames, ","))
end

local ok, err = pcall(function()
  for _, entry in ipairs(SEEDS) do
    traceOne(entry.seed, entry.label)
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
