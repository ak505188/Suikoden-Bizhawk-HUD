local StateMonitor = require "monitors.State_Monitor"
local ZoneInfo = require "lib.ZoneInfo"
local Location = require "lib.Enums.Location"
local EncounterTable = require "lib.EncounterTable"
local Utils = require "lib.Utils"

local WorkerState = {
  real_state = {},
  custom_state = {},
  -- has_battles = {
  --   random = false,
  --   forced = false
  -- },
  use_custom = false
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

function WorkerState:updateCustomState() end

function WorkerState:useRealState()
  self.use_custom = false
  self.getState = self.real_state
end

function WorkerState:useCustomState()
  self.use_custom = true
  if next(self.custom_state) == nil then
    self.custom_state = Utils.cloneTable(self.real_state)
  end
  self.getState = self.custom_state
end

function WorkerState:toggleCustomState()
  self.use_custom = not self.use_custom
  if self.use_custom then
    self.getState = self.custom_state
  else
    self.getState = self.real_state
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
    ChampVals = data.champVals
  }
end

return WorkerState
