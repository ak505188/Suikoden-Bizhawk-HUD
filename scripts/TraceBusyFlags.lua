-- Traces enemy_data[i]+5 (the busy/reaction mutex byte, already documented: 0=idle,1=busy,
-- 8=being hit,9=hit by Unite) for all 7 combatants across the full window leading up to damage
-- landing (~frame 303-305), for both a known-Lightning and known-Fire-Breath seed. This runs
-- independently of battle_base+0xc (confirmed dead after frame 2), via the separate per-frame
-- animation-callback driver this project already documented (FUN_800e358c).

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/BusyFlagTrace.txt"
local MAX_FRAMES = 320

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
  local last = {}
  for i = 0, 6 do last[i] = mainmemory.read_u8(base + 0xdc + i * 0x8c + 5) end

  for frame = 0, MAX_FRAMES do
    for i = 0, 6 do
      local v = mainmemory.read_u8(base + 0xdc + i * 0x8c + 5)
      if v ~= last[i] then
        log(string.format("  frame=%-4d enemy_data[%d]+5: %d -> %d", frame, i, last[i], v))
        last[i] = v
      end
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
