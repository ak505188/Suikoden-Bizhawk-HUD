-- Determine whether Neclord.State's AoE attack is Wind (element=5) or Lightning (element=4) by
-- reading each target's own MGC + equipped Rune.Id, computing predicted damage under both
-- hypotheses, and comparing against the actually-observed damage from CheckNeclordDamagePattern.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckNeclordElementSignature.txt"
local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

savestate.load("/home/alex/Projects/Suikoden-Bizhawk-HUD/Neclord.State")
local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

local neclordMgc = mainmemory.read_u16_le(base + 0xb94 + 6 * 0x54 + 0x2c)
log(string.format("Neclord MGC = %d", neclordMgc))

local observedDmg = {192, 192, 157, 78, 85, 65}
for i = 0, 5 do
  local mgc = mainmemory.read_u16_le(base + 0xb94 + i * 0x54 + 0x2c)
  local classDataPtr = Address.sanitize(mainmemory.read_u32_le(base + 0xf84 + i * 12))
  local runeId = mainmemory.read_u8(classDataPtr + 0x1c + 0x4c)
  log(string.format("slot %d: MGC=%d RuneId=%d observedDmg=%d base(MGC-diff)=%d",
    i, mgc, runeId, observedDmg[i + 1], neclordMgc - mgc))
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
