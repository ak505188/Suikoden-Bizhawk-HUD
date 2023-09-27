local Location = require "lib.Enums.Location"
local RNG_Events = require "lib.Enums.RNG_Events"
local Drawer = require "controllers.drawer"
local Utils = require "lib.Utils"

local StateHandler = require "modules.Battles.StateHandler"

local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local Worker = {
  Name = "Battles",
  Config = {
    EnemyDrawTableLength = 10
  },
  StateHandler = StateHandler,
  Drawdata = {
    Battles = {},
    Enemies = {},
    Area = {},
  },
  TablePosition = nil,
}

function Worker:draw(options)
  if not self:shouldDraw() then
    return
  end

  local battles = self.Drawdata.Battles
  if options and options.table_position then
    battles = self:genBattlesDrawTable(options)
  end

  Drawer:draw(self.Drawdata.Enemies, Drawer.anchors.BOTTOM_LEFT, true)
  Drawer:draw({ self.Drawdata.Area }, Drawer.anchors.TOP_LEFT, nil, true)
  Drawer:draw(battles, Drawer.anchors.TOP_LEFT)
end

function Worker:shouldDraw()
  return self.StateHandler:getState().Enemies ~= nil and self:getTable() ~= nil
end

function Worker:getTable(location)
  if self.Tables == nil then
    return nil
  end
  location = location or self.StateHandler:getState().Location
  local table = self.Tables[location]
  return table
end

function Worker:findTablePosition(table, RNGIndex)
  table = table or self:getTable()
  if table == nil or #table <= 0 then return nil end
  RNGIndex = RNGIndex or RNGMonitor:getIndex()

  if RNGIndex < table[1].index or RNGIndex > table[#table].index then return nil end

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

function Worker:updateTablePosition(RNGIndex)
  RNGIndex = RNGIndex or RNGMonitor:getIndex()
  local pos = self:findTablePosition(nil, RNGIndex)
  if pos == nil then return end
  self.TablePosition = pos
end

function Worker:jumpToBattle(pos)
  local battle = self:getTable()[pos]
  if not battle then return end

  local newRNGIndex = battle.index - 1
  if newRNGIndex < 0 then newRNGIndex = 0 end

  self.TablePosition = pos
  RNGMonitor:goToIndex(newRNGIndex)
end

function Worker:getEncounter(tableIndex)
  tableIndex = tableIndex or self.TablePosition
  local table = self:getTable()
  if table == nil or #table <= 0 then return end
  local possibleBattle = table[tableIndex]

  if possibleBattle.value and possibleBattle.value >= self.StateHandler:getState().EncounterRate then return nil end
  if StateMonitor.CHAMPION_RUNE_EQUIPPED.current then
    local champVal = self.StateHandler:getState().ChampVals[possibleBattle.battles[self.StateHandler:getState().EncounterTableSize]]
    if StateMonitor.PARTY_LEVEL.current > champVal then return nil end
  end

  local group = self.StateHandler:getState().EncounterTable[table[tableIndex].battles[self.StateHandler:getState().EncounterTableSize]]

  local encounterData = {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }

  return encounterData
end

function Worker:isValidEncounter(tableIndex)
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
function Worker:getValidEncounter(tableIndex)
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

function Worker:genAreaStr()
  local areaNameStr = self.StateHandler:getState().AreaName

  if StateMonitor.CHAMPION_RUNE_EQUIPPED.current then
    areaNameStr = string.format("%s PL:%d", areaNameStr, StateMonitor.PARTY_LEVEL.current)
  end

  return areaNameStr
end

function Worker:genBattlesDrawTable(options, battle_table)
  battle_table = battle_table or self:getTable()
  if battle_table == nil then
    return {}
  end

  local table_position, cursor
  if options then
    table_position = options.table_position
    cursor = options.cursor
  end

  local current_table_position = table_position or self.TablePosition

  local i = 0
  local d = 0 -- Number of entries displayed
  local tableLength = #battle_table

  local drawTable = {}

  repeat
    local battle = self:getEncounter(current_table_position + i)
    if battle then
      local run = "F"
      if battle.run then run = "R" end
      table.insert(drawTable, string.format("%d: %s %s", battle.index, run, battle.group))
      d = d + 1
    end
    i = i + 1
  until d >= self.Config.EnemyDrawTableLength or (current_table_position + i) > tableLength

  if cursor and cursor < tableLength then
    drawTable[cursor] = string.format("> %s", drawTable[cursor])
  end

  return drawTable
end

function Worker:genEnemiesDrawTable()
  local enemiesTable = {}
  for index,enemy in ipairs(self.StateHandler:getState().Enemies) do
    table.insert(enemiesTable, string.format("%d:%s", index, enemy))
  end
  return enemiesTable
end

-- Only used internally since it modifies state
function Worker:updateDrawdata()
  if self:getTable() == nil then return end
  self.Drawdata.Battles = self:genBattlesDrawTable()
  self.Drawdata.Enemies = self:genEnemiesDrawTable()
  self.Drawdata.Area = self:genAreaStr()
end

function Worker:genDrawData(options)
  local Battles = self:genBattlesDrawTable(options)
  local Enemies = self:genEnemiesDrawTable()
  local Area = self:genAreaStr()
  return {
    Battles = Battles,
    Enemies = Enemies,
    Area = Area
  }
end

function Worker:init()
  self.Tables = {
    [Location.WORLD_MAP] = RNGMonitor:getTable()[Location.WORLD_MAP],
    [Location.OVERWORLD] = RNGMonitor:getTable()[Location.OVERWORLD],
  }
  self.StateHandler:updateState()
  self.TablePosition = 1
  self:updateDrawdata()
end

function Worker:onChange()
  self.StateHandler:updateState()
  self:updateDrawdata()
end

function Worker:run()
  local stateChanged = self.StateHandler:isUpdateRequired()

  if not self.StateHandler:getState().Location then
    self.StateHandler:updateState()
    return
  end

  if stateChanged then
    self.StateHandler:updateState()
    self:updateDrawdata()
  end

  if self.StateHandler:getState().Location == Location.OTHER then
    return
  end

  -- Make RNG Tables if they don't exist
  -- So init here
  if self.Tables == nil or RNGMonitor.Event == RNG_Events.START_RNG_CHANGED then
    self:init()
  -- TODO: Handle Start RNG Change
  elseif RNGMonitor.Event ~= RNG_Events.NO_CHANGE or stateChanged then
    self:updateTablePosition()
    self:updateDrawdata()
  end
end

return Worker
