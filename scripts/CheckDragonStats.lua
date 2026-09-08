-- One-shot check: does Dragon's own live CombatantRec.wMGC (+0x2c, the field
-- calc_rune_element_attack_damage's attacker-side reads) actually hold Dragon's declared MGC
-- stat (150, per vc61.bin's own monster record), or does it actually hold something else (e.g.
-- her PWR/250) - i.e. is the Lightning/Fire-Breath damage formula genuinely MGC-based for this
-- boss, or does the ATK-DEF calc_damage formula's ATK field (+0x30) match instead? Also reads
-- all 6 party members' own MGC/DEF/ATK for cross-checking against observed live damage (used
-- to build tests/test_Dragon.lua's TestDragonDamage test vectors).
--
-- RESULT (2026-09-07): Dragon's own CombatantRec has genuinely distinct ATK=250/MGC=150 (not
-- aliased) - matching the static monster record exactly - and predicted damage from the
-- MGC-based formula matches every observed live Lightning/Fire-Breath damage value exactly,
-- confirming Dragon's damage formula is MGC-based like Zombie Dragon's, NOT ATK-based. See
-- Dragon.calculateLightningDamage/calculateFireBreathDamage in lib/Enemies/Dragon.lua.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CheckDragonStats.txt"
local COMBATANT_BASE = 0xb94

local lines = {}
local function log(s) table.insert(lines, s); console.log(s) end

savestate.load(BASE_SAVE)
local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

for i = 0, 6 do
  local c = base + COMBATANT_BASE + i * 0x54
  local pwr_or_atk = mainmemory.read_u16_le(c + 0x30)
  local def = mainmemory.read_u16_le(c + 0x32)
  local mgc = mainmemory.read_u16_le(c + 0x2c)
  local hp = mainmemory.read_u16_le(c + 0x12)
  log(string.format("slot %d: ATK(+0x30)=%d DEF(+0x32)=%d MGC(+0x2c)=%d curHP(+0x12)=%d",
    i, pwr_or_atk, def, mgc, hp))
end

local file = io.open(OUTPUT_FILE, "w")
if file then file:write(table.concat(lines, "\n") .. "\n"); file:close() end
client.exit()
