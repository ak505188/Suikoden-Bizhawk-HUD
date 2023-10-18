local Charmap = require "lib.Charmap"
local Address = require "lib.Address"
local Utils = require "lib.Utils"
local RNGLib = require "lib.RNG"
local RNGMonitor = require "monitors.RNG_Monitor"

local EnemyTablesByAddr = {}
local ItemNames = {}

local function getItemName(id)
  local item_name_addr = memory.read_u32_le(Address.ITEM_NAME_PTR_1 + (id - 1) * 4) & 0x7fffffff
  local item_name_raw_data = memory.read_bytes_as_array(item_name_addr, 16)
  return Charmap.readStringFromList(item_name_raw_data)
end

local function readEnemyTable(addr)
  local encounterTableLength = memory.read_u8(addr)
  local enemies = {}
  for i=1, encounterTableLength, 1 do
    local enemy = {}
    local enemyAddr = Address.sanitize(memory.read_u32_le(addr + i * 4))
    local enemyRawData = memory.read_bytes_as_array(enemyAddr, 60)
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
          item_name = getItemName(id)
          ItemNames[id] = item_name
        end
        local chance = enemyRawData[53 + j * 2 + 1]
        enemy.Drops[j] = {
          id = id,
          chance = chance,
          name = item_name
        }
      end
    end
    enemies[i] = enemy
  end
  return enemies
end

local function getEnemyData()
  local enemyGroupAddr = Address.sanitize(memory.read_u32_le(Address.ENEMY_STRUCT_PTR))
  local encounterTableAddr = Address.sanitize(memory.read_u32_le(Address.ENEMY_ENC_TABLE_PTR))

  local groupSize = memory.read_u8(enemyGroupAddr)
  local enemies = memory.read_bytes_as_array(enemyGroupAddr + 4, 6)

  local EnemyTable = EnemyTablesByAddr[encounterTableAddr]
  if not EnemyTable then
    EnemyTable = readEnemyTable(encounterTableAddr)
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

-- while true do
--   gui.cleartext()
--   local stateChanged = UpdateGamestate()
--   if stateChanged and Gamestate == 3 then
--     -- Get Battle Info here
--     UpdateBattleStructWait = UpdateBattleStructTimer
--   elseif stateChanged and Gamestate ~= 3 then
--     BattleStruct = nil
--   end
--   if UpdateBattleStructWait == 0 then
--     BattleStruct = GetEnemyData()
--     -- for _,v in ipairs(BattleStruct.Enemies[1].Drops) do
--     --   console.log(v)
--     -- end
--   end
--   if BattleStruct then
--     local x = 0
--     local y = 16
--     for i=1,#BattleStruct.Enemies,1 do
--       gui.text(x,y, string.format("%s 0x%x", BattleStruct.Enemies[i].Name, BattleStruct.Enemies[i].Address))
--       y = y + 16
--     end
--   end
--   if UpdateBattleStructWait >= 0 then
--     UpdateBattleStructWait = UpdateBattleStructWait - 1
--   end
--   emu.frameadvance()
-- end

-- Process
-- Check if changed from not in battle to battle.
-- If so, read EMEMY_STRUCT_PTR and get ENEMY_STRUCT_ADDR
-- Read what different enemies are in group, and add to Set
-- Maybe make list as well?

local function calculateDrop(battle, rng_index)
  local rng = RNGMonitor:getRNG(rng_index)
  for i = 1, #battle.Enemies do
    local enemy = battle.Enemies[i]
    rng_index = rng_index + 1
    -- Because rng_index can be greater than RNGMonitor table size by up to 12
    -- For those instances we calculate the RNG manually
    -- This lets us calculate for full RNGMonitor table size
    -- We can't update RNGMonitor table with calculated values
    -- Because that would put us into an infinite loop
    rng = RNGMonitor:getRNG(rng_index) or RNGLib.nextRNG(rng)
    local drop_index_roll = RNGLib.getRNG2(rng)
    local drop_index = (drop_index_roll % 3) + 1
    if drop_index <= #enemy.Drops then
      local drop_data = enemy.Drops[drop_index]
      rng_index = rng_index + 1
      rng = RNGMonitor:getRNG(rng_index) or RNGLib.nextRNG(rng)
      local drop_chance_roll = RNGLib.getRNG2(rng)
      if drop_chance_roll % 100 < drop_data.chance then
        return drop_data
      end
    end
  end
  return nil
end

local function calculateDrops(battle, rng_index, iterations, drops)
  drops = drops or {}
  iterations = iterations or 10000
  rng_index = rng_index or 0
  for _ = 1, iterations do
    local drop = calculateDrop(battle, rng_index)
    if drop ~= nil then
      drops[rng_index] = { name = drop, rng = string.format("0x%x", RNGMonitor:getRNG(rng_index)) }
    end
    rng_index = rng_index + 1
    -- calculateDrop can advance RNG by up to 12 times, which can go outside table bounds
    -- adding 12 prevents out of bounds
    if rng_index >= RNGMonitor:getTableSize() then return drops end
  end
  return drops
end

return {
  calculateDrop = calculateDrop,
  calculateDrops = calculateDrops,
  getEnemyData = getEnemyData,
  getItemName = getItemName,
  readEnemyTable = readEnemyTable
}
