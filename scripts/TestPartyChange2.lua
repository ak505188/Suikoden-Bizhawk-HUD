-- HEADLESS ONLY: loads a savestate over whatever is running - never run in your live session.
-- Adds three characters that were NOT loaded into the party, checks the stats-pointer chain
-- resolves to the right record (id + level from the global stats table at 0x1b8294, stride 0x50),
-- then removes them again. Companion to TestPartyChange.lua.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Party = require "lib.Party"
local PC = require "lib.PartyChange"
local OUT = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TestPartyChange2.txt"
local lines = {}
local function log(s) table.insert(lines, s); local f = io.open(OUT, "w"); f:write(table.concat(lines, "\n")); f:close() end
local function size() return memory.read_u8(Address.PARTY_SIZE) end
local function dump(tag)
  local ids, form = {}, {}
  for i = 0, 5 do ids[#ids + 1] = string.format("%02x", memory.read_u8(Address.PARTY_IDS + i)) end
  for i = 0, 5 do form[#form + 1] = string.format("%02x", memory.read_u8(Address.FORMATION_POSITIONS + i)) end
  local st = {}
  for i = 0, size() - 1 do
    local a = Party.getCharacterDataAddress(i)
    st[#st + 1] = string.format("id%d@%x lvl%d", memory.read_u8(a), a, Party.getCharacterLVL(a))
  end
  log(string.format("[%s] size=%d ids=%s form=%s | %s", tag, size(), table.concat(ids, " "), table.concat(form, " "), table.concat(st, "; ")))
end
local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/PartyMenuGregminsterClosed.State")
  for _ = 1, 5 do emu.frameadvance() end
  PC.install()
  dump("initial")
  local cands = {}
  for a = 0x1b8294, 0x1b8294 + 0x50 * 90, 0x50 do
    local id, lvl = memory.read_u8(a), memory.read_u8(a + 0xd)
    if id > 0 and id < 0x6c and lvl > 1 and not PC.inParty(id) then cands[#cands + 1] = { id = id, lvl = lvl, a = a } end
  end
  log("candidates: " .. #cands)
  for i = 1, math.min(3, #cands) do
    local c = cands[i]
    local ok2, info = PC.addToParty(c.id)
    log(string.format("add id=%d (table lvl %d @%x) -> %s %s", c.id, c.lvl, c.a, tostring(ok2), tostring(info)))
    for _ = 1, 10 do emu.frameadvance() end
    dump("after add " .. c.id)
  end
  for _ = 1, 120 do emu.frameadvance() end
  dump("after 120 frames")
  for i = 1, math.min(3, #cands) do
    log("remove " .. cands[i].id .. " -> " .. tostring(PC.removeFromParty(cands[i].id)))
    for _ = 1, 5 do emu.frameadvance() end
  end
  dump("after removes")
end)
if not ok then log("ERR " .. tostring(err)) end
log("DONE")
while true do emu.frameadvance() end -- idle; the spawn script's timeout ends the instance
