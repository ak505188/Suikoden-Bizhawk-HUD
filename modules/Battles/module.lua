local Menu = require "modules.Battles.menu"
local Lib = require "lib.Encounter"
local Gamestates = require "lib.Gamestates"

local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local Battles_Module = {
  Name = "Battles",
  Menu = Menu,
}

function Battles_Module:run()
  local stateChanged = stateChanged = self:updateState()

  -- What does this line do?
  if not next(self.State) then return end

  if self.RNG_HUD.State.RNG_CHANGED or stateChanged then
    self:updateTablePosition()
  end

end

function Battles_Module:draw(opts) return opts end

return Battles_Module


function BattlesHUD:isUpdateRequired()
  local gameState = StateMonitor.IG_CURRENT_GAMESTATE.current
  local prevGameState = StateMonitor.IG_PREVIOUS_GAMESTATE.current

  local location = Lib.onWorldMapOrOverworld(gameState, prevGameState)

  if location ~= Gamestates.WORLD_MAP and location ~= Gamestates.OVERWORLD then
    return false
  end

  local wm_zone = StateMonitor.WM_ZONE.current
  local area_zone = StateMonitor.AREA_ZONE.current
  local inGameEncounterRate = StateMonitor.ENCOUNTER_RATE.current

  -- Get Champion Rune Info
  local IsChampion = StateMonitor.CHAMPION_RUNE_EQUIPPED.current
  local PartyLevel = StateMonitor.PARTY_LEVEL.current

  local stateChanged = false

  -- print("Location:", location, self.State.Location)
  -- print("WM Zone:", wm_zone, self.State.WM_Zone)
  -- print("Area Zone:", area_zone, self.State.Area_Zone)
  -- print("Encounter Rate:", inGameEncounterRate, self.State.EncounterRate)

  if location ~= self.State.Location then
    -- print("Location changed")
    stateChanged = true
  elseif wm_zone ~= self.State.WM_Zone then
    -- print("WM Zone changed")
    stateChanged = true
  elseif area_zone ~= self.State.Area_Zone then
    -- print("Area Zone changed")
    stateChanged = true
  elseif inGameEncounterRate ~= self.State.EncounterRate then
    -- print("EncounterRate changed")
    stateChanged = true
  elseif IsChampion then
    if not self.State.IsChampion then
      stateChanged = true
    elseif PartyLevel ~= self.State.PartyLevel then
      stateChanged = true
    end
  end

  -- Check if change, if not do nothing.
  if not stateChanged then
    return false
  end

  local encounterRate
  local name
  local data

  if location == Gamestates.WORLD_MAP then
    name = ZoneInfo[wm_zone].name
    data = EncounterTable[name]
    if not data then return false end
    encounterRate = 8
  elseif location == Gamestates.OVERWORLD then
    name = ZoneInfo[wm_zone][area_zone]
    data = EncounterTable[name]
    if not data then return false end
    encounterRate = math.min(inGameEncounterRate, data.encounterRate)
  end


  self.State = {
    Location = location,
    Name = name,
    EncounterTable = data.encounters,
    Enemies = data.enemies,
    EncounterRate = encounterRate,
    EncounterTableSize = #data.encounters,
    ChampVals = data.champVals,
    WM_Zone = wm_zone,
    Area_Zone = area_zone,
    IsChampion = IsChampion,
    PartyLevel = PartyLevel
  }

  return true
end

function BattlesHUD:switchArea(areaName)
  local areaData = EncounterTable[areaName]

  self.State.Location = areaData.areaType
  self.State.Name = areaName
  self.State.EncounterTable = areaData.encounters
  self.State.Enemies = areaData.enemies
  self.State.EncounterRate = areaData.encounterRate or 8
  self.State.EncounterTableSize = #areaData.encounters
end
