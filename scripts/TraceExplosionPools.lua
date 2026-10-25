-- Full per-tick dump of Explosion's Pool A (15 entries, ctx+0xd0) and Pool B (20 entries,
-- ctx+0x80) schedule(+0x24)/flag(+0x1c) fields across ALL of case3's 96 ticks, plus the raw
-- RNG value each tick. Goal: read the exact activation/re-trigger cycle empirically (how many
-- ticks after activation does flag clear and the object become eligible again), since that's
-- governed by a generic, non-spell-specific sprite-animation subsystem
-- (FUN_801238e0/FUN_800e2044/FUN_800e2a9c) whose frame-count/delay data lives in a resource
-- table this trace sidesteps by just observing the real per-tick state directly.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceExplosionPools.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function ctxBase()
  return Address.sanitize(mainmemory.read_u32_le(0x17a030))
end

local function poolState(baseSlotOffset, count)
  local ctx = ctxBase()
  local sched, flag = {}, {}
  for i = 0, count - 1 do
    local ptrAddr = ctx + (baseSlotOffset + i) * 4
    local obj = Address.sanitize(mainmemory.read_u32_le(ptrAddr))
    sched[i] = mainmemory.read_u32_le(obj + 0x24)
    flag[i] = mainmemory.read_u32_le(obj + 0x1c)
  end
  return sched, flag
end

local function fmtArr(t, n)
  local parts = {}
  for i = 0, n - 1 do parts[#parts + 1] = tostring(t[i]) end
  return table.concat(parts, ",")
end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Explosion.State")

  -- Fast-forward to case3 tick 0 (224 ticks * 2 frames/tick = 448 frames of case0/1/2).
  for _ = 1, 448 do emu.frameadvance() end

  local ctx = ctxBase()
  local phase = mainmemory.read_u32_le(ctx + 0x51 * 4)
  local tick0 = mainmemory.read_u32_le(ctx + 0x52 * 4)
  log(string.format("Arrived at phase=%d tick=%d (expect phase=3 tick=0)", phase, tick0))

  for tick = 0, 100 do
    local rng = mainmemory.read_u32_le(Address.RNG)
    local schedA, flagA = poolState(0x34, 15)
    local schedB, flagB = poolState(0x20, 20)
    log(string.format("tick=%-3d rng=0x%08x A_sched=[%s] A_flag=[%s] B_sched=[%s] B_flag=[%s]",
      tick, rng, fmtArr(schedA, 15), fmtArr(flagA, 15), fmtArr(schedB, 20), fmtArr(flagB, 20)))
    emu.frameadvance()
    emu.frameadvance()
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
