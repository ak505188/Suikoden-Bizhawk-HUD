-- Static data tables in main.exe's image (KUSEG-stripped RAM offsets, resident from boot, readable like any fixed global).
-- Build handling (v1.1 vs v1.0/PSN): lib/AddressBuild.lua. In v1.0 every table below sits 0x45a4 higher and the pointers
-- stored inside the tables are relocated by the same amount (the Lua code follows them, so nothing else changes). The
-- v1.0 values were checked against a PSN RAM dump (equal words or pointers shifted by 0x45a4 for all 64 words read of each).
local AddressBuild = require "lib.AddressBuild"

local V11 = {
  RUNE_ABILITY_SET_TABLE = 0x16a0e0, -- DAT_8016a0e0, indexed by Rune.Id (0-33)
  SPELL_DEFINITION_TABLE = 0x16d33c, -- DAT_8016d33c, indexed by resolved spell id (normal casters)
  ALT_ABILITY_TABLE = 0x16a630,      -- DAT_8016a630, indexed the same way, for ability-set+0x16==1
  UNITE_ATTACK_TABLE = 0x16d18c,     -- DAT_8016d18c, indexed by AbilitySlot (1-32)
  WEAPON_CLASS_TABLE = 0x165890,     -- DAT_80165890, pointer table indexed by WeaponType*4
  WEAPON_POWER_TABLE = 0x1659cc,     -- PTR_DAT_801659cc, used as a raw i16 table base directly (not dereferenced)
}

local V10 = {
  RUNE_ABILITY_SET_TABLE = 0x16e684, -- 0x16a0e0
  SPELL_DEFINITION_TABLE = 0x1718e0, -- 0x16d33c
  ALT_ABILITY_TABLE = 0x16ebd4,      -- 0x16a630
  UNITE_ATTACK_TABLE = 0x171730,     -- 0x16d18c
  WEAPON_CLASS_TABLE = 0x169e34,     -- 0x165890
  WEAPON_POWER_TABLE = 0x169f70,     -- 0x1659cc
}

-- The item tables (ITEM_DEFINITION_TABLE, ITEM_NAME_PTR_1) are in lib/Address.lua.
return AddressBuild.wrap(V11, V10)
