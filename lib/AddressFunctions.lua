-- Addresses of main.exe code (full KSEG0 addresses, as Ghidra shows them): hook/handler targets and values compared against
-- the game's own function pointers. Build handling (v1.1 vs v1.0/PSN): lib/AddressBuild.lua. In v1.0 the code moved by
-- +0x1ec (0x800c....), +0x1b0 (0x800e.... to 0x8012....) or -0x560 (0x8013....); each value below was checked to have the same
-- instructions (immediates and jump targets ignored) at its v1.0 address in a PSN RAM dump (40 of 40 for every entry).
local AddressBuild = require "lib.AddressBuild"

local V11 = {
  -- lib/SoulEaterCapture.lua: the battle-state handler installed while the spell's tick machine runs
  SOUL_EATER_BLACK_SHADOW_HANDLER = 0x80114ca8,
  SOUL_EATER_HELL_HANDLER = 0x80115a7c,
  -- lib/BattleRoundInput.lua: battle_menu_fight_run_bribe_freewill
  FIGHT_MENU_HANDLER = 0x800ea2a8,
  -- lib/PartyChange.lua: functions the stub calls (see its header)
  PARTY_CLAIM_SLOT = 0x800c48d4,
  PARTY_CD_SYNC = 0x800c2fa4,
  PARTY_APPEND_TO_FORMATION = 0x800c49b8,
  PARTY_REMOVE_SLOT = 0x800c4afc,
  -- lib/ScreenTeleport.lua: the field main handler (field_main_running) and the loader's idle handler
  FIELD_MAIN_RUNNING = 0x801319c4,
  FIELD_LOADER_IDLE = 0x80132790,
}

local V10 = {
  SOUL_EATER_BLACK_SHADOW_HANDLER = 0x80114e58, -- 0x80114ca8
  SOUL_EATER_HELL_HANDLER = 0x80115c2c,         -- 0x80115a7c
  FIGHT_MENU_HANDLER = 0x800ea458,              -- 0x800ea2a8
  PARTY_CLAIM_SLOT = 0x800c4ac0,                -- 0x800c48d4
  PARTY_CD_SYNC = 0x800c3190,                   -- 0x800c2fa4
  PARTY_APPEND_TO_FORMATION = 0x800c4ba4,       -- 0x800c49b8
  PARTY_REMOVE_SLOT = 0x800c4ce8,               -- 0x800c4afc
  FIELD_MAIN_RUNNING = 0x80131464,              -- 0x801319c4
  FIELD_LOADER_IDLE = 0x80132230,               -- 0x80132790
}

return AddressBuild.wrap(V11, V10)
