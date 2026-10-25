-- HEADLESS ONLY (ends with client.exit()). Tests lib/ForceBattle.lua from savestates/ForceBattleBaseSave.State: every
-- Mt. Seifu random group (slots checked against lib/EncounterTable.lua), the two scripted tables of the Queen Ant room,
-- a stay-on-screen request, and the refusal paths. Globals: TEST_OUT. One line per case: OK / FAIL <why>.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local ForceBattle = require "lib.ForceBattle"
local ScreenTeleport = require "lib.ScreenTeleport"
local EncounterTable = require "lib.EncounterTable"
local Areas = require "lib.Enums.Areas.Areas_All"
local OUT = TEST_OUT or "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestForceBattle.txt"
local START = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/ForceBattleBaseSave.State"
local f = io.open(OUT, "w"); f:close()
local function log(s) local h = io.open(OUT, "a"); h:write(s .. "\n"); h:close() end
pcall(function() client.speedmode(6400) end)

local function load()
  savestate.load(START)
  for _ = 1, 4 do emu.frameadvance() end
end

local function slotsOf(digits)
  local s = {}
  for i = 1, 6 do s[i] = tonumber(digits:sub(i, i)) end
  return s
end

local function same(a, b)
  for i = 1, 6 do if a[i] ~= b[i] then return false end end
  return true
end

local function run(opts, wantSlots, label)
  load()
  local ok, why = ForceBattle.request(opts)
  if not ok then return log(string.format("FAIL %s request refused: %s", label, why)) end
  local frames = 0
  while ForceBattle.busy() and frames < 4000 do ForceBattle.tick(); emu.frameadvance(); frames = frames + 1 end
  local msg, r = ForceBattle.lastMessage or "?", ForceBattle.lastResult
  if msg:sub(1, 14) == "battle started" and r and same(r.slots, wantSlots) then
    log(string.format("OK   %s %s frames=%d", label, msg, frames))
  else
    log(string.format("FAIL %s msg=%s slots=%s", label, msg, r and table.concat(r.slots, ",") or "-"))
  end
end

local function refused(opts, label)
  load()
  local ok, why = ForceBattle.request(opts)
  if not ok then return log("OK   " .. label .. " refused: " .. why) end
  local frames = 0
  while ForceBattle.busy() and frames < 4000 do ForceBattle.tick(); emu.frameadvance(); frames = frames + 1 end
  local msg = ForceBattle.lastMessage or "?"
  log((msg:sub(1, 6) == "FAILED" and "OK   " or "FAIL ") .. label .. " -> " .. msg)
end

local seifu = EncounterTable[Areas.MT_SEIFU]
for g, digits in ipairs(seifu.encounters) do
  local ok, err = pcall(run, { wm = 0, area = 6, screen = 2, x = 7, y = 53, group = g }, slotsOf(digits),
    string.format("Seifu 0/6/2 random group %d (%s)", g, digits))
  if not ok then log("FAIL ERR " .. tostring(err)) end
end
pcall(run, { wm = 0, area = 6, screen = 9, x = 53, y = 10, scripted = 0 }, { 2, 2, 2, 1, 0, 0 }, "Queen Ant 0/6/9 scripted B=0")
pcall(run, { wm = 0, area = 6, screen = 9, x = 53, y = 10, scripted = 1 }, { 0, 0, 0, 1, 0, 0 }, "Queen Ant 0/6/9 scripted B=1")

-- Teleport by hand, then force on the current screen (no wm in opts).
pcall(function()
  load()
  ScreenTeleport.request(0, 6, 2, 7, 53)
  while ScreenTeleport.busy() do ScreenTeleport.tick(); emu.frameadvance() end
  for _ = 1, 20 do emu.frameadvance() end
  local ok, why = ForceBattle.request({ group = 2 })
  if not ok then return log("FAIL stay-on-screen refused: " .. why) end
  local frames = 0
  while ForceBattle.busy() and frames < 4000 do ForceBattle.tick(); emu.frameadvance(); frames = frames + 1 end
  local r = ForceBattle.lastResult
  log((r and same(r.slots, slotsOf(seifu.encounters[2])) and "OK   " or "FAIL ") .. "stay-on-screen group 2: " .. tostring(ForceBattle.lastMessage))
end)

-- ForceBattle.list() on a freshly loaded screen: counts per kind, and the texts for eyeballing.
local function listCase(wm, area, screen, x, y, wantRandom, wantScripted, label)
  local ok, err = pcall(function()
    load()
    ScreenTeleport.request(wm, area, screen, x, y)
    while ScreenTeleport.busy() do ScreenTeleport.tick(); emu.frameadvance() end
    local l, why = ForceBattle.list()
    if not l then return log("FAIL list " .. label .. ": " .. tostring(why)) end
    local random, scripted, texts = 0, 0, {}
    for _, e in ipairs(l.entries) do
      if e.kind == "random" then random = random + 1 else scripted = scripted + 1 end
      texts[#texts + 1] = (e.kind == "random" and "R" .. e.group or "S" .. e.scripted) .. "=" .. e.text
    end
    local rate = l.random and string.format("rate %d grace %d", l.random.rate, l.random.grace) or "no random block"
    log(string.format("%s list %s: %d random, %d scripted (%s) | %s", (random == wantRandom and scripted == wantScripted) and "OK  " or "FAIL", label, random, scripted, rate, table.concat(texts, " | ")))
  end)
  if not ok then log("FAIL ERR list " .. label .. ": " .. tostring(err)) end
end
listCase(0, 6, 2, 7, 53, 5, 0, "Seifu 0/6/2")
listCase(0, 6, 9, 53, 10, 5, 2, "Queen Ant 0/6/9")
listCase(0, 6, 0, 38, 17, 5, 0, "Seifu entrance 0/6/0")

pcall(refused, { wm = 0, area = 6, screen = 2, x = 7, y = 53, group = 6 }, "Seifu group 6 (table has 5)")
pcall(refused, { wm = 0, area = 6, screen = 2, x = 7, y = 53, scripted = 0 }, "Seifu scripted B=0 (no scripted tables)")
pcall(refused, { wm = 0 }, "wm without area/screen/x/y")
-- World map (savestates/ForceBattleWorldMap.State): list, force every listed group, compare with the encounter seen
-- when walking into a real one (group 6 -> slots 2,2,0,0,0,0, traced 2026-10-24), and the refusals.
local WM_START = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/ForceBattleWorldMap.State"
local function loadWM()
  savestate.load(WM_START)
  for _ = 1, 4 do emu.frameadvance() end
end
local function runTicks()
  local frames = 0
  while ForceBattle.busy() and frames < 4000 do ForceBattle.tick(); emu.frameadvance(); frames = frames + 1 end
  return frames
end
pcall(function()
  loadWM()
  local l, why = ForceBattle.list()
  if not l then return log("FAIL WM list: " .. tostring(why)) end
  local texts = {}
  for _, e in ipairs(l.entries) do texts[#texts + 1] = "R" .. e.group .. "=" .. e.text end
  log(string.format("%s WM list: worldMap=%s %d entries | %s", (l.worldMap and #l.entries >= 6) and "OK  " or "FAIL", tostring(l.worldMap), #l.entries, table.concat(texts, " | ")))
  for _, e in ipairs(l.entries) do
    loadWM()
    local ok, err = ForceBattle.request({ group = e.group })
    if not ok then log(string.format("FAIL WM group %d refused: %s", e.group, err))
    else
      local frames = runTicks()
      local r = ForceBattle.lastResult
      local good = (ForceBattle.lastMessage or ""):sub(1, 14) == "battle started" and r and r.groupSize == e.size
      if good and e.group == 6 then good = same(r.slots, { 2, 2, 0, 0, 0, 0 }) end
      log(string.format("%s WM group %d (%s) %s frames=%d", good and "OK  " or "FAIL", e.group, e.text, tostring(ForceBattle.lastMessage), frames))
    end
  end
end)
pcall(function()
  loadWM()
  local ok, why = ForceBattle.request({ group = 99 })
  if not ok then return log("OK   WM group 99 refused: " .. why) end
  runTicks()
  local msg = ForceBattle.lastMessage or "?"
  log((msg:sub(1, 6) == "FAILED" and "OK   " or "FAIL ") .. "WM group 99 -> " .. msg)
end)
pcall(function()
  loadWM()
  local ok, why = ForceBattle.request({ scripted = 0 })
  if not ok then return log("OK   WM scripted refused: " .. why) end
  runTicks()
  local msg = ForceBattle.lastMessage or "?"
  log((msg:sub(1, 6) == "FAILED" and "OK   " or "FAIL ") .. "WM scripted -> " .. msg)
end)
pcall(function()
  loadWM()
  local ok, why = ForceBattle.request({ wm = 0, area = 6, screen = 2, x = 7, y = 53 })
  if ok then runTicks() end
  local msg = ok and (ForceBattle.lastMessage or "?") or why
  log(((not ok) or msg:sub(1, 6) == "FAILED") and ("OK   WM teleport request: " .. msg) or ("FAIL WM teleport request: " .. msg))
end)

log("DONE")
client.exit()
