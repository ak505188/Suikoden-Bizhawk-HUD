package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DragonNextStateCheck.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function traceOne(label, seed)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)

  log(string.format("=== %s seed=0x%08x ===", label, seed))
  local lastNext = mainmemory.read_u32_le(base + 0xc)
  for frame = 0, 40 do
    local nextState = mainmemory.read_u32_le(base + 0xc)
    if nextState ~= lastNext then
      log(string.format("  frame=%d base+0xc: 0x%08x -> 0x%08x", frame, lastNext, nextState))
      lastNext = nextState
    end
    emu.frameadvance()
  end
end

local ok, err = pcall(function()
  traceOne("LIGHTNING(default)", 0x29c7855e)
  traceOne("FIREBREATH(rng+1)", 0x994a9d3f)
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
