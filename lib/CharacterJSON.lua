-- Imports/exports characters' persistent Stats structs as JSON, in the format shared with
-- Suikoden-RNG-lib (docs/Character_JSON_Format.md). Reads and writes game memory directly by
-- offset, independent of the Character Editor's Data layout.
--
-- Only state that can change in game is exchanged; growths, weapon type, rune lock and the
-- unidentified bytes are left as they are. Ids (character roster id, rune id, item id) are the
-- game's own and are what import goes by; `key` fields are for reading and are checked when given.
--
-- This edits the persistent struct, not the battle copy (combatant_rec). Import outside battle:
-- battle load copies the struct in, so an in-battle import only takes effect next battle.

local json = require "lib.json"
local fs = require "lib.fs"
local Address = require "lib.Address"
local Names = require "lib.Characters.Names"
local Addresses = require "lib.Characters.Addresses"
local Party = require "lib.Party"

local OFFSET = {
  ID = 0x00,
  HP_MAX = 0x04, -- u16
  HP = 0x06, -- u16
  MP = 0x09, -- 4 bytes, spell levels 1-4
  LVL = 0x0d,
  EXP = 0x0e, -- u16
  PWR = 0x10, SKL = 0x11, DEF = 0x12, SPD = 0x13, MGC = 0x14, LUK = 0x15,
  STATUS = 0x16,
  ITEM_COUNT = 0x1f,
  ITEMS = 0x20, -- 9 slots of { u16 id, equip byte, quantity }
  WEAPON_LVL = 0x45,
  RUNE_PIECE_TYPE = 0x46,
  RUNE_PIECE_COUNTS = 0x47, -- 5 bytes, one per type; type N's count is at +0x46 + N
  RUNE = 0x4c,
}

local STAT_ORDER = { "PWR", "SKL", "DEF", "SPD", "MGC", "LUK" }
local MAX_ITEMS = 9

-- Rune_Piece_Type -> the element the weapon attacks as (RNG-lib WEAPON_ELEMENTS keys). Types 3
-- and 5 are labelled Wind/Earth in game (a game bug); this is the element they actually apply.
local PIECE_ELEMENTS = { "FIRE", "WATER", "EARTH", "LIGHTNING", "WIND" }
local PIECE_TYPES = { NONE = 0 }
for type, element in ipairs(PIECE_ELEMENTS) do PIECE_TYPES[element] = type end

-- Equip byte low 7 bits -> slot (DAT_8016a8c4 order, same as RNG-lib ARMOR_SLOT)
local SLOTS = { "HEAD", "BODY", "SHIELD", "ACCESSORY_1", "ACCESSORY_2" }
local SLOT_INDEX = {}
for index, slot in ipairs(SLOTS) do SLOT_INDEX[slot] = index end
local EQUIP_FIXED = 0x80
local APPRAISED = 0xff

-- Persistent status bits (see CharacterEditor/StatusMenu.lua). Balloon stages are cumulative.
local POISON = 0x01
local BALLOON_BITS = { [0] = 0x00, 0x02, 0x06, 0x0e }
local PERSISTENT_STATUS_MASK = 0x0f

-- HUD key names that differ from RNG-lib's CHARACTER_KEYS
local KEY_ALIASES = { HERO = "MCDOHL" }

-- Roster id -> { key, name, address }, for every character with a Stats struct
local BY_ID = {}
local BY_NAME = {}
local BY_ADDRESS = {}
for key, name in pairs(Names) do
  local addresses = Addresses[name]
  if addresses and addresses.Stats then
    local entry = { key = KEY_ALIASES[key] or key, name = name, address = addresses.Stats }
    BY_ID[addresses.Id] = entry
    BY_ADDRESS[addresses.Stats] = entry
    BY_NAME[name] = entry
    BY_NAME[key] = entry
    BY_NAME[entry.key] = entry
  end
end

local function readItemDefinition(id)
  local ptr = mainmemory.read_u32_le(Address.ITEM_DEFINITION_TABLE + id * 4)
  if not Address.isValidPointer(ptr) then return nil end
  ptr = Address.sanitize(ptr)
  local flags = mainmemory.read_u16_le(ptr + 0x1c)
  return {
    IsEquipment = flags & 0x80 ~= 0,
    IsAntique = flags & 0x7000 ~= 0,
    FullQuantity = mainmemory.read_u8(ptr + 0x1e),
  }
end

local function findCharacter(nameOrId)
  local entry = type(nameOrId) == "number" and BY_ID[nameOrId] or BY_NAME[nameOrId]
  if not entry then error("CharacterJSON: unknown character " .. tostring(nameOrId)) end
  return entry
end

-------------------------------------------------------------------------------
-- Export
-------------------------------------------------------------------------------

local function readItems(address)
  local items = {}
  local count = mainmemory.read_u8(address + OFFSET.ITEM_COUNT)
  for slot = 0, math.min(count, MAX_ITEMS) - 1 do
    local entryAddr = address + OFFSET.ITEMS + slot * 4
    local id = mainmemory.read_u16_le(entryAddr)
    local equip = mainmemory.read_u8(entryAddr + 2)
    local quantity = mainmemory.read_u8(entryAddr + 3)
    local def = readItemDefinition(id)
    if not def then error(string.format("CharacterJSON: item slot %d has invalid id %d", slot, id)) end

    local item = { id = id }
    if def.IsEquipment and equip ~= 0 then
      item.slot = SLOTS[equip & 0x7f]
      if not item.slot then
        error(string.format("CharacterJSON: item %d has unknown equip byte 0x%02x", id, equip))
      end
      if equip & EQUIP_FIXED ~= 0 then item.locked = true end
    elseif def.IsAntique then
      item.appraised = equip == APPRAISED
    end
    if quantity ~= 0 then item.quantity = quantity end
    table.insert(items, item)
  end
  return items
end

-- One character's state, as a table in the shared format. Takes a HUD name ("Cleo"), key
-- ("CLEO") or roster id.
local function readCharacter(nameOrId)
  local entry = findCharacter(nameOrId)
  local address = entry.address
  local u8 = function(offset) return mainmemory.read_u8(address + offset) end
  local u16 = function(offset) return mainmemory.read_u16_le(address + offset) end

  local stats = { HP = u16(OFFSET.HP_MAX) }
  for i, stat in ipairs(STAT_ORDER) do stats[stat] = u8(OFFSET.PWR + i - 1) end

  local pieceType = u8(OFFSET.RUNE_PIECE_TYPE)
  if pieceType ~= 0 and not PIECE_ELEMENTS[pieceType] then
    error(string.format("CharacterJSON: %s has unknown rune piece type %d", entry.name, pieceType))
  end

  local status = u8(OFFSET.STATUS)
  -- The highest stage whose own bit is set, as StatusMenu reads it
  local balloon = 0
  for stage = 3, 1, -1 do
    if status & (0x01 << stage) ~= 0 then balloon = stage; break end
  end

  return {
    key = entry.key,
    id = u8(OFFSET.ID),
    LVL = u8(OFFSET.LVL),
    EXP = u16(OFFSET.EXP),
    stats = stats,
    HP = u16(OFFSET.HP),
    MP = { u8(OFFSET.MP), u8(OFFSET.MP + 1), u8(OFFSET.MP + 2), u8(OFFSET.MP + 3) },
    rune = { id = u8(OFFSET.RUNE) },
    weapon = {
      lvl = u8(OFFSET.WEAPON_LVL),
      runePiece = {
        element = pieceType == 0 and "NONE" or PIECE_ELEMENTS[pieceType],
        amount = pieceType == 0 and 0 or u8(OFFSET.RUNE_PIECE_TYPE + pieceType),
      },
    },
    status = { poison = status & POISON ~= 0, balloon = balloon },
    inventory = readItems(address),
  }
end

-------------------------------------------------------------------------------
-- Import
-------------------------------------------------------------------------------

-- An integer in [min, max], or an error naming the field
local function int(value, field, min, max)
  local n = type(value) == "number" and math.tointeger(value)
  if not n or n < min or n > max then
    error(string.format("CharacterJSON: %s must be an integer %d-%d, got %s", field, min, max,
      tostring(value)))
  end
  return n
end

-- Checks a character table and turns it into the bytes to write. Errors before anything is
-- written, so a bad file never leaves a character half-imported.
local function prepareCharacter(c)
  if type(c) ~= "table" then error("CharacterJSON: character entry must be an object") end
  local id = int(c.id, "id", 0, 255)
  local entry = BY_ID[id]
  if not entry then error("CharacterJSON: no Stats struct for character id " .. id) end
  if c.key ~= nil and c.key ~= entry.key then
    error(string.format("CharacterJSON: id %d is %s, not %s", id, entry.key, tostring(c.key)))
  end
  local where = entry.key .. "."
  local stats = c.stats or {}

  local p = { entry = entry }
  p.HP_MAX = int(stats.HP, where .. "stats.HP", 0, 0xffff)
  for _, stat in ipairs(STAT_ORDER) do p[stat] = int(stats[stat], where .. "stats." .. stat, 0, 255) end
  p.LVL = int(c.LVL, where .. "LVL", 1, 99)
  p.EXP = int(c.EXP, where .. "EXP", 0, 0xffff)
  p.HP = int(c.HP, where .. "HP", 0, 0xffff)
  if type(c.MP) ~= "table" or #c.MP ~= 4 then error("CharacterJSON: " .. where .. "MP must have 4 entries") end
  p.MP = {}
  for i = 1, 4 do p.MP[i] = int(c.MP[i], where .. "MP[" .. i .. "]", 0, 255) end
  p.RUNE = int((c.rune or {}).id, where .. "rune.id", 0, 255)

  local weapon = c.weapon or {}
  local piece = weapon.runePiece or {}
  p.WEAPON_LVL = int(weapon.lvl, where .. "weapon.lvl", 1, 255)
  p.PIECE_TYPE = PIECE_TYPES[piece.element]
  if not p.PIECE_TYPE then
    error("CharacterJSON: " .. where .. "weapon.runePiece.element unknown: " .. tostring(piece.element))
  end
  p.PIECE_COUNT = int(piece.amount, where .. "weapon.runePiece.amount", 0, 255)
  if p.PIECE_TYPE == 0 and p.PIECE_COUNT ~= 0 then
    error("CharacterJSON: " .. where .. "weapon.runePiece has an amount but no element")
  end

  local status = c.status or {}
  p.STATUS = (status.poison and POISON or 0) |
    BALLOON_BITS[int(status.balloon or 0, where .. "status.balloon", 0, 3)]

  local inventory = c.inventory or {}
  if #inventory > MAX_ITEMS then
    error(string.format("CharacterJSON: %sinventory holds at most %d items", where, MAX_ITEMS))
  end
  p.ITEMS = {}
  local usedSlots = {}
  for i, item in ipairs(inventory) do
    local field = string.format("%sinventory[%d]", where, i)
    local itemId = int(item.id, field .. ".id", 1, 0xffff)
    local def = readItemDefinition(itemId)
    if not def then error("CharacterJSON: " .. field .. " has invalid item id " .. itemId) end

    local equip = 0
    if item.slot ~= nil then
      local slotIndex = SLOT_INDEX[item.slot]
      if not slotIndex or not def.IsEquipment then
        error("CharacterJSON: " .. field .. " can't be worn in slot " .. tostring(item.slot))
      end
      if usedSlots[item.slot] then error("CharacterJSON: " .. field .. " slot " .. item.slot .. " already taken") end
      usedSlots[item.slot] = true
      equip = slotIndex | (item.locked and EQUIP_FIXED or 0)
    elseif def.IsAntique and item.appraised ~= false then
      equip = APPRAISED
    end

    local defaultQuantity = def.IsEquipment and 0 or def.FullQuantity
    local quantity = item.quantity == nil and defaultQuantity or int(item.quantity, field .. ".quantity", 0, 255)
    table.insert(p.ITEMS, { id = itemId, equip = equip, quantity = quantity })
  end
  return p
end

local function writePrepared(p)
  local address = p.entry.address
  local w8 = function(offset, value) mainmemory.write_u8(address + offset, value) end
  local w16 = function(offset, value) mainmemory.write_u16_le(address + offset, value) end

  w16(OFFSET.HP_MAX, p.HP_MAX)
  w16(OFFSET.HP, p.HP)
  for i = 1, 4 do w8(OFFSET.MP + i - 1, p.MP[i]) end
  w8(OFFSET.LVL, p.LVL)
  w16(OFFSET.EXP, p.EXP)
  for i, stat in ipairs(STAT_ORDER) do w8(OFFSET.PWR + i - 1, p[stat]) end

  local status = mainmemory.read_u8(address + OFFSET.STATUS)
  w8(OFFSET.STATUS, (status & ~PERSISTENT_STATUS_MASK & 0xff) | p.STATUS)

  w8(OFFSET.WEAPON_LVL, p.WEAPON_LVL)
  -- Only the active type's count is kept; the other four are zeroed, as equipping a piece does
  w8(OFFSET.RUNE_PIECE_TYPE, p.PIECE_TYPE)
  for i = 0, #PIECE_ELEMENTS - 1 do w8(OFFSET.RUNE_PIECE_COUNTS + i, 0) end
  if p.PIECE_TYPE ~= 0 then w8(OFFSET.RUNE_PIECE_TYPE + p.PIECE_TYPE, p.PIECE_COUNT) end
  w8(OFFSET.RUNE, p.RUNE)

  w8(OFFSET.ITEM_COUNT, #p.ITEMS)
  for slot = 0, MAX_ITEMS - 1 do
    local entryAddr = OFFSET.ITEMS + slot * 4
    local item = p.ITEMS[slot + 1] or { id = 0, equip = 0, quantity = 0 }
    w16(entryAddr, item.id)
    w8(entryAddr + 2, item.equip)
    w8(entryAddr + 3, item.quantity)
  end
end

-- Writes one character table (shared format) into its Stats struct
local function writeCharacter(c)
  writePrepared(prepareCharacter(c))
end

-------------------------------------------------------------------------------
-- Files
-------------------------------------------------------------------------------

-- A file is a JSON array of character tables
local function encode(characters)
  return json.encode(characters)
end

local function decode(str)
  local characters = json.decode(str)
  if type(characters) ~= "table" then error("CharacterJSON: expected an array of characters") end
  return characters
end

-- Writes the named characters (HUD names, keys or ids) to a JSON file
local function exportFile(path, names)
  local characters = {}
  for _, name in ipairs(names) do table.insert(characters, readCharacter(name)) end
  local ok, err = fs.writeFile(path, encode(characters))
  if not ok then error("CharacterJSON: couldn't write " .. path .. ": " .. tostring(err)) end
  return characters
end

-- HUD names of the characters in the current party, in formation order. The party's slots point at
-- each character's persistent Stats struct, which is what BY_ADDRESS is keyed by.
local function partyNames()
  local names = {}
  for slot = 0, Party.getPartySize() - 1 do
    local address = Party.getCharacterDataAddress(slot)
    local entry = BY_ADDRESS[address]
    if not entry then
      error(string.format("CharacterJSON: party slot %d (0x%06x) is not a known Stats struct", slot, address))
    end
    table.insert(names, entry.name)
  end
  return names
end

-- Writes the current party to a JSON file. Returns the characters written.
local function exportParty(path)
  return exportFile(path, partyNames())
end

-- Imports every character in a JSON file. All are checked before any is written. Returns the
-- keys written.
local function importFile(path)
  local content, err = fs.readFile(path)
  if not content then error("CharacterJSON: couldn't read " .. path .. ": " .. tostring(err)) end
  local prepared = {}
  for _, c in ipairs(decode(content)) do table.insert(prepared, prepareCharacter(c)) end
  local keys = {}
  for _, p in ipairs(prepared) do
    writePrepared(p)
    table.insert(keys, p.entry.key)
  end
  return keys
end

return {
  readCharacter = readCharacter,
  writeCharacter = writeCharacter,
  encode = encode,
  decode = decode,
  exportFile = exportFile,
  importFile = importFile,
  partyNames = partyNames,
  exportParty = exportParty,
}
