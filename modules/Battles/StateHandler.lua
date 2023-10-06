local StateMonitor = require "monitors.State_Monitor"
local ZoneInfo = require "lib.ZoneInfo"
local Location = require "lib.Enums.Location"
local EncounterTable = require "lib.EncounterTable"
local Utils = require "lib.Utils"
local EncounterLib = require "lib.Encounter"
local AreasWithRandomBattles = require "lib.Enums.Areas.Areas_Random"

local WorkerState = {
  real_state = {},
  custom_state = {},
  -- has_battles = {
  --   random = false,
  --   forced = false
  -- },
  use_custom = false
}

local defaultCustomStateAreaName = AreasWithRandomBattles.CAVE_OF_THE_PAST
local defaultCustomStateAreaData = EncounterTable[defaultCustomStateAreaName]

local defaultCustomState = {
  Location = Location.OVERWORLD,
  AreaName = AreasWithRandomBattles.CAVE_OF_THE_PAST,
  EncounterTable = defaultCustomStateAreaData.encounters,
  Enemies = defaultCustomStateAreaData.enemies,
  EncounterRate = defaultCustomStateAreaData.encounterRate,
  EncounterTableSize = #defaultCustomStateAreaData.encounters,
  ChampVals = defaultCustomStateAreaData.champVals,
  PartyLevel = 1,
  IsChampion = false,
}

-- function WorkerState:hasRandomBattles() return self.has_battles.random end
-- function WorkerState:hasForcedBattles() return self.has_battles.forced end

function WorkerState:getState()
  if self.use_custom then return self.custom_state end
  return self.real_state
end

function WorkerState:getRealState()
  return self.real_state
end

function WorkerState:getCustomState()
  return self.custom_state
end

function WorkerState:updateCustomState(new_custom_state)
  self.custom_state = new_custom_state
end

function WorkerState:updateCustomStateArea(area_name)
  local new_custom_state = self:getCustomState()
  local area_data = EncounterTable[area_name]

  new_custom_state.LOCATION = EncounterLib.locationIntToKey(area_data.areaType)
  new_custom_state.AreaName = area_name
  new_custom_state.EncounterTable = area_data.encounters
  new_custom_state.Enemies = area_data.enemies
  new_custom_state.EncounterRate = area_data.encounterRate or 8
  new_custom_state.EncounterTableSize = #area_data.encounters
  new_custom_state.ChampVals = area_data.champVals

  self:updateCustomState(new_custom_state)
end

function WorkerState:useRealState()
  self.use_custom = false
end

function WorkerState:initCustomState()
  if next(self.custom_state) == nil then
    self.custom_state = Utils.combineTables(defaultCustomState, self.real_state)
  end
end

function WorkerState:useCustomState()
  self:initCustomState()
  self.use_custom = true
end

function WorkerState:toggleCustomState()
  self.use_custom = not self.use_custom
  if self.use_custom then self:useCustomState()
  else
    self:useRealState()
  end
end

function WorkerState:isUpdateRequired()
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

function WorkerState:updateState()
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

  self.real_state = {
    Location = StateMonitor.LOCATION.current,
    AreaName = name,
    EncounterTable = data.encounters,
    Enemies = data.enemies,
    EncounterRate = encounterRate,
    EncounterTableSize = #data.encounters,
    ChampVals = data.champVals,
    PartyLevel = StateMonitor.PARTY_LEVEL.current,
    IsChampion = StateMonitor.CHAMPION_RUNE_EQUIPPED.current,
  }
end

return WorkerState
