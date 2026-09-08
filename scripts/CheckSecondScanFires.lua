-- Checks whether dragon_move_confirm_or_override_to_fire_breath (0x80080490) actually ever
-- runs during a real Dragon turn, by watching battle_base+0x125c (the target-lock field it
-- writes) and combatant_rec[Dragon]+0x46/+0x49 for a SECOND write after the initial one from
-- dragon_ai_select_target_and_move's own scan. If these never change again, that function does
-- not execute in this savestate's turn sequence at all.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/SecondScanCheck.txt"
local MAX_FRAMES = 300

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local SEEDS = {0x00000002, 0x11223344, 0xb0b1b2b3, 0xbeefbeef, 0x29c7855e}

local function traceOne(seed)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)

  log(string.format("=== seed=0x%08x ===", seed))
  local dragonRec = base + 0xb94 + 6 * 0x54
  local last125c = mainmemory.read_u32_le(base + 0x125c)
  local last46 = mainmemory.read_u8(dragonRec + 0x46)
  local last49 = mainmemory.read_u8(dragonRec + 0x49)
  for frame = 0, MAX_FRAMES do
    local cur125c = mainmemory.read_u32_le(base + 0x125c)
    local cur46 = mainmemory.read_u8(dragonRec + 0x46)
    local cur49 = mainmemory.read_u8(dragonRec + 0x49)
    if cur125c ~= last125c then
      log(string.format("  frame=%-4d +0x125c: %d -> %d", frame, last125c, cur125c))
      last125c = cur125c
    end
    if cur46 ~= last46 then
      log(string.format("  frame=%-4d dragonRec+0x46: %d -> %d", frame, last46, cur46))
      last46 = cur46
    end
    if cur49 ~= last49 then
      log(string.format("  frame=%-4d dragonRec+0x49: %d -> %d", frame, last49, cur49))
      last49 = cur49
    end
    emu.frameadvance()
  end
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
