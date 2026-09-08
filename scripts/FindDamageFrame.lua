-- Extends the trace to 600 frames (matching the sweep script's own known-working window) and
-- logs the EXACT frame each party member's HP changes, plus +0xc and RNG state at that moment,
-- to find where in wall-clock time the real damage application happens - since it's confirmed
-- to happen somewhere past frame 250, through a mechanism that doesn't touch +0xc.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/FindDamageFrame.txt"
local MAX_FRAMES = 600

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local SEEDS = {
  {seed = 0x29c7855e, label = "Lightning(control)"},
  {seed = 0x994a9d3f, label = "FireBreath(control)"},
}

local function traceOne(seed, label)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)

  log(string.format("=== %s seed=0x%08x ===", label, seed))
  local baseline = {}
  for i = 0, 6 do baseline[i] = mainmemory.read_u16_le(base + 0xb94 + i * 0x54 + 0x12) end

  local lastRng = mainmemory.read_u32_le(Address.RNG)
  local lastNextState = mainmemory.read_u32_le(base + 0xc)
  local hitFrame = {}
  local anyHit = false
  for frame = 0, MAX_FRAMES do
    local curRng = mainmemory.read_u32_le(Address.RNG)
    local nextState = mainmemory.read_u32_le(base + 0xc)
    if nextState ~= lastNextState then
      log(string.format("  frame=%-4d base+0xc: 0x%08x -> 0x%08x  RNG=0x%08x", frame, lastNextState, nextState, curRng))
      lastNextState = nextState
    end
    for i = 0, 6 do
      local hp = mainmemory.read_u16_le(base + 0xb94 + i * 0x54 + 0x12)
      if hp ~= baseline[i] and not hitFrame[i] then
        hitFrame[i] = frame
        anyHit = true
        log(string.format("  frame=%-4d *** HP HIT slot%d: %d -> %d ***  RNG=0x%08x  +0xc=0x%08x",
          frame, i, baseline[i], hp, curRng, nextState))
        baseline[i] = hp
      end
    end
    lastRng = curRng
    emu.frameadvance()
  end
  if not anyHit then
    log("  (no HP change detected in " .. MAX_FRAMES .. " frames)")
  end
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
