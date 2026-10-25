-- RAM addresses (offsets into main RAM) of globals and game state. Build handling (v1.1 vs v1.0/PSN): lib/AddressBuild.lua.
-- This file's V11 table is the v1.1 disc BizHawk normally runs; V10 below overrides what moved in v1.0. The game state at
-- 0x1B8000+, the heap and the BIOS RNG did not move. The v1.0 values were derived from the two MAIN.EXE files and checked
-- against a PSN RAM dump (outputs/HudAddressMapV10.tsv); not tested on a live v1.0 BizHawk.
-- Related files: lib/AddressTables.lua (static data tables in main.exe), lib/AddressFunctions.lua (main.exe code addresses).
local AddressBuild = require "lib.AddressBuild"

local V11 = {
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
  MONEY = 0x1B801C, -- u32
  HERO_NAME = 0x1B9B74, -- 8 charmap bytes (lib/Charmap.lua) + a 0 terminator at +8: the name typed at the start of the game. Text control code index 0 prints it (DAT_8017c1d8[0] = game state + 0x1b74, set by FUN_800c4ecc)
  CASTLE_NAME = 0x1B9B84, -- same layout, the name given to the castle (empty until then); text control code index 1
  ROOM_POINTER = 0x17DAA0,
  ROOM_SLOT_COUNT = 0x17DBFC, -- u8 (DAT_8017dbfc): exact number of 0x18-byte actor slots at ROOM_POINTER. See docs/game_mechanics/Zones_Areas_and_Rooms.md
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
  MENU_STATE_PTR = 0x179fe8, -- DAT_80179fe8, the battle menu system's own persistent context pointer (see lib/BattleRoundInput.lua)
  -- The main loop's scene-handler pointer array (DAT_8017da90, u32 per slot): the main-loop handler, then field main,
  -- field loader and menu scheduler slots. Used by lib/PartyChange.lua (slot 0), lib/ScreenTeleport.lua and BattleRoundInput.
  SCENE_HANDLER_MAIN_LOOP = 0x17da90,
  SCENE_HANDLER_FIELD_MAIN = 0x17da94,
  SCENE_HANDLER_FIELD_LOADER = 0x17da98,
  SCENE_HANDLER_MENU = 0x17da9c,
  FIELD_CTX_PTR = 0x17be20, -- pointer to the field's context struct (+0x34 "change screen" request byte; lib/ScreenTeleport.lua)
  -- lib/ForceBattle.lua. The v1.0 values are in V10 below (derived from the two main.exe files; confirmed working on v1.0 by the user).
  ROOM_RECORD_PTR = 0x17aae4, -- DAT_8017aae4: pointer to the current room record (+0x1c/+0x20 scripted-table list, +0x38 encounter block). Area overlay, so the pointer can be below 0x80100000
  ENCOUNTER_ARMED = 0x17159a, -- DAT_8017159a: field_check_random_encounter's armed flag (3 bytes before ENCOUNTER_RATE)
  WM_CTX_PTR = 0x17a0b8, -- DAT_8017a0b8: world-map context; *(ctx+0x2c)+0xc -> pointer to the region's encounter table pointer
}

-- Only the entries that differ in v1.0 (value = v1.0 address). The comment is the v1.1 address.
local V10 = {
  ITEM_DEFINITION_TABLE = 0x16bbfc, -- 0x167658; the u32 item pointers inside it are relocated too (+0x45a4)
  ITEM_NAME_PTR_1 = 0x16bc00,       -- 0x16765c
  ENCOUNTER_RATE = 0x175b11,        -- 0x17159D
  SESSION_FRAMECOUNT = 0x17b914,    -- 0x1783f8
  SOUL_EATER_CTX = 0x17d5ac,        -- 0x17a060
  FLAMING_ARROW_CTX_PTR = 0x17d57c, -- 0x17a030
  HERO_X = 0x180cb0,                -- 0x17BD74
  HERO_Y = 0x180cb1,                -- 0x17BD75
  HERO_DIRECTION_PTR = 0x180cb8,    -- 0x17BD7C
  BATTLE_STATE_PTR = 0x18157c,      -- 0x17be3c
  ROOM_POINTER = 0x181a98,          -- 0x17DAA0
  ROOM_SLOT_COUNT = 0x181be4,       -- 0x17DBFC
  MENU_STATE_PTR = 0x17d534,        -- 0x179fe8
  SCENE_HANDLER_MAIN_LOOP = 0x181a88,   -- 0x17da90
  SCENE_HANDLER_FIELD_MAIN = 0x181a8c,  -- 0x17da94
  SCENE_HANDLER_FIELD_LOADER = 0x181a90, -- 0x17da98
  SCENE_HANDLER_MENU = 0x181a94,        -- 0x17da9c
  FIELD_CTX_PTR = 0x180d60,         -- 0x17be20
  ROOM_RECORD_PTR = 0x180248,       -- 0x17aae4 (field_check_random_encounter, v1.0 at 0x8012c6d8: lw ...,0x248 under lui 0x8018)
  ENCOUNTER_ARMED = 0x175b0e,       -- 0x17159a (same function: lbu ...,0x5b0e under lui 0x8017)
  WM_CTX_PTR = 0x17d604,            -- 0x17a0b8 (wm_battle_start, v1.0 at 0x80128754: lw ...,-0x29fc under lui 0x8018)
}

local Address = AddressBuild.wrap(V11, V10)

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
