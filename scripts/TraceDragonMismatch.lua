-- Traces Address.RNG every single frame for specific seeds (known mismatches between the
-- Python model and live behavior, plus a known-good control) to find exactly how many rand()
-- calls happen and at which frames, since the user confirmed Dragon has NO idle/animation RNG
-- consumers (ruling out ambient interleaving as the explanation for the ~10% miss rate).

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DragonMismatchTrace.txt"
local MAX_FRAMES = 300

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local SEEDS = {
  {seed = 0x00000002, label = "MISMATCH(reject-all-3)"},
  {seed = 0x11223344, label = "MISMATCH(predicted FireBreath, actual Lightning)"},
  {seed = 0xb0b1b2b3, label = "MISMATCH(predicted FireBreath, actual Lightning)"},
  {seed = 0xbeefbeef, label = "MISMATCH(predicted Lightning, actual FireBreath)"},
  {seed = 0x29c7855e, label = "CONTROL(matched, Lightning)"},
}

local function traceOne(seed, label)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)

  log(string.format("=== %s seed=0x%08x ===", label, seed))
  local lastRng = mainmemory.read_u32_le(Address.RNG)
  local lastNextState = mainmemory.read_u32_le(base + 0xc)
  local dragonRec = base + 0xb94 + 6 * 0x54
  local count = 0
  for frame = 0, MAX_FRAMES do
    local curRng = mainmemory.read_u32_le(Address.RNG)
    local nextState = mainmemory.read_u32_le(base + 0xc)
    local actionType = mainmemory.read_u8(dragonRec + 0x47)
    local targetIdx = mainmemory.read_u8(dragonRec + 0x49)
    if curRng ~= lastRng then
      count = count + 1
      log(string.format("  frame=%-4d roll#%-2d RNG 0x%08x -> 0x%08x  +0xc=0x%08x actionType=%d targetIdx=%d",
        frame, count, lastRng, curRng, nextState, actionType, targetIdx))
      lastRng = curRng
    elseif nextState ~= lastNextState then
      log(string.format("  frame=%-4d              (no RNG change)          +0xc: 0x%08x -> 0x%08x",
        frame, lastNextState, nextState))
      lastNextState = nextState
    end
    emu.frameadvance()
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
