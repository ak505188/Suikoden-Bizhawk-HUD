-- Live check of scripts/python/AttackTimingWalker.py's predictions (outputs/AttackTimings.json).
-- Loads ZombieDragonT2Start.State (round 2+ prompt), picks Free Will, overrides every party
-- member to a basic Attack on Zombie Dragon, confirms, then logs per-frame state changes for
-- every combatant until the round ends. Execute hooks don't fire on this core, so everything is
-- polled once per frame (end-of-frame state):
--   cursor  enemy_data+0x0c  (attack start = first frame inside the actor's slot-1 script)
--   busy    enemy_data+0x05  (bits 1 = acting, 8 = being hit)
--   fx      enemy_data+0x40  (0x2 impact, 0x4 done, 0x10 damage applied)
--   hp      combatant_rec+0x12
--   rand    LCG steps taken this frame (Address.RNG advanced from last frame's value)
-- Free Will sets the post-attack roll gate to 10; that shifts when the next actor starts, not
-- any of the per-attack animation deltas this checks. Several RNG seeds are tried so Zombie
-- Dragon rolls a basic Attack (~71%) at least once. The companion analysis is
-- scripts/python/AttackTimingCompare.py.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh \
--          /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/verify/VerifyAttackTimings.lua "" 600

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/ZombieDragonT2Start.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/VerifyAttackTimings.txt"
local DUMP_DIR = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/"
local SEEDS = { false, 0x5eed1234, 0x33333333, 0x11111111 } -- false = the state's own seed
local MAX_FRAMES = 2400

local out = {}
local function log(s) out[#out + 1] = s end

local function lcgNext(s)
  -- 32-bit s * 0x41c64e6d + 0x3039 without float overflow: split the multiplier
  local lo = (s * 0x4e6d) % 0x100000000
  local hi = ((s * 0x41c6) % 0x10000) * 0x10000
  return (lo + hi + 0x3039) % 0x100000000
end

local function rngSteps(from, to)
  if from == to then return 0 end
  local s = from
  for n = 1, 20000 do
    s = lcgNext(s)
    if s == to then return n end
  end
  return -1
end

local function base()
  return Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
end

local function ed(b, i) return b + 0x50 + i * 0x8c end
local function rec(b, i) return b + 0xb40 + i * 0x54 end

local function dumpActorFiles(b, total, tag)
  -- For matching party actors to data/04_play/<code>.bin offline: dump 0x1000 bytes from each
  -- actor's script table minus 0x34 (the table's file offset in the party files checked so far).
  for i = 1, total do
    local tab = mainmemory.read_u32_le(ed(b, i) + 0x8)
    if Address.isValidPointer(tab) then
      local start = Address.sanitize(tab) - 0x34
      local bytes = mainmemory.read_bytes_as_array(start, 0x1000)
      local f = io.open(DUMP_DIR .. string.format("VerifyAttackTimings_%s_actor%d.bin", tag, i), "wb")
      if f then
        for _, v in ipairs(bytes) do f:write(string.char(v)) end
        f:close()
      end
      log(string.format("ACTOR %d table=0x%08x slot1=0x%08x slot2=0x%08x slot4=0x%08x id=%d",
        i, tab, mainmemory.read_u32_le(Address.sanitize(tab) + 4),
        mainmemory.read_u32_le(Address.sanitize(tab) + 8),
        mainmemory.read_u32_le(Address.sanitize(tab) + 16),
        mainmemory.read_s8(ed(b, i))))
    end
  end
end

for run, seed in ipairs(SEEDS) do
  savestate.load(SAVESTATE)
  if seed then mainmemory.write_u32_le(Address.RNG, seed) end
  local b = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not b then
    log(string.format("RUN %d: round prompt never became ready", run))
  else
    local party = mainmemory.read_u32_le(b + 0x1c)
    local total = mainmemory.read_u32_le(b + 0x24)
    local actions = {}
    for i = 1, party do actions[i] = { 0, 0, party + 1 } end
    BattleRoundInput:setActions(actions)
    log(string.format("RUN %d seed=%s party=%d total=%d round=%d", run,
      seed and string.format("0x%08x", seed) or "state", party, total,
      mainmemory.read_u32_le(b + 0x4)))
    for i = 1, party do
      local r = rec(b, i)
      log(string.format("SET %d type=%d slot=%d tgt=%d", i, mainmemory.read_u8(r + 0x47),
        mainmemory.read_u8(r + 0x48), mainmemory.read_u8(r + 0x49)))
    end
    if run == 1 then dumpActorFiles(b, total, "run1") end
    BattleRoundInput:confirmRound()

    local prev = {}
    local lastRng = mainmemory.read_u32_le(Address.RNG)
    local f0 = emu.framecount()
    for n = 1, MAX_FRAMES do
      emu.frameadvance()
      b = base()
      local fr = emu.framecount() - f0
      local rng = mainmemory.read_u32_le(Address.RNG)
      local steps = rngSteps(lastRng, rng)
      lastRng = rng
      if steps ~= 0 then log(string.format("F %d RAND %d", fr, steps)) end
      local cur = mainmemory.read_u32_le(b + 0x8)
      if cur ~= prev.cur then
        log(string.format("F %d CURRENT %d", fr, cur)); prev.cur = cur
      end
      for i = 1, total do
        local e, r = ed(b, i), rec(b, i)
        local tab = mainmemory.read_u32_le(e + 0x8)
        local cursor = mainmemory.read_u32_le(e + 0xc)
        local slot1 = Address.isValidPointer(tab) and mainmemory.read_u32_le(Address.sanitize(tab) + 4) or 0
        local inSlot1 = cursor >= slot1 and cursor < slot1 + 0x200 and 1 or 0
        local state = { mainmemory.read_u8(e + 0x5), mainmemory.read_u16_le(e + 0x40),
                        mainmemory.read_s16_le(r + 0x12), inSlot1, mainmemory.read_u8(r + 0x46) }
        local p = prev[i]
        if not p or p[1] ~= state[1] or p[2] ~= state[2] or p[3] ~= state[3]
           or p[4] ~= state[4] or p[5] ~= state[5] then
          log(string.format("F %d A %d busy=%d fx=0x%x hp=%d slot1=%d tag=%d cursor=0x%08x", fr, i,
            state[1], state[2], state[3], state[4], state[5], cursor))
          prev[i] = state
        end
      end
      -- round over: every combatant has acted and nobody is busy for a while
      local done = true
      for i = 1, total do
        if mainmemory.read_u8(rec(b, i) + 0x46) == 0 and mainmemory.read_u8(rec(b, i) + 0x45) == 0 then
          done = false
        end
        if mainmemory.read_u8(ed(b, i) + 0x5) ~= 0 then done = false end
      end
      if done then
        prev.idle = (prev.idle or 0) + 1
        if prev.idle > 120 then log(string.format("F %d ROUND DONE", fr)); break end
      else
        prev.idle = 0
      end
    end
  end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(out, "\n") .. "\n"); file:close() end
client.exit()
