-- Counts EVERY rand()-consuming step (Address.RNG change) from savestate load through to
-- damage landing, for known-Lightning seeds, to determine whether Lightning's total RNG
-- advancement is fixed or variable, and to see where the already-known 2 decision rolls
-- (target-accept + move-choice) sit relative to everything else that happens afterward.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/LightningRNGCount.txt"
local MAX_FRAMES = 400

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

-- known-Lightning seeds from prior validation, targeting different slots
local SEEDS = {
  {seed = 0x29c7855e, label = "Lightning target0"},
  {seed = 0x00000001, label = "Lightning target1"},
  {seed = 0x00000003, label = "Lightning target2"},
  {seed = 0xd1f6f86c, label = "Lightning target0 (fresh)"},
}

local function traceOne(seed, label)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)

  log(string.format("=== %s seed=0x%08x ===", label, seed))
  local baseline = {}
  for i = 0, 6 do baseline[i] = mainmemory.read_u16_le(base + 0xb94 + i * 0x54 + 0x12) end

  local lastRng = mainmemory.read_u32_le(Address.RNG)
  local rollCount = 0
  local hitFrame = nil
  local lastRollFrame = -1
  for frame = 0, MAX_FRAMES do
    local curRng = mainmemory.read_u32_le(Address.RNG)
    if curRng ~= lastRng then
      rollCount = rollCount + 1
      lastRollFrame = frame
      lastRng = curRng
    end
    for i = 0, 6 do
      local hp = mainmemory.read_u16_le(base + 0xb94 + i * 0x54 + 0x12)
      if hp ~= baseline[i] and not hitFrame then
        hitFrame = frame
        log(string.format("  frame=%-4d HP HIT slot%d: %d -> %d  (rolls consumed so far: %d)",
          frame, i, baseline[i], hp, rollCount))
      end
    end
    emu.frameadvance()
  end
  log(string.format("  TOTAL rolls in %d frames: %d, last roll at frame %d, hit at frame %s",
    MAX_FRAMES, rollCount, lastRollFrame, tostring(hitFrame)))
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
