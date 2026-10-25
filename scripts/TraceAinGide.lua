-- Live trace of Ain Gide's turn (AinGide.State, round 1, lone enemy). Plan approved by the user
-- 2026-10-07. Per round, per seed: roster snapshot (formation pos, alive, busy) and the RNG seed
-- at the frame he becomes the current actor (T0), then every event relative to T0: each frame with
-- rand() calls (exact count via LCG step-counting), his ActionTag/busy/+0x40 fx/+0x42 phase/+0x54
-- callback, battle+0x0c continuation, the target he locked (combatant_rec[self]+0x49, battle+0x125c),
-- every party member's busy and HP change, the gate reset and the next actor.
-- Whole party Defends; living party HP is restored to HPMax each round start.
-- Offline checker: scripts/python/CheckAinGideTrace.py.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh \
--          /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/TraceAinGide.lua "" 1500

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/AinGide.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceAinGide.txt"
local SEEDS, ROUNDS = tonumber(os.getenv("AG_SEEDS")) or 12, 2
local MAX_ROUND_FRAMES = 2400

local outFile = io.open(OUTPUT_FILE, "w")
local function log(s)
  if outFile then outFile:write(s .. "\n"); outFile:flush() end
end
pcall(function() client.speedmode(6400) end)
local function base() return Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)) end
local function rec(b, i) return b + 0xb40 + i * 0x54 end
local function ed(b, i) return b + 0x50 + i * 0x8c end
local function step(s) return (s * 0x41c64e6d + 0x3039) % 0x100000000 end
local function randSteps(from, to)
  local s = from
  for n = 0, 20000 do
    if s == to then return n end
    s = step(s)
  end
  return -1
end

local function round(label)
  local b = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not b then log(label .. ": round prompt never became ready"); return false end
  local party, total = mainmemory.read_u32_le(b + 0x1c), mainmemory.read_u32_le(b + 0x24)
  local me = total -- lone enemy: last actor
  if total ~= party + 1 then log(label .. ": expected 1 enemy, party=" .. party .. " total=" .. total) end
  for i = 1, party do
    local r = rec(b, i)
    if mainmemory.read_u8(r + 0x45) == 0 then
      mainmemory.write_s16_le(r + 0x12, mainmemory.read_s16_le(r + 0x10))
    end
    BattleRoundInput:setAction(i, 1, 0, 0)
  end
  local roster = {}
  for i = 1, party do
    roster[#roster + 1] = string.format("#%d pos%d dead%d hp%d/%d", i, mainmemory.read_u8(rec(b, i) + 0x44),
      mainmemory.read_u8(rec(b, i) + 0x45), mainmemory.read_s16_le(rec(b, i) + 0x12), mainmemory.read_s16_le(rec(b, i) + 0x10))
  end
  log(string.format("%s: me=#%d round=%d RNGstart=%08x", label, me, mainmemory.read_u32_le(b + 0x4),
    mainmemory.read_u32_le(Address.RNG)))
  log("  roster " .. table.concat(roster, "; "))
  BattleRoundInput:confirmRound()
  b = base()

  local prevSeed = mainmemory.read_u32_le(Address.RNG)
  local function snap()
    local s = { act = mainmemory.read_u32_le(b + 0x8), gate = mainmemory.read_s32_le(b + 0x1264),
      c0c = mainmemory.read_u32_le(b + 0x0c), tag = mainmemory.read_u8(rec(b, me) + 0x46),
      tgt = mainmemory.read_u8(rec(b, me) + 0x49), t125c = mainmemory.read_u32_le(b + 0x125c),
      busy = mainmemory.read_u8(ed(b, me) + 5), fx = mainmemory.read_u16_le(ed(b, me) + 0x40),
      st = mainmemory.read_u16_le(ed(b, me) + 0x42), cb = mainmemory.read_u32_le(ed(b, me) + 0x54),
      pb = {}, hp = {}, tb = {} }
    for i = 1, party do
      s.pb[i] = mainmemory.read_u8(ed(b, i) + 5)
      s.hp[i] = mainmemory.read_s16_le(rec(b, i) + 0x12)
    end
    return s
  end
  local prev = snap()
  local T0
  local function rel(f) return T0 and ("T+" .. (f - T0)) or ("F" .. f) end
  local function add(f, what) log("  " .. rel(f) .. " " .. what) end
  local startPhase = mainmemory.read_u32_le(b + 0x3428)
  local meDone = false
  for f = 1, MAX_ROUND_FRAMES do
    emu.frameadvance()
    b = base()
    local seed = mainmemory.read_u32_le(Address.RNG)
    local n = randSteps(prevSeed, seed)
    local s = snap()
    if s.act == me and prev.act ~= me and not T0 then
      T0 = f
      add(f, string.format("Ain Gide becomes current actor; RNG(before this frame's rolls)=%08x round=%d", prevSeed,
        mainmemory.read_u32_le(b + 0x4)))
      add(f, string.format("RNG now %08x", seed))
    end
    if n ~= 0 then add(f, string.format("rand x%d (seed %08x)", n, seed)) end
    prevSeed = seed
    if s.act ~= prev.act then add(f, string.format("act %d -> %d", prev.act, s.act)) end
    if s.tag ~= prev.tag then add(f, string.format("AG ActionTag %d -> %d", prev.tag, s.tag)) end
    if s.tgt ~= prev.tgt then add(f, string.format("AG TargetIdx(+0x49) %d -> %d", prev.tgt, s.tgt)) end
    if s.t125c ~= prev.t125c then add(f, string.format("battle+0x125c %d -> %d", prev.t125c, s.t125c)) end
    if s.busy ~= prev.busy then add(f, string.format("AG busy %d -> %d", prev.busy, s.busy)) end
    if s.fx ~= prev.fx then add(f, string.format("AG fx %04x -> %04x", prev.fx, s.fx)) end
    if s.st ~= prev.st then add(f, string.format("AG +0x42 %d -> %d", prev.st, s.st)) end
    if s.cb ~= prev.cb then add(f, string.format("AG +0x54 %08x -> %08x", prev.cb, s.cb)) end
    if s.c0c ~= prev.c0c then add(f, string.format("battle+0x0c %08x -> %08x", prev.c0c, s.c0c)) end
    if s.gate > prev.gate then add(f, string.format("gate reset %d -> %d", prev.gate, s.gate)) end
    local hits = {}
    for i = 1, party do
      if s.pb[i] ~= prev.pb[i] then add(f, string.format("#%d busy %d -> %d", i, prev.pb[i], s.pb[i])) end
      if s.hp[i] < prev.hp[i] then hits[#hits + 1] = string.format("#%d -%d", i, prev.hp[i] - s.hp[i]) end
    end
    if #hits > 0 then add(f, "damage: " .. table.concat(hits, " ") .. string.format(" (rand this frame %d)", n)) end
    if T0 and prev.act == me and s.act ~= me then meDone = true end
    prev = s
    if f > 60 and mainmemory.read_u32_le(b + 0x3428) ~= startPhase
      and mainmemory.read_u32_le(b + 0x3428) == 0 then
      add(f, "round driver back to phase 0")
      break
    end
  end
  return true
end

local ok, err = pcall(function()
  for s = 1, SEEDS do
    savestate.load(SAVESTATE)
    if s > 1 then
      mainmemory.write_u32_le(Address.RNG, (0x1234567 * s + 0x89abcdef) % 0x100000000)
    end
    for r = 1, ROUNDS do
      if not round(string.format("s%d r%d", s, r)) then break end
    end
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end
if outFile then outFile:close() end
client.exit()
