-- Live check of the cover mechanic (find_cover_target 0x800f79e0 / battle_check_counter_attack
-- 0x800f4d5c) on 3Mosquito1Ant.State (Hero, Gremio, Pahn front; Ted, Cleo back), party Defending,
-- round 1 only per run. Modes (applied after the round prompt, before confirm):
--   PROBE  no changes; logs each party member's HPMax (+0x10) and the first 16 bytes that
--          classPtrs[i] (base+0xf84+i*0xc) points at, to match against data/04_play headers
--   AT     Hero HP = floor(HPMax/4)      -> expect no cover (strict <)
--   BELOW  Hero HP = floor(HPMax/4) - 1  -> expect Gremio (or Pahn if Gremio busy) to cover
--   KO     Gremio + Pahn KO'd (HP 0, +0x45 = 1), Hero HP = T - 1 -> expect back-row Cleo to cover
--   PHERO  Pahn Rune.Id (persistent +0x4c) = 26 (Phero), Pahn HP = T_pahn - 1 -> the Phero scan
--          from slot 4 (Ted, male) should pick slot 5 (Cleo, female)
-- Per-frame format matches VerifyMosquitoRedAnt.lua, so VerifyMosquitoRedAntCompare's parser
-- reads it. Analysis: scripts/python/VerifyCoverCompare.py.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh \
--          /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/verify/VerifyCover.lua "" 900

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/3Mosquito1Ant.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/VerifyCover.txt"
local SEEDS = { false, 0x5eed1234, 0x33333333, 0x11111111, 0x0badf00d, 0x2468ace0 }
local MODES = { "PROBE", "AT", "BELOW", "KO", "PHERO" }
local ROUNDS = 1
local HERO, GREMIO, PAHN = 1, 2, 3
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

local MODE = "PROBE"

local function hpMax(b, i) return mainmemory.read_s16_le(rec(b, i) + 0x10) end
local function setHP(b, i, hp) mainmemory.write_s16_le(rec(b, i) + 0x12, hp) end
local function classPtr(b, i) return Address.sanitize(mainmemory.read_u32_le(b + 0xf84 + i * 0xc)) end

function setup(b, party)
  for i = 1, party do
    local cp = classPtr(b, i)
    local bytes = {}
    for k = 0, 15 do bytes[#bytes + 1] = string.format("%02x", mainmemory.read_u8(cp + k)) end
    local stats = Address.sanitize(mainmemory.read_u32_le(cp + 0x1c))
    log(string.format("PROBE %d hpmax=%d hp=%d classPtr=0x%08x rune=%d bytes=%s", i, hpMax(b, i),
      mainmemory.read_s16_le(rec(b, i) + 0x12), cp, mainmemory.read_u8(stats + 0x4c), table.concat(bytes, " ")))
  end
  local T = hpMax(b, HERO) // 4
  if MODE == "AT" then setHP(b, HERO, T)
  elseif MODE == "BELOW" then setHP(b, HERO, T - 1)
  elseif MODE == "KO" then
    setHP(b, HERO, T - 1)
    for _, i in ipairs({ GREMIO, PAHN }) do
      setHP(b, i, 0)
      mainmemory.write_u8(rec(b, i) + 0x45, 1)
    end
  elseif MODE == "PHERO" then
    local stats = Address.sanitize(mainmemory.read_u32_le(classPtr(b, PAHN) + 0x1c))
    mainmemory.write_u8(stats + 0x4c, 26)
    setHP(b, PAHN, hpMax(b, PAHN) // 4 - 1)
  end
  log(string.format("SETUP mode=%s heroT=%d pahnT=%d", MODE, T, hpMax(b, PAHN) // 4))
end

local function runRound(runIdx, roundIdx)
  local b = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not b then log(string.format("RUN %d ROUND %d: no prompt", runIdx, roundIdx)); return false end
  local party = mainmemory.read_u32_le(b + 0x1c)
  local total = mainmemory.read_u32_le(b + 0x24)
  local actions = {}
  for i = 1, party do actions[i] = { DEFEND, 0, 0 } end
  BattleRoundInput:setActions(actions)
  setup(b, party)
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

local run = 0
for _, mode in ipairs(MODES) do
 MODE = mode
 for _, seed in ipairs(mode == "PROBE" and { false } or SEEDS) do
  run = run + 1
  savestate.load(SAVESTATE)
  if seed then mainmemory.write_u32_le(Address.RNG, seed) end
  log(string.format("RUN %d mode=%s seed=%s", run, mode, seed and string.format("0x%08x", seed) or "state"))
  for r = 1, ROUNDS do
    local ok, res = pcall(runRound, run, r)
    if not ok then log("ERROR " .. tostring(res)); break end
    if not res then break end
  end
  file:flush()
 end
end

file:close()
client.exit()
