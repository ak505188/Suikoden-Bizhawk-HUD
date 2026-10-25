-- Makes the disc build's libgte rsin/rcos (what BizHawk runs) behave like the PSN build's (what the PSTV runs),
-- by patching ten instruction immediates in RAM: the quadrant boundaries and the mirror constants.
-- Verified offline (one-off offline script, since removed: all 8193 angles identical to the PSN routines, via a MIPS interpreter)
-- and live (scripts/WarPsnTest.lua: Magic, Magic, Charge ends at the console's seed 0xb147d7d8). Call apply() after every savestate.load (a load restores the original code) and
-- before the first Magic cast (the instruction cache was not a problem when applied right after the load).
-- Usage:  package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
--         local psn = require("scripts.WarPsnPatch"); savestate.load(STATE); psn.apply()
local M = {}

-- {RAM address, word in the disc build, word in the PSN-equivalent}; slti/ori immediates
M.PATCH = {
  {0x8015084c, 0x28820801, 0x28820800}, {0x80150854, 0x28820401, 0x28820400}, {0x80150878, 0x34020800, 0x340207ff},
  {0x8015089c, 0x28820c01, 0x28820c00}, {0x801508a8, 0x34021000, 0x34020fff},                      -- rsin helper
  {0x801508fc, 0x28820801, 0x28820800}, {0x80150904, 0x28820401, 0x28820400}, {0x8015090c, 0x34020400, 0x340203ff},
  {0x8015094c, 0x28820c01, 0x28820c00}, {0x80150954, 0x34020c00, 0x34020bff},                      -- rcos
}

-- Returns true if the patch was applied, false (and writes nothing) if any word is not the disc build's.
function M.apply()
  for _, p in ipairs(M.PATCH) do
    if mainmemory.read_u32_le(p[1] & 0x1fffff) ~= p[2] then return false end
  end
  for _, p in ipairs(M.PATCH) do mainmemory.write_u32_le(p[1] & 0x1fffff, p[3]) end
  return true
end

return M
