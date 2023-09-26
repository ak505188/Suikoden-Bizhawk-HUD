local StateMonitor = require "monitors.State_Monitor"
local ZoneInfo = require "lib.ZoneInfo"
local Location = require "lib.Enums.Location"
local EncounterTable = require "lib.EncounterTable"

local WorkerState = {}

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

  self.Location = StateMonitor.LOCATION.current
  self.AreaName = name
  self.EncounterTable = data.encounters
  self.Enemies = data.enemies
  self.EncounterRate = encounterRate
  self.EncounterTableSize = #data.encounters
  self.ChampVals = data.champVals
end

return WorkerState
