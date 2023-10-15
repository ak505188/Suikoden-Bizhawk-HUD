local Location = require "lib.Enums.Location"
local Drawer = require "controllers.drawer"

local StateHandler = require "modules.Battles.StateHandler"

local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local Worker = {
  Name = "Battles",
  Config = {
    EnemyDrawTableLength = 10
  },
  StateHandler = StateHandler,
  TablePosition = nil,
}

function Worker:draw(options)
  if not self:shouldDraw() then
    return
  end

  -- local battles = self.Drawdata.Battles
  -- if options and options.table_position then
  --   battles = self:genBattlesDrawTable(options)
  -- end
  local draw_data = self:genDrawData(options)

  Drawer:draw(draw_data.Enemies, Drawer.anchors.BOTTOM_LEFT, true)
  Drawer:draw({ draw_data.Area }, Drawer.anchors.TOP_LEFT, nil, true)
  Drawer:draw(draw_data.Battles, Drawer.anchors.TOP_LEFT)
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

  if RNGIndex > table[#table].index then return nil end
  if RNGIndex < table[1].index then
    return 1
  end

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

function Worker:isValidEncounter(tableIndex)
  tableIndex = tableIndex or self.TablePosition
  local game_state = self.StateHandler:getState()
  local battle = self:getTable()[tableIndex]

  if battle.value >= game_state.EncounterRate then
    return false
  end

  if not game_state.IsChampion then
    return true
  end

  local encounter_table_index = battle.battles[#game_state.EncounterTable]
  local battle_champion_lvl = game_state.ChampVals[encounter_table_index]
  return game_state.PartyLevel <= battle_champion_lvl
end

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
    if tableIndex > #table then return nil, tableIndex end
  until validBattleFound

  local encounter_table = self.StateHandler:getState().EncounterTable
  local group = encounter_table[table[tableIndex].battles[#encounter_table]]

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

  local battle = nil
  local current_table_position = table_position or self.TablePosition

  local d = 0 -- Number of entries displayed
  local tableLength = #battle_table

  local drawTable = {}

  repeat
    battle, current_table_position = self:getValidEncounter(current_table_position)
    if battle then
      local run = battle.run and "R" or "F"
      table.insert(drawTable, string.format("%d: %s %s", battle.index, run, battle.group))
      d = d + 1
    end
    current_table_position = current_table_position + 1
  until d >= self.Config.EnemyDrawTableLength or current_table_position > tableLength

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
  self.CurrentStartingRNG = RNGMonitor.StartingRNG
  self.CurrentRNGIndex = RNGMonitor.RNGIndex
  self.Tables = {
    [Location.WORLD_MAP] = RNGMonitor:getTable()[Location.WORLD_MAP],
    [Location.OVERWORLD] = RNGMonitor:getTable()[Location.OVERWORLD],
  }
  self.StateHandler:updateState()
  self.TablePosition = 1
  if self:getTable() then self:findTablePosition() end
end

function Worker:onChange()
  self.StateHandler:updateState()
end

function Worker:run()
  local stateChanged = self.StateHandler:isUpdateRequired()

  -- Because this doesn't run when it's not the current module,
  -- can't use RNGMonitor events reliably. Need to run our own checks
  local startRNGChanged = self.CurrentStartingRNG ~= RNGMonitor.StartingRNG
  local RNGIndexChanged = self.CurrentRNGIndex ~= RNGMonitor.RNGIndex

  self.CurrentStartingRNG = RNGMonitor.StartingRNG
  self.CurrentRNGIndex = RNGMonitor.RNGIndex

  if stateChanged then
    self.StateHandler:updateState()
  end

  if not self.StateHandler:getState().Location then
    self.StateHandler:updateState()
    return
  end

  if self.StateHandler:getState().Location == Location.OTHER then
    return
  end


  if self.Tables == nil or startRNGChanged then
    self:init()
  -- TODO: Handle Start RNG Change
  elseif RNGIndexChanged or stateChanged then
    self:updateTablePosition()
  end



  --[[
  -- Make RNG Tables if they don't exist
  -- So init here
  if self.Tables == nil or RNGMonitor.Event == RNG_Events.START_RNG_CHANGED then
    self:init()
  -- TODO: Handle Start RNG Change
  elseif RNGMonitor.Event ~= RNG_Events.NO_CHANGE or stateChanged then
    Utils.printDebug('Battle Worker RNG Event', RNGMonitor.Event, 1000)
    self:updateTablePosition()
  end
  ]]--
end

return Worker
