-- Command-menu unit order: from TeoWB2T1.State (Teo 2, first menu), randomly removes members (avail bytes at
-- 0x18ebb0 + id), chooses Charge and records the sorted unit list at 0x800a8a... (kuwa 0xa7658 + 0x1350 for teo2).
-- Output: Lua/Output/WarMenuOrder.txt, one line per trial: avail bytes (hex, 108 members) | sorted group list.
local STATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/TeoWB2T1.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/WarMenuOrder.txt"
local OFF = 0x1350
local PHASE, STATE_A, LIST, COUNT = 0xa7760 + OFF, 0xa76a8 + OFF, 0xa7658 + OFF, 0xa73d0 + OFF
local AVAIL = 0x18ebb0
local TRIALS = 60
local function r8(a) return mainmemory.read_u8(a) end
local function press(btn, n)
  for _ = 1, (n or 4) do joypad.set({[btn] = true}); emu.frameadvance() end
  for _ = 1, 10 do emu.frameadvance() end
end
local function wait(n) for _ = 1, n do emu.frameadvance() end end
pcall(client.speedmode, 6400)
local fh = io.open(OUT, "w")
math.randomseed(12345)
for trial = 0, TRIALS - 1 do
  savestate.load(STATE)
  wait(5)
  local avail = {}
  for i = 0, 107 do avail[i] = r8(AVAIL + i) end
  if trial > 0 then
    for i = 0, 107 do
      if avail[i] == 0xff and math.random() < 0.25 then mainmemory.write_u8(AVAIL + i, 0); avail[i] = 0 end
    end
  end
  local hex = {}
  for i = 0, 107 do hex[#hex + 1] = string.format("%02x", avail[i]) end
  if not (r8(PHASE) == 2 and r8(STATE_A) == 2) then
    fh:write(string.format("trial %d: menu not ready phase=%d state=%d\n", trial, r8(PHASE), r8(STATE_A)))
  else
    press("P1 X"); wait(30)
    local n = r8(COUNT)
    local l = {}
    for i = 0, n - 1 do l[#l + 1] = r8(LIST + i) end
    fh:write(table.concat(hex) .. " | " .. table.concat(l, ",") .. "\n")
  end
  fh:flush()
end
fh:close()
client.exit()
