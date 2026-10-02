local Address = {
  GAMESTATE = 0x1B9BBC,
  PREV_GAMESTATE = 0x1B9BB8,
  AREA_ZONE = 0x1B8000,
  SCREEN_ZONE = 0x1B8001,
  WM_ZONE = 0x1B8002,
  PARTY_SIZE = 0x1B8003,
  PARTY_IDS = 0x1B8008,
  FORMATION_POSITIONS = 0x1B800e,
  CASTLE_LEVEL = 0x1B8034,
  ENCOUNTER_RATE = 0x17159D,
  RNG = 0x9010,
  EVENT_ID = 0x1B9BC0,
  ENEMY_GROUP_PTR = 0x197F10,
  ENCOUNTER_TABLE_PTR = 0x197F14,
  ITEM_NAME_PTR_1 = 0x16765c,
  ITEM_DEFINITION_TABLE = 0x167658, -- LAB_80167658: u32 pointer per item id (1-179; id 0 is empty). Static, same as main.exe. Record layout in docs/game_mechanics/Items.md.
  BATTLE_ITEM_DROP = 0x18FAF0,
  GAMESTATE_BASE = 0x1B8000,
  RECRUIT_FIRST_SLOT = 0x1B9AF4,
  HERO_X = 0x17BD74,
  HERO_Y = 0x17BD75,
  HERO_DIRECTION_PTR = 0x17BD7C,
  ROOM_POINTER = 0x17DAA0,
  STONE_TABLET_NAMES_START = 0x084EAC, --Starts on slot 2, Lepant
  SESSION_FRAMECOUNT = 0x1783f8, -- Kinda loadless, not completely accurate to save IGT
  -- SAVE_FRAMECOUNT = 0x18B0A8, -- Not sure how to calculate real IGT, missing some value
  -- Other IGT options are 17DBE8 (stops on loads?), 1B9B8C (Updated on save)
  SAVE_FRAMECOUNT = 0x1B9B8C, -- Used for Chinchironin randomization
  BIRDS_PTR = 0x199f7c,
  BATTLE_STATE_PTR = 0x17be3c, -- Pointer to the live in-battle combatant/turn-order struct (DAT_8017be3c in Ghidra). See docs/game_mechanics/Turn_Order.md and Battle_Damage_Formula.md.
  SOUL_EATER_CTX = 0x17a060, -- Pointer to a generic, dynamically heap-allocated VFX scratch struct (DAT_8017a060 in Ghidra), read+written by (at least) four spells' tick_state_machines: Hell, Black Shadow, Deadly Fingertips, and Judgment - identified via a charmap-encoded name+dispatch table at ~0x8016e000+ (see the plate comment on 0x8016e8a0 in Ghidra) and confirmed by each spell's own dedicated teardown function (spell_hell_cleanup, spell_blackshadow_cleanup, spell_deadlyfingertips_cleanup, spell_judgment_cleanup - all call a shared per-object release helper, FUN_801234d0, then heap_free the struct itself). See Battle_Damage_Formula.md's "Hell"/"Black Shadow" sections and docs/game_mechanics/Black_Shadow_Simulation_Workflow.md.
  FLAMING_ARROW_CTX_PTR = 0x17a030, -- Pointer to Flaming Arrow's own VFX context (DAT_8017a030 in Ghidra) - a SEPARATE heap-allocated slot from SOUL_EATER_CTX, shared with Explosion, Dancing Flames, and Firestorm (spell_explosion_vfx_setup/spell_dancingflames_vfx_setup both heap_alloc into this exact slot; spell_flamingarrow_cleanup heap_free's it every cast). Despite genuine reuse, empirically confirmed to resolve to the same address/content across 4 real savestates, including one captured after a same-slot Firestorm cast - see lib/Magic.lua's FlamingArrowResidualLow12 comment and docs/game_mechanics/Battle_Damage_Formula.md's "Flaming Arrow" section.
  VFX_HEAP_ARENA_BASE = 0x182000, -- Fixed static heap arena every VFX context above (and much else - see heap_alloc's 53 call sites) allocates from - literal args to heap_init(&DAT_80182000, 0x18000) inside the engine's one-time boot init (Ghidra FUN_800c2ba8). Same address in every savestate; only the allocation state WITHIN this range varies.
  VFX_HEAP_ARENA_SIZE = 0x18000,
}

function Address.sanitize(addr)
  return addr & 0x001fffff
end

function Address.isValidAddress(addr)
  return addr >= 0x000000 and addr <= 0x001fffff
end

function Address.isValidPointer(pointer)
  return pointer >= 0x80000000 and pointer <= 0x801fffff
end

return Address
