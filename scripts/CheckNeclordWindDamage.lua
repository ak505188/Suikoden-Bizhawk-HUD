-- Independent live test of Neclord's Wind attack specifically (element=5) - inject a seed
-- pre-computed (via lib/Enemies/Neclord.lua) to produce the Wind branch from this exact battle
-- position, then capture per-target damage to validate against the predicted formula.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckNeclordWindDamage.txt"
local SEED = 2

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/Neclord.State")
local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
mainmemory.write_u32_le(Address.RNG, SEED)

local function readHp(i) return mainmemory.read_u16_le(base + 0xb94 + i * 0x54 + 0x12) end
local baseline = {}
for i = 0, 5 do baseline[i] = readHp(i) end

for frame = 1, 600 do emu.frameadvance() end

local dmgStr = {}
for i = 0, 5 do
  local finalHp = readHp(i)
  table.insert(dmgStr, string.format("slot%d:%d->%d(-%d)", i, baseline[i], finalHp, baseline[i] - finalHp))
end
log(string.format("seed=0x%08x %s", SEED, table.concat(dmgStr, ",")))

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
