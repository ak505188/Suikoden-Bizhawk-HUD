-- Verify Poison's periodic tick: does it consume RNG, and what's the exact per-round damage
-- formula? slot1 is already poisoned in NeclordBats.State (confirmed in a prior session).
-- Advance many more rounds, watching slot1's HP and Address.RNG each round, to see the exact
-- per-tick damage amount and whether RNG changes during it.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceNeclordPoisonTick.txt"
local TARGET_SLOT = 1
local MAX_FRAMES = 6000

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/NeclordBats.State")
local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
local c = base + 0xb94 + TARGET_SLOT * 0x54

log(string.format("slot%d: HP_Max=%d MGC=%d PWR=%d DEF=%d SPD=%d SKL=%d LUK=%d",
  TARGET_SLOT,
  mainmemory.read_u16_le(c + 0x10), mainmemory.read_u16_le(c + 0x2c),
  mainmemory.read_u16_le(c + 0x24), mainmemory.read_u16_le(c + 0x28),
  mainmemory.read_u16_le(c + 0x2a), mainmemory.read_u16_le(c + 0x26),
  mainmemory.read_u16_le(c + 0x2e)))

local lastHp = mainmemory.read_u16_le(c + 0x12)
local lastRound = mainmemory.read_u32_le(base + 0x4)
local lastRng = mainmemory.read_u32_le(Address.RNG)
log(string.format("frame=0 round=%d HP=%d status=%d rng=0x%08x",
  lastRound, lastHp, mainmemory.read_u8(c + 0x4a), lastRng))

for frame = 1, MAX_FRAMES do
  emu.frameadvance()
  local hp = mainmemory.read_u16_le(c + 0x12)
  local round = mainmemory.read_u32_le(base + 0x4)
  local rng = mainmemory.read_u32_le(Address.RNG)
  if hp ~= lastHp or round ~= lastRound then
    log(string.format("frame=%d round=%d HP=%d (delta=%d) status=%d rng_changed=%s",
      frame, round, hp, hp - lastHp, mainmemory.read_u8(c + 0x4a), tostring(rng ~= lastRng)))
    lastHp = hp
    lastRound = round
  end
  lastRng = rng
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
