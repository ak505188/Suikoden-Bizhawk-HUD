-- HEADLESS ONLY: loads a savestate over whatever is running - never run in your live session.
-- Drives modules/Toolbox/Tools/PartyMembers.lua + the Toolbox worker (no controller input):
-- candidate list, guards (hero / full party / empty party), queue + cancel, paused-tick safety,
-- and that queued adds/removes really land once frames run.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local PC = require "lib.PartyChange"
local Menu = require "modules.Toolbox.Tools.PartyMembers"
local Toolbox = require "modules.Toolbox.module"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestPartyMembersMenu.txt"
local lines = {}
local function log(s) table.insert(lines, s); local f = io.open(OUT, "w"); f:write(table.concat(lines, "\n")); f:close() end
local function party()
  local t = {}
  for i = 0, PC.partySize() - 1 do t[#t + 1] = memory.read_u8(Address.PARTY_IDS + memory.read_u8(Address.FORMATION_POSITIONS + i)) end
  return "size=" .. PC.partySize() .. " [" .. table.concat(t, ",") .. "]"
end
local function select(name)
  Menu:refresh()
  for i, c in ipairs(Menu.visible) do if c.name == name then Menu.pos = i; return c end end
  error("not visible: " .. name)
end
local function press(name)
  local c = select(name); Menu:toggle(); log(string.format("toggle %-9s -> %s | queued=%d projected=%d", name, Menu.status, PC.queuedCount(), PC.projectedSize()))
end
local function runFrames(n) for _ = 1, n do emu.frameadvance(); Toolbox.Worker:run() end end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/PartyMenuGregminsterClosed.State")
  for _ = 1, 5 do emu.frameadvance() end
  Menu:refresh()
  local names = {}
  for _, c in ipairs(Menu.visible) do names[#names + 1] = (c.inParty and "*" or "") .. c.name end
  log("visible(" .. #names .. "): " .. table.concat(names, " "))
  log("start " .. party())
  press("Hero")      -- guard: hero can't be removed
  press("Gremio"); press("Gremio") -- queue then cancel
  log("after cancel queued=" .. PC.queuedCount())
  for i = 1, 50 do Toolbox.Worker:run() end -- "paused": tick spam with no frames must not time out
  press("Gremio"); press("Cleo"); press("Pahn"); press("Kasumi") -- 3 free slots then party-full guard
  press("Flik")      -- queue a removal
  log("paused-tick spam done, queued=" .. PC.queuedCount())
  for i = 1, 50 do Toolbox.Worker:run() end
  log("still queued after tick spam: " .. PC.queuedCount() .. " (expect 5)")
  runFrames(300)
  log("after apply " .. party() .. " queued=" .. PC.queuedCount() .. " msg=" .. tostring(PC.lastMessage))
  Menu:refresh()
  press("Cleo"); press("Gremio"); press("Pahn"); press("Kasumi"); press("Viktor") -- remove four, then last-but-guards
  runFrames(300)
  log("after removals " .. party() .. " msg=" .. tostring(PC.lastMessage))
  press("Hero")
  press("Viktor") -- would leave only the hero; allowed since hero stays
  runFrames(120)
  log("final " .. party())
  local w = Toolbox.Worker; w:draw()
end)
if not ok then log("ERR " .. tostring(err)) end
log("DONE")
while true do emu.frameadvance() end
