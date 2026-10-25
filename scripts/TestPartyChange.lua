-- HEADLESS ONLY: loads a savestate over whatever is running - never run in your live session.
-- Verifies scripts/PartyChange.lua against PartyMenuGregminsterClosed.State: hook installs and the
-- stub runs (heartbeat), cdSync round-trips, remove the last party member, add them back, and
-- the party fields / stats-pointer chain match the original. Run headless via
-- scripts/spawn-headless-emuhawk.sh.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Party = require "lib.Party"
local PC = require "lib.PartyChange"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestPartyChange.txt"
local lines = {}
local function log(s) table.insert(lines, s); local f = io.open(OUT, "w"); f:write(table.concat(lines, "\n")); f:close() end

local function dump(tag)
  local ids, form = {}, {}
  for i = 0, 5 do ids[#ids + 1] = string.format("%02x", memory.read_u8(Address.PARTY_IDS + i)) end
  for i = 0, 5 do form[#form + 1] = string.format("%02x", memory.read_u8(Address.FORMATION_POSITIONS + i)) end
  local n = memory.read_u8(Address.PARTY_SIZE)
  local stats = {}
  for i = 0, n - 1 do
    local ok, a = pcall(Party.getCharacterDataAddress, i)
    stats[#stats + 1] = ok and string.format("%x(lvl%d)", a, Party.getCharacterLVL(a)) or "ERR"
  end
  log(string.format("[%s] size=%d ids=%s form=%s stats=%s", tag, n, table.concat(ids, " "), table.concat(form, " "), table.concat(stats, " ")))
end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/PartyMenuGregminsterClosed.State")
  for _ = 1, 5 do emu.frameadvance() end
  dump("initial")
  local lastId = memory.read_u8(Address.PARTY_IDS + 2)
  log(string.format("handler before=%08x", memory.read_u32_le(0x17da90)))
  PC.install()
  for _ = 1, 3 do emu.frameadvance() end
  log(string.format("handler after=%08x heartbeat=%d", memory.read_u32_le(0x17da90), PC.heartbeat()))
  log("cdSync -> " .. tostring(PC.call(PC.FN.cdSync, 0)))
  log("remove " .. lastId .. " -> " .. tostring(select(1, PC.removeFromParty(lastId))))
  for _ = 1, 10 do emu.frameadvance() end
  dump("after remove")
  local okAdd, info = PC.addToParty(lastId)
  log("add " .. lastId .. " -> " .. tostring(okAdd) .. " " .. tostring(info))
  for _ = 1, 10 do emu.frameadvance() end
  dump("after add")
  for _ = 1, 180 do emu.frameadvance() end
  dump("after 180 frames")
  log(string.format("handler end=%08x heartbeat=%d", memory.read_u32_le(0x17da90), PC.heartbeat()))
end)
if not ok then log("ERR " .. tostring(err)) end
log("DONE")
while true do emu.frameadvance() end -- idle; the spawn script's timeout ends the instance
