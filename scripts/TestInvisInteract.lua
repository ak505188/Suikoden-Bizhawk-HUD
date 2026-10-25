-- HEADLESS ONLY. From InvisVikiCleo.State (hidden slot 1 = (11,11)), teleport the hero next to a real NPC
-- (slot 2 at (15,31)) and next to the hidden slot, face a direction, press Cross, and log whether an event
-- started (EVENT_ID / gamestate / hero-lock change). Checks the FUN_8013d3cc geometry:
--   UP/DOWN: slotY == heroY + (UP:-1, DOWN:+2) and |slotX - heroX| <= 1
--   LEFT/RIGHT: slotX == heroX + (LEFT:-2, RIGHT:+2) and slotY in [heroY, heroY+1]
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestInvisInteract.txt"
local lines = {}
local function log(s) table.insert(lines, s); local f = io.open(OUT, "w"); f:write(table.concat(lines, "\n")); f:close() end
pcall(function() client.speedmode(6400) end)
local STATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/InvisViki" .. (INTERACT_STATE or "Cleo") .. ".State"
local DIRS = { DOWN = 0, UP = 1, LEFT = 2, RIGHT = 3 }

local function snap()
  return { ev = memory.read_u32_le(Address.EVENT_ID), gs = memory.read_u8(Address.GAMESTATE),
           win = memory.read_bytes_as_array(0x17a000, 0x2000) }
end
local function diffCount(a, b) local n = 0 for i = 1, #a.win do if a.win[i] ~= b.win[i] then n = n + 1 end end return n end

local function try(label, x, y, dir)
  savestate.load(STATE)
  for _ = 1, 3 do emu.frameadvance() end
  memory.write_u8(Address.HERO_X, x); memory.write_u8(Address.HERO_Y, y)
  local dp = memory.read_u32_le(Address.HERO_DIRECTION_PTR) & 0x1fffff
  memory.write_u8(dp, DIRS[dir])
  for _ = 1, 2 do emu.frameadvance() end
  local before = snap()
  for _ = 1, 4 do joypad.set({ ["P1 X"] = true }); emu.frameadvance() end
  for _ = 1, 40 do emu.frameadvance() end
  local after = snap()
  local lock = diffCount(before, after)
  log(string.format("%-22s hero=(%2d,%2d) %-5s ev %x->%x gs %d->%d windowDiff=%d", label, x, y, dir, before.ev, after.ev, before.gs, after.gs, lock))
end

local ok, err = pcall(function()
  savestate.load(STATE)
  for _ = 1, 3 do emu.frameadvance() end
  log("room slots: " .. (function()
    local t, ptr = {}, memory.read_u32_le(Address.ROOM_POINTER) & 0x1fffff
    for i = 0, memory.read_u8(0x17dbfc) - 1 do t[#t + 1] = string.format("(%d,%d id%02x)", memory.read_u8(ptr + i * 0x18), memory.read_u8(ptr + i * 0x18 + 1), memory.read_u8(ptr + i * 0x18 + 0x14)) end
    return table.concat(t, " ") end)())
  try("baseline (nothing)", 30, 20, "UP")
  try("real NPC (15,31) ctrl", 15, 29, "DOWN")
  try("real NPC off by 1 x", 16, 29, "DOWN")
  try("real NPC off by 2 x", 17, 29, "DOWN")
  try("real NPC wrong Y", 15, 28, "DOWN")
  try("hidden (11,11) DOWN", 11, 9, "DOWN")
  try("hidden (11,11) DOWN x+1", 12, 9, "DOWN")
  try("hidden (11,11) DOWN x+2", 13, 9, "DOWN")
  try("hidden (11,11) UP", 11, 12, "UP")
  try("hidden (11,11) UP wrong", 11, 13, "UP")
  try("hidden (11,11) LEFT", 13, 11, "LEFT")
  try("hidden (11,11) LEFT y-1", 13, 10, "LEFT")
  try("hidden (11,11) LEFT y+1", 13, 12, "LEFT")
  try("hidden (11,11) RIGHT", 9, 11, "RIGHT")
  try("hidden (11,11) RIGHT y-1", 9, 10, "RIGHT")
end)
if not ok then log("ERR " .. tostring(err)) end
log("DONE")
while true do emu.frameadvance() end
