-- HEADLESS ONLY. Teleport experiment: from InvisVikiOutsideRoom.State (area32/screen1/wm9) write the target zone
-- bytes and set the "leaving screen" flag (*(DAT_8017be20)+0x34 = 1) instead of walking through the door; log the
-- scene-state sequence and the resulting room table. Natural transition gives table 0x8018b400, ns=3.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestTeleport.txt"
local lines = {}
local function log(s) table.insert(lines, s); local f = io.open(OUT, "w"); f:write(table.concat(lines, "\n")); f:close() end
pcall(function() client.speedmode(6400) end)
local function zones() return string.format("area%d/screen%d/wm%d", memory.read_u8(0x1b8000), memory.read_u8(0x1b8001), memory.read_u8(0x1b8002)) end
local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/InvisVikiOutsideRoom.State")
  for _ = 1, 4 do emu.frameadvance() end
  local base = memory.read_u32_le(0x17be20) & 0x1fffff
  log(string.format("DAT_8017be20=%x flag@+0x34=%d zones=%s", base, memory.read_u8(base + 0x34), zones()))
  memory.write_u8(0x1b8001, 2) -- SCREEN_ZONE
  memory.write_u8(base + 0x34, 1)
  local last = ""
  for f = 1, 160 do
    emu.frameadvance()
    local t = {}
    for i = 1, 3 do t[#t + 1] = string.format("%08x", memory.read_u32_le(0x17da90 + 4 * i)) end
    local h = table.concat(t, " ")
    if h ~= last then
      log(string.format("f%03d [%s] %s hero=(%d,%d) ptr=%08x", f, h, zones(), memory.read_u8(0x17bd74), memory.read_u8(0x17bd75), memory.read_u32_le(Address.ROOM_POINTER)))
      last = h
    end
  end
  local ptr = memory.read_u32_le(Address.ROOM_POINTER)
  log(string.format("final table=%08x slots=%d slot1=%s", ptr, memory.read_u8(0x17dbfc), (function() local t = {} for i = 0, 7 do t[#t + 1] = string.format("%02x", memory.read_u8((ptr & 0x1fffff) + i)) end return table.concat(t, " ") end)()))
end)
if not ok then log("ERR " .. tostring(err)) end
log("DONE")
while true do emu.frameadvance() end
