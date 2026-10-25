-- Prints a running battle log (round starts, turns, actions, damage/heals, RNG advances) to the
-- BizHawk Lua console. Load it from Tools > Lua Console, or headlessly via
-- scripts/spawn-headless-emuhawk.sh. See lib/BattleLogger.lua for the line format and limits.
--
-- Set LEVEL to 2 to also log busy / primed / finished state changes (see lib/BattleLogger.lua).
-- Set LOG_FILE to also append every line to a file.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local BattleLogger = require "lib.BattleLogger"

local LEVEL = 1
local LOG_FILE = nil -- e.g. "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/BattleLog.txt"

BattleLogger.Level = LEVEL

if LOG_FILE then
  local file = assert(io.open(LOG_FILE, "w"))
  BattleLogger.Sink = function(line) console.log(line); file:write(line, "\n"); file:flush() end
end

while true do
  BattleLogger:update()
  emu.frameadvance()
end
