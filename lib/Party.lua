local Address = require "lib.Address"

local ChampionRuneID = 24

local PartyLib = {}

local function getPartySize()
  return memory.read_u8(Address.PARTY_SIZE)
end

local function getCharacterDataAddress(formationSlot)
  local offset = memory.read_u8(Address.CHARACTER_OFFSETS + formationSlot)
  local ptr1 = Address.GAMESTATE_BASE + offset * 4
  local ptr2 = Address.sanitize(memory.read_u32_le(ptr1 + 0x1b9c))
  return Address.sanitize(memory.read_u32_le(Address.sanitize(ptr2 + 0x1c)))
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

local function getPartyLVL(partySize)
  partySize = partySize or getPartySize()
  local lvl_sum = 0
  for i = 0,getPartySize()-1 do
    local char_addr = getCharacterDataAddress(i)
    local charLVL = getCharacterLVL(char_addr)
    lvl_sum = lvl_sum + charLVL
  end
  return lvl_sum
end

PartyLib.getPartySize = getPartySize
PartyLib.isChampionsRuneEquipped = isChampionsRuneEquipped
PartyLib.getCharacterDataAddress = getCharacterDataAddress
PartyLib.getCharacterRune = getCharacterRune
PartyLib.getCharacterLVL = getCharacterLVL
PartyLib.getPartyLVL = getPartyLVL

return PartyLib;
