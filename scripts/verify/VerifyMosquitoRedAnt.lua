-- Live check of Mosquito / Red Solider Ant AI and attack timings against the static predictions
-- (outputs/AttackTimingsClean.json + the Red Solider Ant DoubleStrike walk, see
-- docs/game_mechanics/Battle_Damage_Formula.md's regular-enemy sweep).
-- Loads 3Mosquito1Ant.State, picks Free Will, sets every party member to Defend so the enemies
-- survive and keep attacking, confirms, and logs per-frame state for every combatant for up to
-- ROUNDS rounds per RNG seed. Everything is polled once per frame (end-of-frame state):
--   busy    enemy_data+0x05   fx  enemy_data+0x40   cursor  enemy_data+0x0c
--   hp      combatant_rec+0x12   tag +0x46   tgt +0x49
--   RNG     full LCG value, logged with step count whenever it changes (replayed offline)
--   gate    BattleState+0x1264, current actor BattleState+0x8
-- Analysis: scripts/python/VerifyMosquitoRedAntCompare.py.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh \
--          /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/verify/VerifyMosquitoRedAnt.lua "" 900

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/3Mosquito1Ant.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/VerifyMosquitoRedAnt.txt"
local SEEDS = { false, 0x5eed1234, 0x33333333, 0x11111111, 0x0badf00d, 0x2468ace0,
                0x13579bdf, 0x7e57c0de }
local ROUNDS = 4
local MAX_FRAMES = 3000
local DEFEND = 1

local file = io.open(OUTPUT_FILE, "w")
local function log(s) file:write(s, "\n") end

local function lcgNext(s)
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

local function logLayout(b, party, total)
  for i = 1, total do
    local e, r = ed(b, i), rec(b, i)
    local tab = mainmemory.read_u32_le(e + 0x8)
    log(string.format("LAYOUT %d id=%d table=0x%08x hp=%d/%d form=%d dead=%d tag=%d busy=%d",
      i, mainmemory.read_s8(e), tab, mainmemory.read_s16_le(r + 0x12),
      mainmemory.read_s16_le(r + 0x14), mainmemory.read_u8(r + 0x44),
      mainmemory.read_u8(r + 0x45), mainmemory.read_u8(r + 0x46), mainmemory.read_u8(e + 0x5)))
  end
end

local function runRound(runIdx, roundIdx)
  local b = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not b then log(string.format("RUN %d ROUND %d: no prompt", runIdx, roundIdx)); return false end
  local party = mainmemory.read_u32_le(b + 0x1c)
  local total = mainmemory.read_u32_le(b + 0x24)
  local actions = {}
  for i = 1, party do actions[i] = { DEFEND, 0, 0 } end
  BattleRoundInput:setActions(actions)
  log(string.format("ROUND %d party=%d total=%d round=%d freewill=%d", roundIdx, party, total,
    mainmemory.read_u32_le(b + 0x4), mainmemory.read_s32_le(0x17be44)))
  logLayout(b, party, total)
  BattleRoundInput:confirmRound()

  local prev = {}
  local lastRng = mainmemory.read_u32_le(Address.RNG)
  log(string.format("F 0 RNGSTART 0x%08x", lastRng))
  local f0 = emu.framecount()
  for n = 1, MAX_FRAMES do
    emu.frameadvance()
    b = base()
    local fr = emu.framecount() - f0
    local rng = mainmemory.read_u32_le(Address.RNG)
    if rng ~= lastRng then
      log(string.format("F %d RNG 0x%08x -> 0x%08x steps=%d", fr, lastRng, rng, rngSteps(lastRng, rng)))
      lastRng = rng
    end
    local cur = mainmemory.read_u32_le(b + 0x8)
    local gate = mainmemory.read_s32_le(b + 0x1264)
    if cur ~= prev.cur or gate ~= prev.gate then
      log(string.format("F %d CURRENT %d gate=%d", fr, cur, gate)); prev.cur = cur; prev.gate = gate
    end
    for i = 1, total do
      local e, r = ed(b, i), rec(b, i)
      local st = { mainmemory.read_u8(e + 0x5), mainmemory.read_u16_le(e + 0x40),
                   mainmemory.read_s16_le(r + 0x12), mainmemory.read_u8(r + 0x46),
                   mainmemory.read_u8(r + 0x49), mainmemory.read_u32_le(e + 0xc),
                   mainmemory.read_u8(r + 0x45), mainmemory.read_u32_le(r + 0x50) }
      local p = prev[i]
      local changed = not p
      if p then for k = 1, #st do if p[k] ~= st[k] then changed = true end end end
      if changed then
        log(string.format("F %d A %d busy=%d fx=0x%x hp=%d tag=%d tgt=%d cursor=0x%08x dead=%d cont=0x%08x",
          fr, i, st[1], st[2], st[3], st[4], st[5], st[6], st[7], st[8]))
        prev[i] = st
      end
    end
    local done = true
    for i = 1, total do
      if mainmemory.read_u8(rec(b, i) + 0x46) == 0 and mainmemory.read_u8(rec(b, i) + 0x45) == 0 then
        done = false
      end
      if mainmemory.read_u8(ed(b, i) + 0x5) ~= 0 then done = false end
    end
    if done then
      prev.idle = (prev.idle or 0) + 1
      if prev.idle > 120 then log(string.format("F %d ROUND DONE", fr)); return true end
    else
      prev.idle = 0
    end
  end
  log("ROUND TIMEOUT")
  return false
end

for run, seed in ipairs(SEEDS) do
  savestate.load(SAVESTATE)
  if seed then mainmemory.write_u32_le(Address.RNG, seed) end
  log(string.format("RUN %d seed=%s", run, seed and string.format("0x%08x", seed) or "state"))
  for r = 1, ROUNDS do
    local ok, res = pcall(runRound, run, r)
    if not ok then log("ERROR " .. tostring(res)); break end
    if not res then break end
  end
  file:flush()
end

file:close()
client.exit()
