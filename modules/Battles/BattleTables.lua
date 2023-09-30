local Location = require "lib.Enums.Location"

local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local BattleTables = {
  position = nil,
}

function BattleTables:getTable(location)
  if self.Tables == nil or location == nil then
    return nil
  end
  return self.Tables[location]
end

-- table, rngindex, tableposition
function BattleTables:findTablePosition(table, RNGIndex)
  table = table or self:getTable()
  if table == nil or #table <= 0 then return nil end
  RNGIndex = RNGIndex or RNGMonitor:getIndex()

  if RNGIndex < table[1].index or RNGIndex > table[#table].index then return 0 end

  -- Eventually want to do a binary or ternary search here
  -- For now, just going to iterate through the list
  local pos = 1

  -- Shortcut if RNGIndex >= current position index, which should be most common scenario
  if RNGIndex >= table[self.TablePosition].index then
    pos = self.TablePosition
  end
  repeat
    -- This only works because we're going in order.
    -- If doing more optimal search we would need to
    -- compare both current and next entry
    if RNGIndex < table[pos].index then return pos end
    pos = pos + 1
  until pos > #table
  return nil
end

-- table, rngindex, tableposition
function BattleTables:updateTablePosition(RNGIndex)
  local pos = self:findTablePosition(nil, RNGIndex)
  if pos == nil then return end
  self.TablePosition = pos
end

-- tableposition, location
function BattleTables:jumpToBattle(pos)
  local battle = self:getTable()[pos]
  if not battle then return end

  local newRNGIndex = battle.index - 1
  if newRNGIndex < 0 then newRNGIndex = 0 end

  self.TablePosition = pos
  RNGMonitor:goToIndex(newRNGIndex)
end

function BattleTables:getEncounter(table_pos)
  table_pos = table_pos or self.TablePosition
  local table = self:getTable()
  if table == nil or #table <= 0 then return end
  local possibleBattle = table[table_pos]

  if possibleBattle.value and possibleBattle.value >= self.StateHandler:getState().EncounterRate then return nil end
  if StateMonitor.CHAMPION_RUNE_EQUIPPED.current then
    local champVal = self.StateHandler:getState().ChampVals[possibleBattle.battles[self.StateHandler:getState().EncounterTableSize]]
    if StateMonitor.PARTY_LEVEL.current > champVal then return nil end
  end

  local group = self.StateHandler:getState().EncounterTable[table[table_pos].battles[self.StateHandler:getState().EncounterTableSize]]

  local encounterData = {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }

  return encounterData
end

function BattleTables:isValidEncounter(tableIndex)
  tableIndex = tableIndex or self.TablePosition
  local battle = self:getTable()[tableIndex]

  if battle.value >= self.StateHandler:getState().EncounterRate then
    return false
  end

  if not self.StateHandler:getState().IsChampion then
    return true
  end

  local battleChampVal = battle.battles[self.StateHandler:getState().EncounterTableSize]
  return self.StateHandler:getState().PartyLevel <= battleChampVal
end

-- This should probably be split into 2 functions
-- and have clearer return values and name
function BattleTables:getValidEncounter(tableIndex)
  tableIndex = tableIndex or self.TablePosition
  local table = self:getTable()
  if table == nil or #table <= 0 then return end

  local possibleBattle
  local validBattleFound = false

  repeat
    possibleBattle = table[tableIndex]
    validBattleFound = self:isValidEncounter(tableIndex)

    if not validBattleFound then
      tableIndex = tableIndex + 1
    end
  until validBattleFound or tableIndex > #table

  local group = self.StateHandler:getState().EncounterTable[table[tableIndex].battles[self.StateHandler:getState().EncounterTableSize]]

  return {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }, tableIndex
end

function BattleTables:init()
  self.Tables = {
    [Location.WORLD_MAP] = RNGMonitor:getTable()[Location.WORLD_MAP],
    [Location.OVERWORLD] = RNGMonitor:getTable()[Location.OVERWORLD],
  }
  self.TablePosition = 1
end

return BattleTables
