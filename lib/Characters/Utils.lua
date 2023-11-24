local Utils = require "lib.Utils"

local readFromByteTable = Utils.readFromByteTable

local function readCharacterData(character)
  -- All addresses are offset by 1 because of lua tables starting at 1
  local stats_address = character.stats_address
  if stats_address == nil then return nil end

  local buffer = mainmemory.read_bytes_as_array(stats_address, 0x50)
  local items = {
    Count = buffer[0x1C],
  }

  for i = 1, 9, 1 do
    local offset = 0x1D + (4 * (i - 1))
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
    Stats = {
      HP_Max = readFromByteTable(buffer, 0x1, 2),
      HP_Current = readFromByteTable(buffer, 0x3, 2),
      MP = {
        buffer[0x6],
        buffer[0x7],
        buffer[0x8],
        buffer[0x9],
      },
      LVL = buffer[0xA],
      EXP = readFromByteTable(buffer, 0xB, 2),
      PWR = buffer[0xD],
      SKL = buffer[0xE],
      DEF = buffer[0xF],
      SPD = buffer[0x10],
      MGC = buffer[0x11],
      LUK = buffer[0x12],
    },
    Growths = {
      PWR = buffer[0x15],
      SKL = buffer[0x16],
      DEF = buffer[0x17],
      SPD = buffer[0x18],
      MGC = buffer[0x19],
      LUK = buffer[0x1A],
      HP = buffer[0x1B],
    },
    Weapon = {
      Type = buffer[0x41],
      Level = buffer[0x42],
      Rune_Piece_Type = buffer[0x43],
      Fire_Piece_Count = buffer[0x44],
      Water_Piece_Count = buffer[0x45],
      Wind_Piece_Count = buffer[0x46],
      Thunder_Piece_Count = buffer[0x47],
      Earth_Piece_Count = buffer[0x48],
    },
    Status = buffer[0x13],
    Items = items,
    Unknowns = {
      ['0x13'] = buffer[0x14],
      ['0x4a'] = buffer[0x4b],
      ['0x4b'] = buffer[0x4c],
      ['0x4c'] = buffer[0x4d],
      ['0x4d'] = buffer[0x4e],
      ['0x4e'] = buffer[0x4f],
      ['0x4f'] = buffer[0x50],
    }
  }

  return data
end

local function characterDataToStr(cd)
  local name = string.format(
    "%s LVL:%d.%03d S:%x",
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
    "Unknowns: 0x13:0x%x 0x4a:0x%x 0x4b:0x%x 0x4c:0x%x 0x4d:0x%x 0x4e:0x%x 0x4f:0x%x",
    cd.Unknowns['0x13'],
    cd.Unknowns['0x4a'],
    cd.Unknowns['0x4b'],
    cd.Unknowns['0x4c'],
    cd.Unknowns['0x4d'],
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

return {
  characterDataToStr = characterDataToStr,
  readCharacterData = readCharacterData
}
