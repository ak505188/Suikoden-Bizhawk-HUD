-- Wind of Sleep (spell id 13, Wind Lv1) live capture. WindOfSleep.State, McDohl in formation slot 1; his rune
-- is set to Wind (id 4, user-approved edit), all MP 9, Rune slot 1 -> first enemy, others Defend.
-- Part 1 (native RNG): per-frame log from the setup handler 0x80108b80 on: rand() count per frame (only
--   frames with calls), the tick machine's phase/tick (ctx = pointer at 0x17a048: phase +0x104, tick +0x100),
--   each enemy's HP and ailment slot, and the end-handler frame. Also dumps the enemy count/ids.
-- Part 2: 20 injected seeds, totals only: LCG steps setup-frame RNG -> end-handler-frame RNG, plus steps from
--   there to the next-actor frame (the post-spell window), for each seed.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/WindOfSleep.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CaptureWindOfSleep.txt"
local SEEDS = { 0x11111111, 0xcafebabe, 0xdeadbeef, 0x00000001, 0x7fffffff, 0x9e3779b9, 0x12345678, 0xa5a5a5a5,
  0x00c0ffee, 0x1badb002, 0x5eadbeef, 0x8badf00d, 0xfeedface, 0x0defaced, 0xabad1dea, 0x31337000, 0x42424242,
  0x55555555, 0xaaaaaaaa, 0xfffffffe }
local CASTER, RUNE, SLOT, WIND = 8, 2, 1, 4
local SETUP, END = 0x80108b80, 0x80109358
local CTX = 0x17a048
local function lcg(x) return (x * 0x41c64e6d + 0x3039) % 0x100000000 end
local function steps(from, to)
  local x, n = from, 0
  while x ~= to and n < 20000 do x = lcg(x); n = n + 1 end
  return x == to and n or -1
end
local out = {}
local function log(s) out[#out + 1] = s end
local function base() return Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)) end
local function ed(b, i) return b + 0x50 + i * 0x8c end
local function rec(b, i) return b + 0xb40 + i * 0x54 end

local function prepare(seed)
  savestate.load(SAVESTATE)
  local b
  for _ = 1, 8 do b = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL); if b then break end end
  if not b then return nil end
  if seed then mainmemory.write_u32_le(Address.RNG, seed) end
  local party = mainmemory.read_u32_le(b + 0x1c)
  local total = mainmemory.read_u32_le(b + 0x24)
  local casterIdx
  for i = 1, party do
    if mainmemory.read_u8(ed(b, i)) == CASTER then
      casterIdx = i
      local c = mainmemory.read_u32_le(b + 0xf84 + i * 0xc)
      local st = Address.sanitize(mainmemory.read_u32_le(Address.sanitize(c) + 0x1c))
      mainmemory.write_u8(st + 0x4c, WIND)
      for o = 9, 12 do mainmemory.write_u8(st + o, 9) end
      local set = Address.sanitize(mainmemory.read_u32_le(0x16a0e0 + WIND * 4))
      local def = Address.sanitize(mainmemory.read_u32_le(0x16d33c + mainmemory.read_u8(set + 0x1a + SLOT) * 4))
      local tt = mainmemory.read_u16_le(def + 0x16) & 3
      log(string.format("slot %d -> spell id %d targetType=%d party=%d total=%d", SLOT,
        mainmemory.read_u8(set + 0x1a + SLOT), tt, party, total))
      BattleRoundInput:setAction(i, RUNE, SLOT, tt == 2 and i or (tt == 3 and party + 1 or 0))
    else BattleRoundInput:setAction(i, 1, 0, 0) end
  end
  BattleRoundInput:confirmRound()
  return b, casterIdx, party, total
end

-- Part 1: detailed
do
  local b, casterIdx, party, total = prepare(nil)
  if not b then log("part1: round prompt never ready")
  else
    for i = party + 1, total do
      log(string.format("enemy idx %d id=%d hp=%d recbyte0x45=%d flags26=%04x", i, mainmemory.read_u8(ed(b, i)),
        mainmemory.read_u16_le(rec(b, i) + 0x12), mainmemory.read_u8(rec(b, i) + 0x45), 0))
    end
    local last = mainmemory.read_u32_le(Address.RNG)
    local t0, endN
    for n = 1, 1500 do
      emu.frameadvance()
      b = base()
      local h = mainmemory.read_u32_le(b + 0x14)
      local rng = mainmemory.read_u32_le(Address.RNG)
      local c = rng ~= last and steps(last, rng) or 0
      if not t0 and h == SETUP then t0 = n; log(string.format("F%d setup handler, rng=%08x", n, rng)) end
      if t0 then
        local ctx = Address.sanitize(mainmemory.read_u32_le(CTX))
        local ph, tk = -1, -1
        if h ~= SETUP and ctx ~= 0 then ph, tk = mainmemory.read_u32_le(ctx + 0x104), mainmemory.read_u32_le(ctx + 0x100) end
        if c ~= 0 or h == END and not endN then
          log(string.format("+%d h=%08x ph=%d tk=%d rand=%d", n - t0, h, ph, tk, c))
        end
        if h == END and not endN then endN = n end
        if endN and mainmemory.read_u32_le(b + 0x8) ~= casterIdx then
          log(string.format("+%d next actor (end handler at +%d)", n - t0, endN - t0)); break
        end
      end
      last = rng
    end
  end
end

-- Part 2: seeds
for _, seed in ipairs(SEEDS) do
  local b, casterIdx = prepare(seed)
  if not b then log(string.format("seed %08x: round prompt never ready", seed))
  else
    local startRng, endRng, nextRng
    for _ = 1, 1500 do
      emu.frameadvance()
      b = base()
      local h = mainmemory.read_u32_le(b + 0x14)
      local rng = mainmemory.read_u32_le(Address.RNG)
      if not startRng and h == SETUP then startRng = rng end
      if startRng and not endRng and h == END then endRng = rng end
      if endRng and mainmemory.read_u32_le(b + 0x8) ~= casterIdx then nextRng = rng; break end
    end
    if startRng and endRng and nextRng then
      log(string.format("seed 0x%08x start 0x%08x end 0x%08x calls %d post %d", seed, startRng, endRng,
        steps(startRng, endRng), steps(endRng, nextRng)))
    else log(string.format("seed 0x%08x incomplete %s %s %s", seed, tostring(startRng), tostring(endRng), tostring(nextRng))) end
  end
end
local f = io.open(OUTPUT_FILE, "w"); f:write(table.concat(out, "\n") .. "\n"); f:close()
client.exit()
