-- HEADLESS ONLY (ends with client.exit()). For every screen in lib/ScreenList.lua that has an entry tile, load the
-- start save, teleport with lib/ScreenTeleport.lua using the first entry, then check the game loaded that screen and
-- put the hero on the requested tile (hero tile = DAT_8017bd74/75). Globals: TEST_ONLY_EVERY (test every Nth screen),
-- TEST_OUT. One line per screen: OK / FAIL <why>.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local ScreenTeleport = require "lib.ScreenTeleport"
local ScreenList = require "lib.ScreenList"
local OUT = TEST_OUT or "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestScreenTeleport.txt"
local EVERY = TEST_ONLY_EVERY or 1
local START = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/InvisVikiOutsideRoom.State"
local f = io.open(OUT, "w"); f:close()
local function log(s) local h = io.open(OUT, "a"); h:write(s .. "\n"); h:close() end
pcall(function() client.speedmode(6400) end)

local function sortedKeys(t) local k = {} for a in pairs(t) do k[#k + 1] = a end table.sort(k) return k end
local n, pass = 0, 0
local idx = 0
for _, wm in ipairs(sortedKeys(ScreenList)) do
  for _, area in ipairs(sortedKeys(ScreenList[wm].areas)) do
    for _, screen in ipairs(sortedKeys(ScreenList[wm].areas[area].screens)) do
      local e = ScreenList[wm].areas[area].screens[screen][2][1]
      if e then
        idx = idx + 1
        if idx % EVERY == 0 then
          n = n + 1
          local ok, err = pcall(function()
            savestate.load(START)
            for _ = 1, 4 do emu.frameadvance() end
            local r, why = ScreenTeleport.request(wm, area, screen, e[1], e[2])
            if not r then return log(string.format("FAIL %d/%d/%d request refused: %s", wm, area, screen, why)) end
            local frames = 0
            while ScreenTeleport.busy() and frames < 2000 do ScreenTeleport.tick(); emu.frameadvance(); frames = frames + 1 end
            local msg = ScreenTeleport.lastMessage or "?"
            local z = string.format("%d/%d/%d", memory.read_u8(0x1b8002), memory.read_u8(0x1b8000), memory.read_u8(0x1b8001))
            local hx, hy = memory.read_u8(0x17bd74), memory.read_u8(0x17bd75)
            local want = string.format("%d/%d/%d", wm, area, screen)
            if msg:sub(1, 6) == "loaded" and z == want and hx == e[1] and hy == e[2] then
              pass = pass + 1
              log(string.format("OK   %s hero=(%d,%d) frames=%d", want, hx, hy, frames))
            else
              log(string.format("FAIL %s msg=%s zones=%s hero=(%d,%d) want=(%d,%d)", want, msg, z, hx, hy, e[1], e[2]))
            end
          end)
          if not ok then log("FAIL ERR " .. tostring(err)) end
        end
      end
    end
  end
end
log(string.format("DONE %d/%d passed", pass, n))
client.exit()
