-- Diagnostic: CheckQueenAntStats.lua's combatant_rec+0x2c/0x30/0x32 (MGC/ATK/DEF) offsets, which
-- work for Neclord (a 1v1 fight), gave garbage for Queen Ant's fight (5 party + 3 ants + queen).
-- Dump raw bytes of Soldier Ant's own record (known stats: PWR=48 SKL=18 DEF=10 SPD=22 MGC=0
-- LUK=6, from its static monster record at 0x8006500c) to find where those values actually live
-- in THIS fight's combatant_rec layout.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DumpQueenAntRecords.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State")
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local function dumpRecord(label, idx)
    local rec = base + 0xb40 + idx * 0x54
    local bytes = {}
    for off = 0, 0x53 do
      table.insert(bytes, string.format("%02x", mainmemory.read_u8(rec + off)))
    end
    log(label .. " (slot " .. idx .. ", addr 0x" .. string.format("%x", rec) .. "):")
    log(table.concat(bytes, " "))
    -- also as u16 words for convenience
    local words = {}
    for off = 0, 0x52, 2 do
      table.insert(words, string.format("+0x%02x=%d", off, mainmemory.read_u16_le(rec + off)))
    end
    log(table.concat(words, "  "))
  end

  dumpRecord("Soldier Ant", 6)
  dumpRecord("Party slot 1", 1)
  dumpRecord("Queen Ant", 9)
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
