-- Resolves every distinct item ID that appears in MonsterRecord's drop-table bytes (+0x36/+0x38/+0x3a
-- low bytes across all 124 Bestiary.json records) to its real item name, using the project's own
-- lib/Battle.lua:getItemName. Item names are static main.exe data, not battle-state dependent.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/DumpAllItemNames.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Battle = require "lib.Battle"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Gigantes.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DumpAllItemNames.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

local IDS = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 29, 30, 31, 34, 35, 36, 37, 39, 40, 41, 43, 44, 45, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 58, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 76, 77, 78, 83, 94, 98, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 139, 148, 149, 150, 153, 154, 155, 164, 165, 166, 167, 168, 169}

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 5 do emu.frameadvance() end
  for _, id in ipairs(IDS) do
    local okName, name = pcall(Battle.getItemName, id)
    log(string.format("%d\t%s", id, okName and tostring(name) or "ERROR"))
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
