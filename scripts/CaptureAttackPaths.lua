-- Live capture for scripts/python/AttackTimingCompare.py --paths: logs every combatant's attack
-- continuation (combatant_rec+0x50), busy byte (EnemyData+5), effect flags (EnemyData+0x40),
-- anim target (EnemyData+4) and HP whenever any of them changes, so miss / counter / cover
-- timings can be checked against AttackTimingWalker.walk_path.
--
-- Setups (all actions in-spec: Free Will's own picks or Defend; values stay in range):
--   A  KasumiMoraviaSoldiersCounterTest.State, party SKL pinned to 1 (hit chance floor 60%):
--      party misses -> Elite Soldier counters (McDohl), long-range fall-through hits
--   B  same save, whole party Defends with Hazy (Rune.Id 18, the real rune slot:
--      *(ClassPtrs[i].pClassDataPtr+0x1c)+0x4c), McDohl's HP set to 100 (< 25% of max) so
--      Kasumi covers him: enemy misses -> party dodges / counters, enemy hits -> cover
--   C  Seifu6Ant.State, party SKL pinned to 1: party misses vs a bit-2 species (ant dodges)
--
-- USAGE: scripts/spawn-headless-emuhawk.sh \
--          /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/CaptureAttackPaths.lua "" 1500

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"

local DIR = "/home/alex/Projects/Suikoden-Bizhawk-HUD/"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CaptureAttackPaths.txt"
local RUNS = 10
local MAX_FRAMES = 2400
local SETUPS = {
  { name = "A", state = "KasumiMoraviaSoldiersCounterTest.State", pinSkl = true },
  { name = "B", state = "KasumiMoraviaSoldiersCounterTest.State", defendHazy = true, coverHero = 100 },
  { name = "C", state = "Seifu6Ant.State", pinSkl = true },
}

local out = {}
local function log(s) out[#out + 1] = s end

local function base() return Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)) end
local function rec(b, i) return b + 0xb40 + i * 0x54 end
local function ed(b, i) return b + 0x50 + i * 0x8c end
local function stats(b, i) -- real PersistentStats: ClassPtrs[i].pClassDataPtr -> +0x1c
  local c = mainmemory.read_u32_le(b + 0xf84 + i * 0xc)
  if not Address.isValidPointer(c) then return nil end
  local p = mainmemory.read_u32_le(Address.sanitize(c) + 0x1c)
  return Address.isValidPointer(p) and Address.sanitize(p) or nil
end

for _, setup in ipairs(SETUPS) do
  for run = 1, RUNS do
    savestate.load(DIR .. setup.state)
    if run > 1 then mainmemory.write_u32_le(Address.RNG, (0x1234567 * run + 0x89abcdef) % 0x100000000) end
    local b = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
    if not b then
      log(string.format("RUN %s %d: round prompt never became ready", setup.name, run))
    else
      local party = mainmemory.read_u32_le(b + 0x1c)
      local total = mainmemory.read_u32_le(b + 0x24)
      log(string.format("RUN %s %d party=%d total=%d", setup.name, run, party, total))
      for i = 1, total do
        local st = i <= party and stats(b, i) or nil
        if setup.defendHazy and i <= party then
          BattleRoundInput:setAction(i, 1, 0, 0)
          if st then mainmemory.write_u8(st + 0x4c, 18) end
        end
        if setup.coverHero and i <= party and mainmemory.read_u8(ed(b, i)) == 8 then
          mainmemory.write_u16_le(rec(b, i) + 0x12, setup.coverHero)
        end
        if i <= party then
          log(string.format("C %d party id=%d runePiece=%d rune=%d pos=%d act=%d hp=%d/%d", i,
            mainmemory.read_u8(ed(b, i)), st and mainmemory.read_u8(st + 0x46) or -1,
            st and mainmemory.read_u8(st + 0x4c) or -1, mainmemory.read_u8(rec(b, i) + 0x44),
            mainmemory.read_u8(rec(b, i) + 0x47), mainmemory.read_u16_le(rec(b, i) + 0x12),
            mainmemory.read_u16_le(rec(b, i) + 0x10)))
        else
          log(string.format("C %d enemy table=0x%08x pos=%d", i, mainmemory.read_u32_le(ed(b, i) + 8),
            mainmemory.read_u8(rec(b, i) + 0x44)))
        end
      end
      BattleRoundInput:confirmRound()

      local last, idle = {}, 0
      for n = 1, MAX_FRAMES do
        emu.frameadvance()
        b = base()
        if setup.pinSkl and n >= 8 then
          for i = 1, party do mainmemory.write_u8(rec(b, i) + 0x26, 1) end
        end
        for i = 1, total do
          local r, e = rec(b, i), ed(b, i)
          local s = string.format("cont=%08x busy=%d fx=%04x at=%d hp=%d", mainmemory.read_u32_le(r + 0x50),
            mainmemory.read_u8(e + 5), mainmemory.read_u16_le(e + 0x40), mainmemory.read_u8(e + 4),
            mainmemory.read_u16_le(r + 0x12))
          if s ~= last[i] then
            log(string.format("F%d %d %s", n, i, s))
            last[i] = s
          end
        end
        local done = true
        for i = 1, total do
          local r = rec(b, i)
          if mainmemory.read_u8(r + 0x46) == 0 and mainmemory.read_u8(r + 0x45) == 0 then done = false end
          if mainmemory.read_u8(ed(b, i) + 5) ~= 0 then done = false end
        end
        idle = done and idle + 1 or 0
        if idle > 60 then break end
      end
    end
  end
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(out, "\n") .. "\n"); file:close() end
client.exit()
