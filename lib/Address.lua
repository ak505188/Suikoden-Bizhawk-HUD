local Address = {
  GAMESTATE = 0x1b9bbc,
  PREV_GAMESTATE = 0x1b9bb8,
  WM_ZONE = 0x1b8002,
  AREA_ZONE = 0x1b8000,
  SCREEN_ZONE = 0x1b8001,
  ENCOUNTER_RATE = 0x17159D,
  RNG = 0x9010,
  EVENT_ID = 0x1B9BC0,
  ENEMY_GROUP_PTR = 0x197f10,
  ENCOUNTER_TABLE_PTR = 0x197f14,
  ITEM_NAME_PTR_1 = 0x16765c,
  BATTLE_ITEM_DROP = 0x18faf0,
  GAMESTATE_BASE = 0x1b8000,
  PARTY_SIZE = 0x1b8003,
  CHARACTER_OFFSETS = 0x1b800e,
  HERO_X = 0x17BD74,
  HERO_Y = 0x17BD75,
  HERO_DIRECTION = 0x18b4c0,
  ROOM_POINTER = 0x17daa0,
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
