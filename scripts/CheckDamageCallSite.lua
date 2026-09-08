-- Watches battle_base+0xec (the state-machine tick counter used by the big per-tick VFX+damage
-- function, dragon_overlay.bin ~0x80013690) and each party member's HP, frame by frame, to find
-- EXACTLY when/how the Lightning vs Fire Breath damage actually gets applied, now that
-- dragon_move_confirm_or_override_to_fire_breath is confirmed to never run. Also watches
-- battle_base+0x1264 (the wait counter dragon_ai_special_move_wait arms) to see when it
-- decrements/expires, since nothing else picks up after that per the +0xc trace.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DamageCallSiteTrace.txt"
local MAX_FRAMES = 250

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

  local lastEc = mainmemory.read_u32_le(base + 0xec)
  local last1264 = mainmemory.read_u32_le(base + 0x1264)
  local lastNextState = mainmemory.read_u32_le(base + 0xc)
  local hitFrame = {}
  for frame = 0, MAX_FRAMES do
    local ec = mainmemory.read_u32_le(base + 0xec)
    local v1264 = mainmemory.read_u32_le(base + 0x1264)
    local nextState = mainmemory.read_u32_le(base + 0xc)
    if ec ~= lastEc then
      log(string.format("  frame=%-4d base+0xec: %d -> %d", frame, lastEc, ec))
      lastEc = ec
    end
    if v1264 ~= last1264 then
      log(string.format("  frame=%-4d base+0x1264: %d -> %d", frame, last1264, v1264))
      last1264 = v1264
    end
    if nextState ~= lastNextState then
      log(string.format("  frame=%-4d base+0xc: 0x%08x -> 0x%08x", frame, lastNextState, nextState))
      lastNextState = nextState
    end
    for i = 0, 6 do
      local hp = mainmemory.read_u16_le(base + 0xb94 + i * 0x54 + 0x12)
      if hp ~= baseline[i] and not hitFrame[i] then
        hitFrame[i] = frame
        log(string.format("  frame=%-4d HP HIT slot%d: %d -> %d", frame, i, baseline[i], hp))
        baseline[i] = hp
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
