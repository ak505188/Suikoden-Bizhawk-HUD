-- Same gotcha as Zombie Dragon: the raw savestate seed may not be what Neclord's own decision
-- function sees, if other actors act first in the same round. Find Neclord's own actor number
-- (watch base+0x8) and capture Address.RNG at the exact frame her turn begins.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CaptureNeclordTurnStartRNG.txt"
local MAX_FRAMES = 300

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function traceOne(savestatePath, label)
  savestate.load(savestatePath)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  local rawSeed = mainmemory.read_u32_le(Address.RNG)
  local partyCount = mainmemory.read_u32_le(base + 0x1c)
  log(string.format("%s: raw_seed=0x%08x partyCount=%d", label, rawSeed, partyCount))

  local frame = 0
  local lastActor = nil
  while frame < MAX_FRAMES do
    local actor = mainmemory.read_u32_le(base + 0x8)
    if actor ~= lastActor then
      log(string.format("  frame=%d actor=%d rng=0x%08x", frame, actor, mainmemory.read_u32_le(Address.RNG)))
      lastActor = actor
    end
    emu.frameadvance()
    frame = frame + 1
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
