-- Checks whether BattleState+0x1330/+0x1334 (the scripted-turn-override mechanism already
-- documented for Queen Ant/Ted) is armed differently between known Lightning vs Fire Breath
-- seeds for Dragon.State - testing the hypothesis that Fire Breath is a separate, higher-
-- priority override rather than something dragon_ai_select_target_and_move itself decides.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DragonOverrideCheck.txt"

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

-- known outcomes from the sweep
local SEEDS = {
  {seed = 0x29c7855e, known = "Lightning"},
  {seed = 0x9e68560c, known = "Lightning"},
  {seed = 0x994a9d3f, known = "FireBreath"},
  {seed = 0xcafebabe, known = "FireBreath"},
  {seed = 0x5eed1234, known = "FireBreath"},
  {seed = 0x00000002, known = "FireBreath"},
}

local function checkOne(seed, known)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)

  local flag1330 = mainmemory.read_u32_le(base + 0x1330)
  local ptr1334 = mainmemory.read_u32_le(base + 0x1334)
  local round = mainmemory.read_u32_le(base + 0x4)
  local rollGate = mainmemory.read_u32_le(base + 0x1330 - 0x8) -- nRollGateCountdown guess area; harmless extra read
  log(string.format("seed=0x%08x known=%-10s round=%d flag1330=0x%08x ptr1334=0x%08x",
    seed, known, round, flag1330, ptr1334))
end

local ok, err = pcall(function()
  for _, entry in ipairs(SEEDS) do
    checkOne(entry.seed, entry.known)
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
