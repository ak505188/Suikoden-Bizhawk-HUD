local Address = {
  GAMESTATE = 0x1B9BBC,
  PREV_GAMESTATE = 0x1B9BB8,
  WM_ZONE = 0x1B8002,
  AREA_ZONE = 0x1B8000,
  SCREEN_ZONE = 0x1B8001,
  ENCOUNTER_RATE = 0x17159D,
  RNG = 0x9010,
  EVENT_ID = 0x1B9BC0,
  ENEMY_GROUP_PTR = 0x197F10,
  ENCOUNTER_TABLE_PTR = 0x197F14,
  ITEM_NAME_PTR_1 = 0x16765c,
  BATTLE_ITEM_DROP = 0x18FAF0,
  GAMESTATE_BASE = 0x1B8000,
  PARTY_SIZE = 0x1B8003,
  CHARACTER_OFFSETS = 0x1B800e,
  HERO_X = 0x17BD74,
  HERO_Y = 0x17BD75,
  HERO_DIRECTION_PTR = 0x17BD7C,
  ROOM_POINTER = 0x17DAA0,
  SESSION_FRAMECOUNT = 0x1783f8, -- Kinda loadless, not completely accurate to save IGT
  SAVE_FRAMECOUNT = 0x18B0A8 -- Not sure how to calculate real IGT, missing some value
  -- Other IGT options are 17DBE8 (stops on loads?), 1B9B8C (Updated on save)
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
