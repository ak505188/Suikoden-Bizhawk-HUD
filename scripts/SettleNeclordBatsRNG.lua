-- Correct methodology (per Spell_RNG_Tracing_Methodology.md): let RNG settle (unchanged for N
-- consecutive frames) after the Bats attack fully resolves, then report the exact final RNG
-- value. The exact total call count is recovered separately via LCG-step-counting in Python/Lua
-- (forward-simulating from the start seed until it equals this settled value).
--
-- NeclordBats.State is already positioned with RNG modified to force the Bats move (per the
-- user). Also captures Neclord.State (unmodified, naturally leads to Wind) for cross-validation
-- of the move-selection formula.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/SettleNeclordBatsRNG.txt"
local MAX_FRAMES = 1200
local SETTLE_FRAMES = 30

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function traceOne(savestatePath, label)
  savestate.load(savestatePath)
  local seed = mainmemory.read_u32_le(Address.RNG)

  local lastRng = seed
  local unchangedStreak = 0
  local frame = 0
  local settledAt = nil
  while frame < MAX_FRAMES do
    local curRng = mainmemory.read_u32_le(Address.RNG)
    if curRng == lastRng then
      unchangedStreak = unchangedStreak + 1
    else
      unchangedStreak = 0
      lastRng = curRng
    end
    if frame > 200 and unchangedStreak >= SETTLE_FRAMES then
      settledAt = frame
      break
    end
    emu.frameadvance()
    frame = frame + 1
  end
  log(string.format("%s: seed=0x%08x final_rng=0x%08x settled_at_frame=%s",
    label, seed, lastRng, tostring(settledAt)))
end

local ok, err = pcall(function()
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/Neclord.State", "Neclord(Wind)")
  traceOne("/home/alex/Projects/Suikoden-Bizhawk-HUD/NeclordBats.State", "NeclordBats")
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
