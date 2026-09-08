-- User: "Check the save state memory" (follow-up to "can you scan to see if [move probability
-- values] are loaded anywhere in game, perhaps in enemy data structure?"). Static disassembly of
-- va7.bin already confirmed both thresholds are compiled `slti` immediates, not data loads - this
-- reads the ACTUAL LIVE RAM bytes at those exact instruction addresses from a real running battle
-- (QueenAnt.State) to confirm the overlay loaded into memory unmodified, rather than trusting the
-- offline ROM/overlay file alone.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh scripts/CheckLiveThresholdBytes.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckLiveThresholdBytes.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local function sanitize(addr) return addr & 0x001fffff end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State")

  local QUEEN_ANT_SLTI = 0x80010ba0   -- slti v1,v1,0x33 (expected bytes: 33 00 63 28)
  local SOLDIER_ANT_SLTI = 0x80010888 -- slti v0,v0,0x4d (expected bytes: 4d 00 42 28)

  local qWord = mainmemory.read_u32_le(sanitize(QUEEN_ANT_SLTI))
  local sWord = mainmemory.read_u32_le(sanitize(SOLDIER_ANT_SLTI))

  log(string.format("Queen Ant slti @ 0x%08x live word = 0x%08x (expected 0x28630033)", QUEEN_ANT_SLTI, qWord))
  log(string.format("Soldier Ant slti @ 0x%08x live word = 0x%08x (expected 0x2842004d)", SOLDIER_ANT_SLTI, sWord))
  log(string.format("Queen Ant match:   %s", qWord == 0x28630033 and "MATCH" or "MISMATCH"))
  log(string.format("Soldier Ant match: %s", sWord == 0x2842004d and "MATCH" or "MISMATCH"))
end)

if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
