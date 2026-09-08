-- Correct methodology (per Spell_RNG_Tracing_Methodology.md): let RNG settle (unchanged for N
-- consecutive frames) after Lightning fully resolves, then report the exact final RNG value.
-- The exact total call count is recovered separately via LCG-step-counting in Python (forward-
-- simulating from the start seed until it equals this settled value), which is immune to the
-- undercounting risk of naive per-frame "did it change" polling when multiple rand() calls can
-- happen within a single frame's CPU execution.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/SettledLightningRNG.txt"
local MAX_FRAMES = 500
local SETTLE_FRAMES = 30 -- consecutive unchanged frames required, after a minimum elapsed floor

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local SEEDS = {
  0xc8065964, 0x147f2e18, 0xe57e02d0, 0xdf5bab03, 0x915a7f79,
  0x92e19f1a, 0x88a0a8b7, 0x7d9510a7, 0x21cf69c0, 0xe0d15871,
}

local function traceOne(seed)
  savestate.load(BASE_SAVE)
  mainmemory.write_u32_le(Address.RNG, seed)

  local lastRng = mainmemory.read_u32_le(Address.RNG)
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
    if frame > 320 and unchangedStreak >= SETTLE_FRAMES then
      settledAt = frame
      break
    end
    emu.frameadvance()
    frame = frame + 1
  end
  log(string.format("seed=0x%08x final_rng=0x%08x settled_at_frame=%s",
    seed, lastRng, tostring(settledAt)))
end

local ok, err = pcall(function()
  for _, seed in ipairs(SEEDS) do
    traceOne(seed)
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
