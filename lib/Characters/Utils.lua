local Utils = require "lib.Utils"

local readFromByteTable = Utils.readFromByteTable

local function readCharacterData(character)
  -- All addresses are offset by 1 because of lua tables starting at 1
  local stats_address = character.stats_address
  if stats_address == nil then return nil end

  local buffer = mainmemory.read_bytes_as_array(stats_address, 0x50)
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

  return data
end

local function characterDataToStr(cd)
  local name = string.format(
    "%d %s LVL:%d.%03d S:%x",
    cd.Id,
    cd.Name,
    cd.Stats.LVL,
    cd.Stats.EXP,
    cd.Status)
  local HP_and_MP = string.format(
    "%d/%d %d/%d/%d/%d",
    cd.Stats.HP_Current,
    cd.Stats.HP_Max,
    cd.Stats.MP[1],
    cd.Stats.MP[2],
    cd.Stats.MP[3],
    cd.Stats.MP[4])
  local stat_labels = string.format("PWR SKL DEF SPD MGC LUK")
  local stats = string.format(
    "%03d %03d %03d %03d %03d %03d",
    cd.Stats.PWR,
    cd.Stats.SKL,
    cd.Stats.DEF,
    cd.Stats.SPD,
    cd.Stats.MGC,
    cd.Stats.LUK)
  local stats_growths = string.format(
    "Growths - PWR:%d SKL:%d DEF:%d SPD:%d MGC:%d LUK:%d HP:%d",
    cd.Growths.PWR,
    cd.Growths.SKL,
    cd.Growths.DEF,
    cd.Growths.SPD,
    cd.Growths.MGC,
    cd.Growths.LUK,
    cd.Growths.HP)

  local weapon_info = string.format(
    "WPN:%d LVL:%d RPT:%d Fi:%d Wa:%d Wi:%d Th:%d Ea:%d",
    cd.Weapon.Type,
    cd.Weapon.Level,
    cd.Weapon.Rune_Piece_Type,
    cd.Weapon.Fire_Piece_Count,
    cd.Weapon.Water_Piece_Count,
    cd.Weapon.Wind_Piece_Count,
    cd.Weapon.Thunder_Piece_Count,
    cd.Weapon.Earth_Piece_Count
  )

  local item_info = string.format("Item Count: %d", cd.Items.Count)
  local item_strings = {}

  for i = 1, 9, 1 do
    local item = cd.Items[i]
    local item_str = string.format(
      "%d. Id:%d Unknown:0x%x Equipped:0x%x Quantity:%d",
      i,
      item.Id,
      item.Unknown,
      item.Equipped,
      item.Quantity)
    table.insert(item_strings, item_str)
  end

  local items_str = table.concat(item_strings, "\n")
  local unknowns_str = string.format(
    "Unknowns: 0x1:0x%x 0x2:0x%x 0x3:0x%x 0x8:0x%x 0x17:0x%x 0x4e:0x%x 0x4f:0x%x",
    cd.Unknowns['0x1'],
    cd.Unknowns['0x2'],
    cd.Unknowns['0x3'],
    cd.Unknowns['0x8'],
    cd.Unknowns['0x17'],
    cd.Unknowns['0x4e'],
    cd.Unknowns['0x4f']
  )

  local strs = {
    name,
    HP_and_MP,
    stat_labels,
    stats,
    stats_growths,
    weapon_info,
    item_info,
    items_str,
    unknowns_str
  }

  return table.concat(strs, "\n")
end

local function writeCharacterData(character_data)
  local address = character_data.Address

  local function writeStats(stats)
    memory.write_u16_le(address + 0x4, stats.HP_Max)
    memory.write_u16_le(address + 0x6, stats.HP_Current)
    memory.write_u8(address + 0x9, stats.MP[1])
    memory.write_u8(address + 0xa, stats.MP[2])
    memory.write_u8(address + 0xb, stats.MP[3])
    memory.write_u8(address + 0xc, stats.MP[4])
    memory.write_u8(address + 0xd, stats.LVL)
    memory.write_u16(address + 0xe, stats.EXP)
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

  writeStats(character_data.Stats)
  writeWeapon(character_data.Weapon)
  writeItems(character_data.Items)
  writeUnknowns(character_data.Unknowns)
  writeStatus(character_data.Status)
  writeRune(character_data.Rune)
end

return {
  characterDataToStr = characterDataToStr,
  readCharacterData = readCharacterData,
  writeCharacterData = writeCharacterData,
}
