local Names = require "lib.Characters.NamesList"
local Growths = require "lib.Characters.Growths"
local Addresses = require "lib.Characters.Addresses"
local Utils = require "lib.Utils"

local readFromByteTable = Utils.readFromByteTable

local function CharacterBuilder(name)
  local character = {}
  local addresses = {}

  character.Name = name

  local recruited_address = Addresses[name].RecruitmentState
  if recruited_address then addresses.Recruited = recruited_address end

  local stats_address = Addresses[name].Stats
  character.IsCombat = stats_address ~= nil
  if stats_address then addresses.Stats = stats_address end

  character.Address = addresses
  if not character.IsCombat then return character end

  character.Growths = Growths[name]
  character.Data = {}

  function character:read()
    -- All addresses are offset by 1 because of lua tables starting at 1
    local address = self.Address.Stats

    local buffer = mainmemory.read_bytes_as_array(address, 0x50)
    local items = {
      Count = buffer[0x20],
    }

    for i = 1, 9, 1 do
      local offset = 0x21 + (4 * (i - 1))
      local item_id = buffer[offset]
      local item_unknown = buffer[offset + 1]
      local item_equipped = buffer[offset + 2]
      local item_quantity = buffer[offset + 3]
      items[i] = {
        Id = item_id,
        Unknown = item_unknown,
        Equipped = item_equipped,
        Quantity = item_quantity
      }
    end

    local data = {
      Name = character.name,
      Address = character.stats_address,
      Id = buffer[0x1],
      Stats = {
        HP_Max = readFromByteTable(buffer, 0x5, 2),
        HP_Current = readFromByteTable(buffer, 0x7, 2),
        MP = {
          buffer[0xa],
          buffer[0xb],
          buffer[0xc],
          buffer[0xd],
        },
        LVL = buffer[0xE],
        EXP = readFromByteTable(buffer, 0xF, 2),
        PWR = buffer[0x11],
        SKL = buffer[0x12],
        DEF = buffer[0x13],
        SPD = buffer[0x14],
        MGC = buffer[0x15],
        LUK = buffer[0x16],
      },
      Growths = {
        PWR = buffer[0x19],
        SKL = buffer[0x1a],
        DEF = buffer[0x1b],
        SPD = buffer[0x1c],
        MGC = buffer[0x1d],
        LUK = buffer[0x1E],
        HP = buffer[0x1F],
      },
      Weapon = {
        Type = buffer[0x45],
        Level = buffer[0x46],
        Rune_Piece_Type = buffer[0x47],
        Fire_Piece_Count = buffer[0x48],
        Water_Piece_Count = buffer[0x49],
        Wind_Piece_Count = buffer[0x4a],
        Thunder_Piece_Count = buffer[0x4b],
        Earth_Piece_Count = buffer[0x4c],
      },
      Rune = {
        Id = buffer[0x4d],
        Locked = buffer[0x4e],
      },
      Status = buffer[0x17],
      Items = items,
      Unknowns = {
        ['0x1'] = buffer[2],
        ['0x2'] = buffer[3],
        ['0x3'] = buffer[4],
        ['0x8'] = buffer[9],
        ['0x17'] = buffer[0x18],
        ['0x4e'] = buffer[0x4f],
        ['0x4f'] = buffer[0x50],
      }
    }
    self.Data = data
  end

  function character:write()
    local address = self.Address.Stats

    local function writeStats(stats)
      memory.write_u16_le(address + 0x4, stats.HP_Max)
      memory.write_u16_le(address + 0x6, stats.HP_Current)
      memory.write_u8(address + 0x9, stats.MP[1])
      memory.write_u8(address + 0xa, stats.MP[2])
      memory.write_u8(address + 0xb, stats.MP[3])
      memory.write_u8(address + 0xc, stats.MP[4])
      memory.write_u8(address + 0xd, stats.LVL)
      memory.write_u16_le(address + 0xe, stats.EXP)
      memory.write_u8(address + 0x10, stats.PWR)
      memory.write_u8(address + 0x11, stats.SKL)
      memory.write_u8(address + 0x12, stats.DEF)
      memory.write_u8(address + 0x13, stats.SPD)
      memory.write_u8(address + 0x14, stats.MGC)
      memory.write_u8(address + 0x15, stats.LUK)
    end

    local function writeWeapon(weapon)
      memory.write_u8(address + 0x44, weapon.Type)
      memory.write_u8(address + 0x45, weapon.Level)
      memory.write_u8(address + 0x46, weapon.Rune_Piece_Type)
      memory.write_u8(address + 0x47, weapon.Fire_Piece_Count)
      memory.write_u8(address + 0x48, weapon.Water_Piece_Count)
      memory.write_u8(address + 0x49, weapon.Wind_Piece_Count)
      memory.write_u8(address + 0x4a, weapon.Thunder_Piece_Count)
      memory.write_u8(address + 0x4b, weapon.Earth_Piece_Count)
    end

    local function writeItems(items)
      memory.write_u8(address + 0x1f, items.Count)
      for i = 1, 9, 1 do
        local offset = 0x20 + (4 * (i - 1))
        local item = items[i]
        memory.write_u8(address + offset, item.Id)
        memory.write_u8(address + offset + 1, item.Unknown)
        memory.write_u8(address + offset + 2, item.Equipped)
        memory.write_u8(address + offset + 3, item.Quantity)
      end
    end

    local function writeUnknowns(unknowns)
      memory.write_u8(address + 1, unknowns['0x1'])
      memory.write_u8(address + 2, unknowns['0x2'])
      memory.write_u8(address + 3, unknowns['0x3'])
      memory.write_u8(address + 8, unknowns['0x8'])
      memory.write_u8(address + 0x17, unknowns['0x17'])
      memory.write_u8(address + 0x4e, unknowns['0x4e'])
      memory.write_u8(address + 0x4f, unknowns['0x4f'])
    end

    local function writeStatus(status)
      memory.write_u8(address + 0x16, status)
    end

    local function writeRune(rune)
      memory.write_u8(address + 0x4c, rune.Id)
      memory.write_u8(address + 0x4d, rune.Locked)
    end

    writeStats(self.Data.Stats)
    writeWeapon(self.Data.Weapon)
    writeItems(self.Data.Items)
    writeUnknowns(self.Data.Unknowns)
    writeStatus(self.Data.Status)
    writeRune(self.Data.Rune)
  end

  return character
end

local characters = {}

for _, name in ipairs(Names) do
  characters[name] = CharacterBuilder(name)
end

return characters
