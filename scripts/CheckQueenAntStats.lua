-- Gather everything needed to bit-exact validate QueenAnt.calculateAoeEarthDamage: Queen Ant's
-- own MGC, and every party member's MGC/DEF/RuneId.
--
-- CORRECTED: this fight's combined combatant array uses a DIFFERENT field layout for enemy slots
-- than party slots (confirmed via DumpQueenAntRecords.lua - Soldier Ant's own known stats
-- PWR=48/SKL=18/DEF=10/SPD=22/MGC=0/LUK=6 line up at +0x14/+0x16/+0x18/+0x1a/+0x1c/+0x1e, NOT the
-- party layout's +0x2c=MGC/+0x32=DEF used successfully in CheckNeclordFullStats.lua/
-- CheckDragonStats.lua). Party slots keep the established +0x2c=MGC/+0x32=DEF layout.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckQueenAntStats.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

local ok, err = pcall(function()
  savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/QueenAnt.State")
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  log(string.format("=== QueenAnt.State (seed=0x%08x) ===", mainmemory.read_u32_le(Address.RNG)))

  local qc = base + 0xb40 + 9 * 0x54
  log(string.format("Queen Ant (slot 9, enemy layout): PWR=%d SKL=%d DEF=%d SPD=%d MGC=%d LUK=%d HP=%d",
    mainmemory.read_u16_le(qc + 0x14), mainmemory.read_u16_le(qc + 0x16),
    mainmemory.read_u16_le(qc + 0x18), mainmemory.read_u16_le(qc + 0x1a),
    mainmemory.read_u16_le(qc + 0x1c), mainmemory.read_u16_le(qc + 0x1e),
    mainmemory.read_u16_le(qc + 0x12)))

  for i = 1, 5 do
    local c = base + 0xb40 + i * 0x54
    local mgc = mainmemory.read_u16_le(c + 0x2c)
    local def = mainmemory.read_u16_le(c + 0x32)
    local hp = mainmemory.read_u16_le(c + 0x12)
    local classDataPtr = Address.sanitize(mainmemory.read_u32_le(base + 0xf84 + i * 12))
    local runeId = mainmemory.read_u8(classDataPtr + 0x1c + 0x4c)
    log(string.format("party slot %d (party layout): MGC=%d DEF=%d HP=%d RuneId=%d", i, mgc, def, hp, runeId))
  end

  for i = 6, 8 do
    local c = base + 0xb40 + i * 0x54
    log(string.format("ant slot %d (enemy layout): PWR=%d SKL=%d DEF=%d SPD=%d MGC=%d LUK=%d HP=%d",
      i, mainmemory.read_u16_le(c + 0x14), mainmemory.read_u16_le(c + 0x16),
      mainmemory.read_u16_le(c + 0x18), mainmemory.read_u16_le(c + 0x1a),
      mainmemory.read_u16_le(c + 0x1c), mainmemory.read_u16_le(c + 0x1e),
      mainmemory.read_u16_le(c + 0x12)))
  end
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
