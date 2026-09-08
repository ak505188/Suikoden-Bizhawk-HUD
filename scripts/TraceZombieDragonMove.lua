-- Captures the RNG state at the exact moment Zombie Dragon's own turn begins (base+0x8==7) -
-- NOT the same as the originally-injected battle seed, since other party members take their
-- own turns (consuming their own RNG rolls) earlier in the same round.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/ZombieDragonT2.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceZombieDragonMove.txt"
local ENEMY_ACTOR_ID = 7

local SEEDS = { 0x5eed1234, 0x33333333, 0x11111111, 0x22222222 }

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

for _, seed in ipairs(SEEDS) do
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  mainmemory.write_u32_le(Address.RNG, seed)
  local frame = 0
  while frame < 300 do
    local actor = mainmemory.read_u32_le(base + 0x8)
    if actor == ENEMY_ACTOR_ID then break end
    emu.frameadvance()
    frame = frame + 1
  end
  local rng = mainmemory.read_u32_le(Address.RNG)
  log(string.format("orig=0x%08x turnStartRng=0x%08x frame=%d", seed, rng, frame))
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
