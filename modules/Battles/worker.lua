local Gamestate = require "lib.Enums.Gamestate"
local Location = require "lib.Enums.Location"
local RNG_Events = require "lib.Enums.RNG_Events"
local ZoneInfo = require "lib.ZoneInfo"
local EncounterTable = require "lib.EncounterTable"
local Utils = require "lib.Utils"

local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local Worker = {
  Name = "Battles",
  Config = {
    EnemyDrawTableLength = 10
  },
  Gamestate = {},
  Drawdata = {
    Battles = {},
    Enemies = {},
    Area = {},
  },
  TablePosition = 1,
}

function Worker:draw(drawOpts)
  if not self:shouldDraw() then
    return drawOpts
  end

  local enemyListOpts = {
    x = 0,
    y = 0,
    gap = 16,
    anchor = "bottomleft",
    reverse = true
  }
  Utils.drawTable(self.Drawdata.Enemies, enemyListOpts);

  local battleListOpts = {
    x = drawOpts.x or 0,
    y = drawOpts.y or 0,
    gap = drawOpts.gap or 16,
    anchor = drawOpts.anchor or "topright"
  }

  -- This should be cheaper than combining the tables or inserting AreaStr to the front
  gui.text(battleListOpts.x, battleListOpts.y, self.Drawdata.Area, nil, battleListOpts.anchor)
  battleListOpts.y = battleListOpts.y + 16

  return Utils.drawTable(self.Drawdata.Battles, battleListOpts)
end

function Worker:shouldDraw()
  return self.Gamestate.Enemies ~= nil and self:getTable() ~= nil
end

function Worker:isUpdateRequired()
  if StateMonitor.LOCATION == Location.OTHER then
    return false
  end

  local stateChanged = false

  if StateMonitor.LOCATION.changed then
    stateChanged = true
  elseif StateMonitor.WM_ZONE.changed then
    stateChanged = true
  elseif StateMonitor.AREA_ZONE.changed then
    stateChanged = true
  elseif StateMonitor.ENCOUNTER_RATE.changed then
    stateChanged = true
  elseif StateMonitor.CHAMPION_RUNE_EQUIPPED.changed then
    stateChanged = true
  elseif StateMonitor.CHAMPION_RUNE_EQUIPPED and StateMonitor.PARTY_LEVEL.changed then
    stateChanged = true
  end

  if not stateChanged then
    return false
  end

  return true
end

function Worker:updateState()
  if StateMonitor.LOCATION.current == Location.OTHER then
    return
  end

  local encounterRate
  local name
  local data

  if StateMonitor.LOCATION.current == Location.WORLD_MAP then
    name = ZoneInfo[StateMonitor.WM_ZONE.current].name
    data = EncounterTable[name]
    if not data then return false end
    encounterRate = 8
  elseif StateMonitor.LOCATION.current == Location.OVERWORLD then
    name = ZoneInfo[StateMonitor.WM_ZONE.current][StateMonitor.AREA_ZONE.current]
    data = EncounterTable[name]
    if not data then return false end
    encounterRate = math.min(StateMonitor.ENCOUNTER_RATE.current, data.encounterRate)
  end

  self.Gamestate = {
    Location = StateMonitor.LOCATION.current,
    AreaName = name,
    EncounterTable = data.encounters,
    Enemies = data.enemies,
    EncounterRate = encounterRate,
    EncounterTableSize = #data.encounters,
    ChampVals = data.champVals,
  }
end

function Worker:switchArea(areaName)
  local areaData = EncounterTable[areaName]
  local location = Location.WORLD_MAP
  if areaData.areaType == Gamestate.OVERWORLD then
    location = Location.OVERWORLD
  end

  self.Gamestate.Location = location
  self.Gamestate.AreaName = areaName
  self.Gamestate.EncounterTable = areaData.encounters
  self.Gamestate.Enemies = areaData.enemies
  self.Gamestate.EncounterRate = areaData.encounterRate or 8
  self.Gamestate.EncounterTableSize = #areaData.encounters
end

function Worker:getTable(location)
  if self.Tables == nil then
    return nil
  end
  location = location or self.Gamestate.Location
  return self.Tables[location]
end

function Worker:findTablePosition(table, RNGIndex)
  table = table or self:getTable()
  if #table <= 0 then return end
  RNGIndex = RNGIndex or RNGMonitor:getRNGIndex()

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
  return -1
end

function Worker:updateTablePosition(RNGIndex)
  RNGIndex = RNGIndex or RNGMonitor:getRNGIndex()
  local pos = self:findTablePosition(nil, RNGIndex)
  if pos < 1 then return end
  self.TablePosition = pos
end

--[[
function Worker:adjustPos(amount)
  local newPos = self.Tablestate.cursor + amount
  if newPos < 1 then self.Tablestate.cursor = 1
  elseif newPos > #self:getTable() then self.Tablestate.cursor = #self:getTable()
  else self.Tablestate.cursor = newPos end
end

function Worker:jumpToBattle(pos)
  pos = pos or self.Tablestate.cursor
  local battle

  battle, pos = self:getValidEncounter(pos)
  if not battle then return end

  local newRNGIndex = battle.index - 1
  if newRNGIndex < 0 then newRNGIndex = 0 end

  self.TablePosition = pos
  self.Tablestate.cursor = pos
  RNGMonitor:goToRNGIndex(newRNGIndex)
end
]]--

function Worker:getEncounter(tableIndex)
  tableIndex = tableIndex or self.TablePosition
  local table = self:getTable()
  if table == nil or #table <= 0 then return end
  local possibleBattle = table[tableIndex]

  if possibleBattle.value and possibleBattle.value >= self.Gamestate.EncounterRate then return nil end
  if StateMonitor.CHAMPION_RUNE_EQUIPPED.current then
    local champVal = self.Gamestate.ChampVals[possibleBattle.battles[self.Gamestate.EncounterTableSize]]
    if StateMonitor.PARTY_LEVEL.current > champVal then return nil end
  end

  local group = self.Gamestate.EncounterTable[table[tableIndex].battles[self.Gamestate.EncounterTableSize]]

  local encounterData = {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }

  return encounterData
end

function Worker:getValidEncounter(tableIndex)
  tableIndex = tableIndex or self.TablePosition
  local table = self:getTable()
  if table == nil or #table <= 0 then return end

  local possibleBattle
  local validBattleFound = false

  repeat
    possibleBattle = table[tableIndex]
    if possibleBattle.value < self.Gamestate.EncounterRate then
      if self.Gamestate.IsChampion then
        local champVal = possibleBattle.battles[self.Gamestate.EncounterTableSize]
        if self.Gamestate.PartyLevel > champVal then
          validBattleFound = true
        end
      else
        validBattleFound = true
      end
    else
      tableIndex = tableIndex + 1
    end
  until validBattleFound or tableIndex > #table

  local group = self.Gamestate.EncounterTable[table[tableIndex].battles[self.Gamestate.EncounterTableSize]]

  return {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }, tableIndex
end

function Worker:genAreaStr()
  local areaNameStr = self.Gamestate.AreaName

  if StateMonitor.CHAMPION_RUNE_EQUIPPED.current then
    areaNameStr = string.format("%s PL:%d", areaNameStr, StateMonitor.PARTY_LEVEL.current)
  end

  return areaNameStr
end

function Worker:genBattlesTable()
  local cur = self.TablePosition

  local i = 0
  local d = 0 -- Number of entries displayed
  local tableLength = #self:getTable()

  local drawTable = {}

  repeat
    local battle = self:getEncounter(cur + i)
    if battle then
      local run = "F"
      if battle.run then run = "R" end
      table.insert(drawTable, string.format("%d: %s %s", battle.index, run, battle.group))
      d = d + 1
    end
    i = i + 1
  until d >= self.Config.EnemyDrawTableLength or (cur + i) > tableLength

  return drawTable
end

function Worker:genEnemiesTable()
  local enemiesTable = {}
  for index,enemy in ipairs(self.Gamestate.Enemies) do
    table.insert(enemiesTable, string.format("%d:%s", index, enemy))
  end
  return enemiesTable
end

function Worker:updateDrawdata()
  self.Drawdata.Battles = self:genBattlesTable()
  self.Drawdata.Enemies = self:genEnemiesTable()
  self.Drawdata.Area = self:genAreaStr()
end

function Worker:init()
  self.Tables = {
    [Location.WORLD_MAP] = RNGMonitor:getRNGTable()[Location.WORLD_MAP],
    [Location.OVERWORLD] = RNGMonitor:getRNGTable()[Location.OVERWORLD],
  }
  self.TablePosition = 1
  self:updateState()
  self:updateDrawdata()
end

function Worker:onChange()
  self:updateState()
  self:updateDrawdata()
end

function Worker:run()
  local stateChanged = self:isUpdateRequired()

  if not next(self.Gamestate) then
    self:updateState()
    return
  end

  if stateChanged then
    self:updateState()
    self:updateDrawdata()
  end

  if self.Gamestate.Location == Location.OTHER then
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
