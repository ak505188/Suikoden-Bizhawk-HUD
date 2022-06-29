local Addresses = {}
Addresses.GAMESTATE_BASE = 0x1b8000
Addresses.PARTY_SIZE = Addresses.GAMESTATE_BASE + 3
-- Character 1 offset is at this address
-- Offset range is 0-5
Addresses.CHARACTER_OFFSETS = Addresses.GAMESTATE_BASE + 0xe

local ChampionRuneID = 24

local PartyLib = {}

function sanitizeAddress(addr)
  return bit.band(addr, 0x001fffff)
end

local function getPartySize()
  return memory.read_u8(Addresses.PARTY_SIZE)
end

local function getCharacterDataAddress(formationSlot)
  local offset = memory.read_u8(Addresses.CHARACTER_OFFSETS + formationSlot)
  local ptr1 = Addresses.GAMESTATE_BASE + offset * 4
  local ptr2 = sanitizeAddress(memory.read_u32_le(ptr1 + 0x1b9c))
  return sanitizeAddress(memory.read_u32_le(sanitizeAddress(ptr2 + 0x1c)))
end

local function getCharacterRune(character_data_address)
  return memory.read_u8(character_data_address + 0x4c)
end

local function getCharacterLVL(character_data_address)
  return memory.read_u8(character_data_address + 0xd)
end

local function isChampionsRuneEquipped()
  for i = 0,getPartySize()-1 do
    local char_addr = getCharacterDataAddress(i)
    local char_rune = getCharacterRune(char_addr)
    if char_rune == ChampionRuneID then return true end
  end
  return false
end

local firstRun = false

local function getPartyLVL()
  local lvl_sum = 0
  for i = 0,getPartySize()-1 do
    local char_addr = getCharacterDataAddress(i)
    local charLVL = getCharacterLVL(char_addr)
    if not firstRun then
      print(string.format("0x%x %d", char_addr, charLVL))
    end
    lvl_sum = lvl_sum + charLVL
  end
  firstRun = true
  return lvl_sum
end

PartyLib.getPartySize = getPartySize
PartyLib.isChampionsRuneEquipped = isChampionsRuneEquipped
PartyLib.getCharacterDataAddress = getCharacterDataAddress
PartyLib.getCharacterRune = getCharacterRune
PartyLib.getCharacterLVL = getCharacterLVL
PartyLib.getPartyLVL = getPartyLVL

return PartyLib;
