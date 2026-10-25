-- Live test of scripts/WarPsnPatch.lua: plays Magic, Magic, Charge on kuwa from KwandaWBT1.State twice (plain disc
-- build, then patched like the PSN build) and writes the seed at each command menu, the sprite arrays at menu 3, and the
-- seed after the last round. Output: Lua/Output/WarPsnTest.txt. Expected (WarSim): disc ends 0x6620060e (index 10867),
-- PSN ends 0xb147d7d8 (index 7689); menu seeds 0x242e5f33 and 0x035c23aa.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local psn = require("scripts.WarPsnPatch")
local STATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/KwandaWBT1.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/WarPsnTest.txt"
local CMDS = {{2, 0}, {2, 0}, {0, 0}}
local function r8(a) return mainmemory.read_u8(a) end
local function press(btn, n)
  for _ = 1, (n or 4) do joypad.set({[btn] = true}); emu.frameadvance() end
  for _ = 1, 10 do emu.frameadvance() end
end
local function wait(n) for _ = 1, n do emu.frameadvance() end end
local function menuReady() return r8(0xa7760) == 2 and r8(0xa76a8) == 2 end
local function hexrange(a, n)
  local t = memory.read_bytes_as_array(a & 0x1fffff, n, "MainRAM")
  local o = {}
  for i = 1, #t do o[i] = string.format("%02x", t[i]) end
  return table.concat(o)
end
pcall(client.speedmode, 6400)
local fh = io.open(OUT, "w")
for _, patched in ipairs({false, true}) do
  savestate.load(STATE)
  local applied = patched and psn.apply() or false
  wait(5)
  fh:write(string.format("== run patched=%s applied=%s\n", tostring(patched), tostring(applied)))
  for turn, cmd in ipairs(CMDS) do
    local n = 0
    while not menuReady() and n < 3000 do emu.frameadvance(); n = n + 1 end
    fh:write(string.format("menu %d seed %08x phase %d state %d p %d e %d\n", turn, mainmemory.read_u32_le(0x9010), r8(0xa7760), r8(0xa76a8),
      mainmemory.read_u16_le(0xa7680), mainmemory.read_u16_le(0xa7682)))
    if turn == 3 then
      local P = mainmemory.read_u32_le(0xa76b0)
      local A0, A1 = mainmemory.read_u32_le(P & 0x1fffff), mainmemory.read_u32_le((P & 0x1fffff) + 4)
      fh:write(string.format("sprites side0 %08x %s\n", A0, hexrange(A0, 19 * 28)))
      fh:write(string.format("sprites side1 %08x %s\n", A1, hexrange(A1, 31 * 28)))
    end
    for _ = 1, cmd[1] do press("P1 D-Pad Down") end
    press("P1 X"); wait(60)
    for _ = 1, cmd[2] do press("P1 D-Pad Down") end
    press("P1 X"); wait(60)
    press("P1 X")
    for f = 1, 9000 do
      if f % 24 == 0 and not menuReady() then joypad.set({["P1 X"] = true}) end
      emu.frameadvance()
      if f > 40 and menuReady() then break end
      if r8(0xa7760) >= 5 and r8(0xa7760) ~= 9 and f > 5 then break end
    end
  end
  fh:write(string.format("after last round: phase %d seed %08x\n", r8(0xa7760), mainmemory.read_u32_le(0x9010)))
  for i = 1, 12 do
    wait(10)
    fh:write(string.format("  +%d frames: phase %d seed %08x\n", i * 10, r8(0xa7760), mainmemory.read_u32_le(0x9010)))
  end
  fh:flush()
end
fh:close()
client.exit()
