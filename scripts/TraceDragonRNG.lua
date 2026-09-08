-- Diagnostic: logs Address.RNG's raw value every single frame from the moment Dragon becomes
-- the active actor until his action resolves, for both the default-RNG and RNG+1 scenarios.
-- Goal: see exactly how many times RNG changes (= how many rand() calls happen) and their
-- exact values, to find where a hand-derived formula (front-row 3 candidates, first-accept-
-- wins) diverges from the real in-game consumption - rather than guessing blind.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local RNG = require "lib.RNG"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DragonRNGTrace.txt"
local MAX_FRAMES = 400

local lines = {}
local function log(s)
  table.insert(lines, s)
  console.log(s)
end

local function traceOne(label, advanceOneStep)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  if advanceOneStep then
    local cur = mainmemory.read_u32_le(Address.RNG)
    mainmemory.write_u32_le(Address.RNG, RNG.nextRNG(cur))
  end

  log(string.format("=== %s === start RNG=0x%08x", label, mainmemory.read_u32_le(Address.RNG)))

  local frame = 0
  -- wait until Dragon (actor 7) is active
  while frame < MAX_FRAMES do
    if mainmemory.read_u32_le(base + 0x8) == 7 then break end
    emu.frameadvance()
    frame = frame + 1
  end
  log(string.format("  actor==7 reached at frame %d, RNG=0x%08x", frame, mainmemory.read_u32_le(Address.RNG)))

  local lastRng = mainmemory.read_u32_le(Address.RNG)
  local dragonRec = base + 0xb94 + 6 * 0x54 -- slot6 = Dragon (actor 7, 0-indexed slot 6)
  local startFrame = frame
  while frame < MAX_FRAMES and frame - startFrame < 120 do
    local curRng = mainmemory.read_u32_le(Address.RNG)
    local actionType = mainmemory.read_u8(dragonRec + 0x47)
    local abilitySlot = mainmemory.read_u8(dragonRec + 0x48)
    local targetIdx = mainmemory.read_u8(dragonRec + 0x49)
    local flag46 = mainmemory.read_u8(dragonRec + 0x46)
    if curRng ~= lastRng then
      log(string.format("  frame=%d RNG 0x%08x -> 0x%08x actionType=%d abilitySlot=%d targetIdx=%d flag46=%d",
        frame, lastRng, curRng, actionType, abilitySlot, targetIdx, flag46))
      lastRng = curRng
    end
    if mainmemory.read_u32_le(base + 0x8) ~= 7 then
      log(string.format("  frame=%d actor left (turn resolved)", frame))
      break
    end
    emu.frameadvance()
    frame = frame + 1
  end
end

local ok, err = pcall(function()
  traceOne("DEFAULT", false)
  traceOne("RNG+1", true)
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then
  file:write(table.concat(lines, "\n") .. "\n")
  file:close()
end
client.exit()
