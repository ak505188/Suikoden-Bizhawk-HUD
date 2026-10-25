-- Standalone party add/remove. Edit ADD / REMOVE with character ids (PARTY_IDS values, e.g.
-- Hero 8, Flik 17, Viktor 35 - see lib/Characters/Addresses.lua `Id`), then load this script
-- while the game is on a normal field screen (not in a battle or menu). It applies the changes,
-- then stays resident showing the party on screen. The Toolbox module has a menu for the same
-- thing ("Party Members"). Mechanism: lib/PartyChange.lua and notes/Party_Change.md.
package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local PartyChange = require "lib.PartyChange"

local ADD = PARTYCHANGE_ADD or {}
local REMOVE = PARTYCHANGE_REMOVE or {}
local START_DELAY_FRAMES = 60

local function partyLine()
  local ids = {}
  for i = 0, memory.read_u8(Address.PARTY_SIZE) - 1 do
    ids[#ids + 1] = tostring(memory.read_u8(Address.PARTY_IDS + memory.read_u8(Address.FORMATION_POSITIONS + i)))
  end
  return "party: " .. table.concat(ids, ",")
end

for _ = 1, START_DELAY_FRAMES do emu.frameadvance() end
local msgs = {}
local function note(s) msgs[#msgs + 1] = s; print("[PartyChange] " .. s) end
local ok, why = PartyChange.install()
if not ok then note("install failed: " .. tostring(why)) end
for _, id in ipairs(ok and REMOVE or {}) do
  local r, info = PartyChange.removeFromParty(id); note(string.format("remove %d: %s %s", id, tostring(r), tostring(info)))
end
for _, id in ipairs(ok and ADD or {}) do
  local r, info = PartyChange.addToParty(id); note(string.format("add %d: %s %s", id, tostring(r), tostring(info)))
end
if #msgs == 0 then note("nothing to do - edit ADD / REMOVE at the top of the script") end
while true do
  PartyChange.install()
  gui.text(2, 2, partyLine() .. "  | " .. msgs[#msgs])
  emu.frameadvance()
end
