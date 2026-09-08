-- Directly watches enemy_data[i]+0x54 (aUnk_0x42+0x12, the per-frame custom callback slot per
-- FUN_800e358c's own decompile: pcVar8 = *(code**)(EnemyDataArray[param_1].aUnk_0x42+0x12); if
-- nonzero, called as pcVar8(g_pBattleState, param_1) every frame) for all 7 combatants, to find
-- what actually gets installed there and when - the definitive test for whether
-- dragon_fire_breath_windup/dragon_special_move_frame_callback are ever really used.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/FrameCallbackTrace.txt"
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
  for i = 0, 6 do last[i] = mainmemory.read_u32_le(base + 0xdc + i * 0x8c + 0x54) end

  for frame = 0, MAX_FRAMES do
    for i = 0, 6 do
      local v = mainmemory.read_u32_le(base + 0xdc + i * 0x8c + 0x54)
      if v ~= last[i] then
        log(string.format("  frame=%-4d enemy_data[%d]+0x54 (callback): 0x%08x -> 0x%08x", frame, i, last[i], v))
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
