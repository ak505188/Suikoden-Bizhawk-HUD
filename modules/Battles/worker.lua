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
  RNGIndex = 0,
  TablePosition = nil,
  Battles = {},
  Display = {},
}

function Worker:draw(options)
  if not self:shouldDraw() then
    return
  end

  local draw_data = self:genDrawData(options)

  Drawer:draw({ draw_data.Area }, Drawer.anchors.TOP_LEFT, nil, true)
  Drawer:draw(draw_data.Battles, Drawer.anchors.TOP_LEFT, nil, true)
  Drawer:draw(draw_data.Enemies, Drawer.anchors.BOTTOM_LEFT, true)
end

function Worker:shouldDraw()
  return self.StateHandler:getState().Enemies ~= nil and self:getTable() ~= nil
end

function Worker:getTable(location)
  location = location or self.StateHandler:getState().Location
  local tbl = RNGMonitor:getTable()[location] or {}
  return tbl
end

function Worker:findTablePosition(tbl, RNGIndex)
  tbl = tbl or self:getTable()
  if tbl == nil or #tbl <= 0 then return nil end

  RNGIndex = RNGIndex or RNGMonitor:getIndex()
  self.RNGIndex = RNGIndex

  if RNGIndex > tbl[#tbl].index then return nil end
  if RNGIndex < tbl[1].index then
    return 1
  end

  -- Eventually want to do a binary or ternary search here
  -- For now, just going to iterate through the list
  local pos = 1

  -- Shortcut if RNGIndex >= current position index, which should be most common scenario
  -- FIX: Sometimes get an error here.
  if tbl[self.TablePosition] ~= nil and RNGIndex >= tbl[self.TablePosition].index then
    pos = self.TablePosition
  end
  repeat
    -- This only works because we're going in order.
    -- If doing more optimal search we would need to
    -- compare both current and next entry
    if RNGIndex < tbl[pos].index then
      return pos
    end
    pos = pos + 1
  until pos > #tbl
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

function Worker:isValidEncounter(battle)
  local game_state = self.StateHandler:getState()

  -- FIX: I sometimes error here when loading saves
  if battle.encounter_roll >= game_state.EncounterRate then
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
  local rng_table = self:getTable()
  if rng_table == nil or #rng_table <= 0 then return end

  local possibleBattle
  local validBattleFound = false

  repeat
    possibleBattle = rng_table[tableIndex]
    if possibleBattle == nil then return nil, tableIndex end
    validBattleFound = self:isValidEncounter(possibleBattle)

    if not validBattleFound then
      tableIndex = tableIndex + 1
    end
    if tableIndex > #rng_table then return nil, tableIndex end
  until validBattleFound

  local encounter_table = self.StateHandler:getState().EncounterTable
  local group = encounter_table[rng_table[tableIndex].battles[#encounter_table]]

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
    if self:getTable()[current_table_position] == nil then return drawTable end
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

  if startRNGChanged then
    self:init()
  elseif RNGIndexChanged or stateChanged then
    self:updateTablePosition()
  end
end

return Worker
