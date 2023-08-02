local Menu = require "modules.Battles.menu"
local Lib = require "lib.Encounter"
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
  State = {},
}

function Battles_Module:draw(drawOpts)
  local opts = {
    x = drawOpts.x or 0,
    y = drawOpts.y or 0,
    gap = drawOpts.gap or 16,
    anchor = drawOpts.anchor or "topright"
  }
  local newDrawOpts = Utils.drawTable({
    "Battle Module Draw"
  }, opts)
  return newDrawOpts
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
    Name = name,
    EncounterTable = data.encounters,
    Enemies = data.enemies,
    EncounterRate = encounterRate,
    EncounterTableSize = #data.encounters,
    ChampVals = data.champVals,
  }

  return true
end

function Battles_Module:switchArea(areaName)
  local areaData = EncounterTable[areaName]
  local location = Location.WORLD_MAP
  if areaData.areaType == Gamestate.OVERWORLD then
    location = Location.OVERWORLD
  end

  self.State.Location = location
  self.State.Name = areaName
  self.State.EncounterTable = areaData.encounters
  self.State.Enemies = areaData.enemies
  self.State.EncounterRate = areaData.encounterRate or 8
  self.State.EncounterTableSize = #areaData.encounters
end

function Battles_Module:run()
  local stateChanged = self:isUpdateRequired()

  if not next(self.State) then
    Utils.printDebug("Pre Battle Module State", self.State)
    self:updateState()
    Utils.printDebug("Battle Module State", self.State)
    return
  end

  if RNGMonitor.Event ~= RNG_Events.NO_CHANGE or stateChanged then
    self:updateTablePosition()
  end
end

return Battles_Module
