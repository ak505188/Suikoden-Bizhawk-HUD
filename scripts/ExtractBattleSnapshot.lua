-- Demo/validation for lib/BattleSnapshot.lua: loads a savestate positioned right before the
-- round-start menu's first confirm, waits for the battle struct to stably populate, extracts a
-- full InitialState snapshot, and writes it out as JSON - both as a human-checkable artifact and
-- as the literal file format a future pure-code simulator would consume.
--
-- USAGE: edit BASE_SAVE below, run via
--   scripts/spawn-headless-emuhawk.sh scripts/ExtractBattleSnapshot.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/ZombieDragonStart.State"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/ZombieDragonStart.snapshot.json"

-- Everything, including requires, inside one pcall: console errors are GUI-only and never reach
-- the headless log, so an uncaught error anywhere (even at module-load time) otherwise leaves no
-- trace at all - no output file, no exit, just a silent hang/timeout.
local ok, err = pcall(function()
  local BattleSnapshot = require "lib.BattleSnapshot"
  local json = require "lib.json"

  savestate.load(BASE_SAVE)
  for i = 1, 200 do emu.frameadvance() end

  local snapshot, reason = BattleSnapshot:extract()
  if not snapshot then
    error("extract failed: " .. tostring(reason))
  end

  local f = io.open(OUT, "w")
  f:write(json.encode(snapshot))
  f:close()
end)

if not ok then
  local f = io.open(OUT, "w")
  f:write("ERROR: " .. tostring(err))
  f:close()
end

client.exit()
