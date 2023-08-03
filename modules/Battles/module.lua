local Menu = require "modules.Battles.menu"
local Gamestate = require "lib.Enums.Gamestate"
local Location = require "lib.Enums.Location"
local RNG_Events = require "lib.Enums.RNG_Events"
local ZoneInfo = require "lib.ZoneInfo"
local EncounterTable = require "lib.EncounterTable"
local Utils = require "lib.Utils"

local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local Battles_Module = {
  Name = "Battles",
  Menu = Menu,
  Config = {
    EnemyDrawTableLength = 10
  },
  State = {},
}

function Battles_Module:draw(drawOpts)
  if self.State.Enemies == nil or self:getTable() == nil then
    return drawOpts
  end

  local enemyListOpts = {
    x = 0,
    y = 0,
    gap = 16,
    anchor = "bottomleft",
    reverse = true
  }
  Utils.drawTable(self:generateAreaEnemiesTable(), enemyListOpts);

  local battleListOpts = {
    x = drawOpts.x or 0,
    y = drawOpts.y or 0,
    gap = drawOpts.gap or 16,
    anchor = drawOpts.anchor or "topright"
  }

  local battleListTable = self:generateBattlesDrawTable()
  return Utils.drawTable(battleListTable, battleListOpts)
end

function Battles_Module:isUpdateRequired()
  if StateMonitor.LOCATION == Location.OTHER then
    return false
  end

  local stateChanged = false

  if StateMonitor.LOCATION.changed then
    -- print("Location changed")
    stateChanged = true
  elseif StateMonitor.WM_ZONE.changed then
    -- print("WM Zone changed")
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

function Battles_Module:updateState()
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

  self.State = {
    Location = StateMonitor.LOCATION.current,
    AreaName = name,
    EncounterTable = data.encounters,
    Enemies = data.enemies,
    EncounterRate = encounterRate,
    EncounterTableSize = #data.encounters,
    ChampVals = data.champVals,
  }
end

function Battles_Module:switchArea(areaName)
  local areaData = EncounterTable[areaName]
  local location = Location.WORLD_MAP
  if areaData.areaType == Gamestate.OVERWORLD then
    location = Location.OVERWORLD
  end

  self.State.Location = location
  self.State.AreaName = areaName
  self.State.EncounterTable = areaData.encounters
  self.State.Enemies = areaData.enemies
  self.State.EncounterRate = areaData.encounterRate or 8
  self.State.EncounterTableSize = #areaData.encounters
end

function Battles_Module:onChange()
  self:updateState()
end

function Battles_Module:run()
  local stateChanged = self:isUpdateRequired()

  if not next(self.State) then
    self:updateState()
    return
  end

  if stateChanged then
    self:updateState()
  end

  if self.State.Location == Location.OTHER then
    return
  end

  -- Make RNG Tables if they don't exist
  -- So init here
  if self.Tables == nil or RNGMonitor.Event == RNG_Events.START_RNG_CHANGED then
    self:init()
  -- TODO: Handle Start RNG Change
  elseif RNGMonitor.Event ~= RNG_Events.NO_CHANGE or stateChanged then
    self:updateTablePosition()
  end
end

------------------------------------------------------------------

function Battles_Module:getTable(location)
  if self.Tables == nil then
    return nil
  end
  location = location or self.State.Location
  return self.Tables[location]
end

function Battles_Module:getRNGIndex()
  return RNGMonitor.RNGIndex
end

function Battles_Module:findTablePosition(table, RNGIndex)
  table = table or self:getTable()
  if #table <= 0 then return end
  RNGIndex = RNGIndex or self:getRNGIndex()

  if RNGIndex < table[1].index or RNGIndex > table[#table].index then return 0 end

  -- Eventually want to do a binary or ternary search here
  -- For now, just going to iterate through the list
  local pos = 1

  -- Shortcut if RNGIndex >= current position index, which should be most common scenario
  if RNGIndex >= table[self.cur].index then
    pos = self.cur
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

function Battles_Module:updateTablePosition(RNGIndex)
  RNGIndex = RNGIndex or self:getRNGIndex()
  local pos = self:findTablePosition(nil, RNGIndex)
  if pos < 1 then return end
  if self.pos == self.cur then
    self.pos = pos
  end
  self.cur = pos
end

function Battles_Module:adjustPos(amount)
  local newPos = self.pos + amount
  if newPos < 1 then self.pos = 1
  elseif newPos > #self:getTable() then self.pos = #self:getTable()
  else self.pos = newPos end
end

function Battles_Module:getEncounter(tableIndex)
  tableIndex = tableIndex or self.cur
  local table = self:getTable()
  if table == nil or #table <= 0 then return end
  local possibleBattle = table[tableIndex]

  if possibleBattle.value and possibleBattle.value >= self.State.EncounterRate then return nil end
  if StateMonitor.CHAMPION_RUNE_EQUIPPED.current then
    local champVal = self.State.ChampVals[possibleBattle.battles[self.State.EncounterTableSize]]
    if StateMonitor.PARTY_LEVEL.current > champVal then return nil end
  end

  local group = self.State.EncounterTable[table[tableIndex].battles[self.State.EncounterTableSize]]

  local encounterData = {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }

  return encounterData
end

function Battles_Module:getValidEncounter(tableIndex)
  tableIndex = tableIndex or self.cur
  local table = self:getTable()
  if table == nil or #table <= 0 then return end

  local possibleBattle
  local validBattleFound = false

  repeat
    possibleBattle = table[tableIndex]
    if possibleBattle.value < self.State.EncounterRate then
      if self.State.IsChampion then
        local champVal = possibleBattle.battles[self.State.EncounterTableSize]
        if self.State.PartyLevel > champVal then
          validBattleFound = true
        end
      else
        validBattleFound = true
      end
    else
      tableIndex = tableIndex + 1
    end
  until validBattleFound or tableIndex > #table

  local group = self.State.EncounterTable[table[tableIndex].battles[self.State.EncounterTableSize]]

  return {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }, tableIndex
end

function Battles_Module:generateBattlesDrawTable()
  local cur = self.cur

  local i = 0
  local d = 0 -- Number of entries displayed
  local tableLength = #self:getTable()

  local drawTable = {}
  local areaNameStr = self.State.AreaName

  if StateMonitor.CHAMPION_RUNE_EQUIPPED.current then
    areaNameStr = string.format("%s PL:%d", areaNameStr, StateMonitor.PARTY_LEVEL.current)
  end

  table.insert(drawTable, areaNameStr)

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

function Battles_Module:generateAreaEnemiesTable()
  local enemiesTable = {}
  for index,enemy in ipairs(self.State.Enemies) do
    table.insert(enemiesTable, string.format("%d:%s", index, enemy))
  end
  return enemiesTable
end

function Battles_Module:init()
  self.Tables = {
    [Location.WORLD_MAP] = RNGMonitor:getRNGTable()[Location.WORLD_MAP],
    [Location.OVERWORLD] = RNGMonitor:getRNGTable()[Location.OVERWORLD],
  }
  self.pos = 1
  self.cur = 1
  self:updateState()
end

return Battles_Module
