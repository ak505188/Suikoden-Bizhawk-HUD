local Charmap = require "lib.Charmap"
local Address = require "lib.Address"

local Gamestate = mainmemory.read_u8(Address.GAMESTATE)
local BattleStruct = nil
local EnemyTablesByAddr = {}
local ItemNames = {}
local UpdateBattleStructWait = -1
local UpdateBattleStructTimer = 1

function UpdateGamestate ()
  local currentState = mainmemory.read_u8(Address.GAMESTATE)
  if currentState == Gamestate then return false end
  Gamestate = currentState
  return true
end

function GetEnemyData()
  local enemyGroupAddr = bit.band(
    mainmemory.read_u32_le(Address.ENEMY_STRUCT_PTR),
    0x7fffffff)
  local encounterTableAddr = bit.band(
    mainmemory.read_u32_le(Address.ENEMY_ENC_TABLE_PTR),
    0x7fffffff)

  local groupSize = mainmemory.read_u8(enemyGroupAddr)
  local enemies = mainmemory.read_bytes_as_array(enemyGroupAddr + 4, 6)

  local EnemyTable = EnemyTablesByAddr[encounterTableAddr]
  if not EnemyTable then
    EnemyTable = ReadEnemyTable(encounterTableAddr)
    EnemyTablesByAddr[encounterTableAddr] = EnemyTable
  end

  local battleStruct = {
    Enemies = {}
  }

  for i=1,#enemies,1 do
    battleStruct.Enemies[i] = EnemyTable[enemies[i]]
  end
  return battleStruct
end

function ReadEnemyTable(addr)
  local encounterTableLength = mainmemory.read_u8(addr)
  local enemies = {}
  for i=1, encounterTableLength, 1 do
    local enemy = {}
    local enemyAddr = bit.band(
      mainmemory.read_u32_le(addr + i * 4),
      0x7fffffff)
    local enemyRawData = mainmemory.read_bytes_as_array(enemyAddr, 60)
    enemy.Address = enemyAddr
    enemy.Name = Charmap.readStringFromList(enemyRawData, 0, 15)
    enemy.LVL = enemyRawData[16] * 256 + enemyRawData[17]
    enemy.HP = enemyRawData[18] * 256 + enemyRawData[19]
    enemy.PWR = enemyRawData[20] * 256 + enemyRawData[21]
    enemy.SKL = enemyRawData[22] * 256 + enemyRawData[23]
    enemy.DEF = enemyRawData[24] * 256 + enemyRawData[25]
    enemy.SPD = enemyRawData[26] * 256 + enemyRawData[27]
    enemy.MGC = enemyRawData[28] * 256 + enemyRawData[29]
    enemy.LUK = enemyRawData[30] * 256 + enemyRawData[31]
    enemy.Bits = enemyRawData[53] + 256 * enemyRawData[54]
    enemy.Drops = {}
    for j=1,3,1 do
      local id = enemyRawData[53 + j * 2]
      if id ~= 0 then
        local item_name = ItemNames[id]
        if not item_name then
          item_name = GetItemName(id)
          ItemNames[id] = item_name
        end
        local chance = enemyRawData[53 + j * 2 + 1]
        enemy.Drops[j] = {
          Id = id,
          Chance = chance,
          Name = item_name
        }
      end
    end
    enemies[i] = enemy
  end
  return enemies
end

function GetItemName(id)
  local item_name_addr = bit.band(
      mainmemory.read_u32_le(Address.ITEM_NAME_PTR_1 + (id - 1) * 4),
      0x7fffffff)
  local item_name_raw_data = mainmemory.read_bytes_as_array(item_name_addr, 16)
  return Charmap.readStringFromList(item_name_raw_data)
end

while true do
  gui.cleartext()
  local stateChanged = UpdateGamestate()
  if stateChanged and Gamestate == 3 then
    -- Get Battle Info here
    UpdateBattleStructWait = UpdateBattleStructTimer
  elseif stateChanged and Gamestate ~= 3 then
    BattleStruct = nil
  end
  if UpdateBattleStructWait == 0 then
    BattleStruct = GetEnemyData()
    -- for _,v in ipairs(BattleStruct.Enemies[1].Drops) do
    --   console.log(v)
    -- end
  end
  if BattleStruct then
    local x = 0
    local y = 16
    for i=1,#BattleStruct.Enemies,1 do
      gui.text(x,y, string.format("%s 0x%x", BattleStruct.Enemies[i].Name, BattleStruct.Enemies[i].Address))
      y = y + 16
    end
  end
  if UpdateBattleStructWait >= 0 then
    UpdateBattleStructWait = UpdateBattleStructWait - 1
  end
  emu.frameadvance()
end

-- Process
-- Check if changed from not in battle to battle.
-- If so, read EMEMY_STRUCT_PTR and get ENEMY_STRUCT_ADDR
-- Read what different enemies are in group, and add to Set
-- Maybe make list as well?

