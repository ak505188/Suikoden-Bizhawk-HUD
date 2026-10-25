-- Ain Gide's Special damage + element test (user-approved 2026-10-07: edit persistent-stats runes,
-- formation can't be edited). The Special loops party slots 1..N and calls calc_rune_element_attack_
-- damage(attacker, slot, element=1) with the loop counter in $s1 (vac.bin 0x800143b4). Question: does a
-- member with an UNLISTED Rune.Id get the accidental halving when their slot == 1, and does a Fire/Rage
-- Rune (category 1) get the real halving? Per seed and rune config: edit each living member's Rune.Id
-- (Stats +0x4c, reached the same way the function reads it: *(b+0xf84+idx*0xc)->+0x1c), set HP/HPMax
-- to 999 (the in-spec max, so a hit never clips), confirm the round (whole party Defends), and log per
-- member MGC (last value before the HP drop), Rune.Id, and the observed HP drop. Offline predictor:
-- scripts/python/CheckAinGideRunes.py.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh \
--          /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/TestAinGideRunes.lua "" 1500

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/AinGide.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestAinGideRunes.txt"
-- seeds (same numbering as TraceAinGide.lua: s1 = native, s>1 injected) that rolled the Special in round 1
local SEEDS = { 1, 2, 3, 10, 15, 20, 22 }
-- rune per party slot 1..6 (nil = leave as equipped). Rune.Id: 8 = Boar (unlisted), 0 = none, 2 = Fire,
-- 3 = Water, 1 = Soul Eater
local CONFIGS = {
  { name = "base" },
  { name = "boar_all", 8, 8, 8, 8, 8, 8 },
  { name = "none_all", 0, 0, 0, 0, 0, 0 },
  { name = "fire_all", 2, 2, 2, 2, 2, 2 },
  { name = "water_all", 3, 3, 3, 3, 3, 3 },
  { name = "soul_s1", 1, 8, 8, 8, 8, 8 },
  { name = "water_s1", 3, 8, 8, 8, 8, 8 },
  { name = "boar_s1_water_rest", 8, 3, 3, 3, 3, 3 },
}

local outFile = io.open(OUTPUT_FILE, "w")
local function log(s)
  if outFile then outFile:write(s .. "\n"); outFile:flush() end
end
pcall(function() client.speedmode(6400) end)
local function base() return Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)) end
local function rec(b, i) return b + 0xb40 + i * 0x54 end
local function ed(b, i) return b + 0x50 + i * 0x8c end
local function stats(b, i)
  local c = mainmemory.read_u32_le(b + 0xf84 + i * 0xc)
  return Address.sanitize(mainmemory.read_u32_le(Address.sanitize(c) + 0x1c))
end

local function run(sNum, cfg)
  savestate.load(SAVESTATE)
  if sNum > 1 then mainmemory.write_u32_le(Address.RNG, (0x1234567 * sNum + 0x89abcdef) % 0x100000000) end
  local b = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not b then log("RUN s" .. sNum .. " " .. cfg.name .. " ERROR no prompt"); return end
  local party, total = mainmemory.read_u32_le(b + 0x1c), mainmemory.read_u32_le(b + 0x24)
  local me = total
  for i = 1, party do
    if mainmemory.read_u8(rec(b, i) + 0x45) == 0 then
      mainmemory.write_s16_le(rec(b, i) + 0x10, 999)
      mainmemory.write_s16_le(rec(b, i) + 0x12, 999)
      if cfg[i] then mainmemory.write_u8(stats(b, i) + 0x4c, cfg[i]) end
    end
    BattleRoundInput:setAction(i, 1, 0, 0)
  end
  BattleRoundInput:confirmRound()
  b = base()
  local mgc, hp, rune = {}, {}, {}
  local function snap()
    for i = 1, party do
      mgc[i] = mainmemory.read_u16_le(rec(b, i) + 0x2c)
      hp[i] = mainmemory.read_s16_le(rec(b, i) + 0x12)
      rune[i] = mainmemory.read_u8(stats(b, i) + 0x4c)
    end
  end
  snap()
  local prevAct, T0seed, special, dmgFrame = mainmemory.read_u32_le(b + 0x8), nil, false, nil
  local prevMgc, prevRune, prevHp = {}, {}, {}
  local prevSeed = mainmemory.read_u32_le(Address.RNG)
  local agMgc
  for f = 1, 700 do
    emu.frameadvance()
    b = base()
    for i = 1, party do prevMgc[i], prevRune[i], prevHp[i] = mgc[i], rune[i], hp[i] end
    snap()
    local act = mainmemory.read_u32_le(b + 0x8)
    if act == me and prevAct ~= me and not T0seed then T0seed = prevSeed end
    if mainmemory.read_u32_le(b + 0x0c) == 0x80013d08 then special = true end
    prevAct = act
    prevSeed = mainmemory.read_u32_le(Address.RNG)
    agMgc = mainmemory.read_u16_le(rec(b, me) + 0x2c)
    local dropped = false
    for i = 1, party do if hp[i] < prevHp[i] then dropped = true end end
    if dropped then
      dmgFrame = f
      log(string.format("RUN s%d %s T0seed=%08x special=%s agMGC=%d", sNum, cfg.name, T0seed or 0, tostring(special), agMgc))
      for i = 1, party do
        log(string.format("  m %d pos %d rune %d mgc %d drop %d", i, mainmemory.read_u8(rec(b, i) + 0x44),
          prevRune[i], prevMgc[i], prevHp[i] - hp[i]))
      end
      return
    end
  end
  log(string.format("RUN s%d %s T0seed=%08x special=%s NO DAMAGE", sNum, cfg.name, T0seed or 0, tostring(special)))
end

local ok, err = pcall(function()
  for _, s in ipairs(SEEDS) do
    for _, cfg in ipairs(CONFIGS) do run(s, cfg) end
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end
if outFile then outFile:close() end
client.exit()
