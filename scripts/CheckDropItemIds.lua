-- Verifies the user's hypothesis that MonsterRecord's "unused" trailing bytes (+0x36..+0x3b) are
-- actually 3 item-drop slots, each an (itemId byte, dropChance byte) pair - exactly matching the
-- logic already implemented in lib/Battle.lua's readEnemyTable (Drops loop, offsets 53+j*2/53+j*2+1
-- 1-indexed = +0x36/+0x37, +0x38/+0x39, +0x3a/+0x3b 0-indexed). Item names are static main.exe data,
-- not battle-state dependent, so any loaded state works - just need SOME state loaded.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/CheckDropItemIds.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Battle = require "lib.Battle"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Gigantes.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckDropItemIds.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  console.log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

-- id -> which monster/slot it came from, for readable output
local IDS = {
  {id=27, from="FurFur slotA id"},
  {id=25, from="FurFur slotB id / Golem slotA id"},
  {id=65, from="Zombie Dragon slotA id"},
  {id=154, from="Holly Fairy slotA id"},
  {id=17, from="Holly Fairy slotB id"},
  {id=71, from="Holly Fairy slotC id"},
  {id=130, from="Empire Captain#2/Holly Boy#2/Eagle man/Orc slotA id"},
  {id=114, from="BonBon/several soldier-types slotA id"},
  {id=3, from="Red Solider Ant/Queen Ant/Robot Soldier#2 slotA id"},
  {id=68, from="Death Machine#1 slotA id"},
  {id=169, from="Simurgh slotA id"},
  {id=1, from="Crow slotA id"},
  {id=123, from="Killer Rabbit/Ivy/Red Slime/Whip Master slotA id"},
}

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 5 do emu.frameadvance() end

  for _, entry in ipairs(IDS) do
    local okName, name = pcall(Battle.getItemName, entry.id)
    log(string.format("id=%3d (%s) -> %s", entry.id, entry.from, okName and tostring(name) or ("ERROR: " .. tostring(name))))
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
