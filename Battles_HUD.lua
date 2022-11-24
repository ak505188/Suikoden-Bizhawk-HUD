local EncounterTable = require "EncounterTable"
local EncounterLib = require "EncounterLib"
local PartyLib = require "PartyLib"
local ZoneInfo = require "ZoneInfo"
local Address = require "Address"
local Config = require "Config"

local REFRESH_RATE = Config.Battle_HUD.REFRESH_RATE
local GUI_GAP = Config.Battle_HUD.GUI_GAP
local GUI_X = Config.Battle_HUD.GUI_X
local GUI_Y = Config.Battle_HUD.GUI_Y
local NUM_TO_DISPLAY = Config.Battle_HUD.NUM_TO_DISPLAY

local Gamestates = {
  ["TITLE"] = 0,
  ["WORLD_MAP"] = 1,
  ["OVERWORLD"] = 2,
  ["BATTLE"] = 3,
  ["EVENT"] = 4,
  ["GAME_OVER"] = 99,
}

local BattlesHUD = {
  State = {},
  RefreshCounter = 0,
  Locked = false,
  AreaMenuOpen = false,
}

function BattlesHUD:toggleLock()
  self.Locked = not self.Locked
end

--- @param state boolean
function BattlesHUD:setLock(state)
  self.Locked = state
end

function BattlesHUD:jumpToBattle(pos)
  pos = pos or self.pos
  local battle

  battle, pos = self:getValidEncounter(pos)
  if not battle then return end

  local newRNGIndex = battle.index - 1
  if newRNGIndex < 0 then newRNGIndex = 0 end

  self.cur = pos
  self.pos = pos
  self.RNG_HUD:goToRNGIndex(newRNGIndex)
end

-- Returns whether or not state changed
function BattlesHUD:updateState()
  if self.Locked then return end

  local location = EncounterLib.onWorldMapOrOverworld()

  if location ~= Gamestates.WORLD_MAP and location ~= Gamestates.OVERWORLD then
    return false
  end

  local wm_zone = memory.read_u8(Address.WM_ZONE)
  local area_zone = memory.read_u8(Address.AREA_ZONE)
  local inGameEncounterRate = memory.read_u8(Address.ENCOUNTER_RATE)

  -- Get Champion Rune Info
  local IsChampion = PartyLib.isChampionsRuneEquipped()
  local PartyLevel = PartyLib.getPartyLVL()

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


function BattlesHUD:getTable(location)
  location = location or self.State.Location
  local locationKey = EncounterLib.locationIntToKey(location)
  return self.Tables[locationKey]
end

function BattlesHUD:getRNGIndex()
  return self.RNG_HUD.RNGIndex
end

function BattlesHUD:findTablePosition(table, RNGIndex)
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

function BattlesHUD:updateTablePosition(RNGIndex)
  RNGIndex = RNGIndex or self:getRNGIndex()
  local pos = self:findTablePosition(nil, RNGIndex)
  if pos < 1 then return end
  if self.pos == self.cur then
    self.pos = pos
  end
  self.cur = pos
end

function BattlesHUD:adjustPos(amount)
  local newPos = self.pos + amount
  if newPos < 1 then self.pos = 1
  elseif newPos > #self:getTable() then self.pos = #self:getTable()
  else self.pos = newPos end
end

function BattlesHUD:getEncounter(tableIndex)
  tableIndex = tableIndex or self.cur
  local table = self:getTable()
  if #table <= 0 then return end
  local possibleBattle = table[tableIndex]

  if possibleBattle.value and possibleBattle.value >= self.State.EncounterRate then return nil end
  if self.State.IsChampion then
    local champVal = self.State.ChampVals[possibleBattle.battles[self.State.EncounterTableSize]]
    if self.State.PartyLevel > champVal then return nil end
  end

  local group = self.State.EncounterTable[table[tableIndex].battles[self.State.EncounterTableSize]]

  return {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }
end

function BattlesHUD:getValidEncounter(tableIndex)
  tableIndex = tableIndex or self.cur
  local table = self:getTable()
  if #table <= 0 then return end

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

function BattlesHUD:drawUpcomingEncounters(locked)
  locked = locked or false
  local cur = self.cur
  if locked then
    cur = self.pos
  else
    self.pos = cur
  end

  local i = 0
  local d = 0 -- Number of entries displayed
  local tableLength = #self:getTable()

  local areaNameStr = self.State.Name

  if self.Locked then
    areaNameStr = areaNameStr .. " LOCKED"
  end
  if self.State.IsChampion then
    areaNameStr = string.format("%s C:%d", areaNameStr, self.State.PartyLevel)
  end

  gui.text(GUI_X, GUI_Y, areaNameStr)
  repeat
    local battle = self:getEncounter(cur + i)
    if battle then
      local run = "F"
      if battle.run then run = "R" end
      gui.text(GUI_X, GUI_Y + (d+1) * GUI_GAP, string.format("%d: %s %s", battle.index, run, battle.group))
      d = d + 1
    end
    i = i + 1
  until d >= NUM_TO_DISPLAY or (cur + i) > tableLength
end

function BattlesHUD:drawAreaEnemies()
  local s = {}
  for k,v in ipairs(self.State.Enemies) do
    table.insert(s, string.format("%d:%s", k, v))
  end
  EncounterLib.drawTable(s, 0, 16, GUI_GAP, "bottomleft", true)
end

function BattlesHUD:drawHUD(locked)
  if not next(self.State) then return end
  self:drawUpcomingEncounters(locked)
  self:drawAreaEnemies()
end

function BattlesHUD:init(RNG_HUD)
  self.RNG_HUD = RNG_HUD
  self.Tables = { WM = RNG_HUD:getRNGTable().WM, OW = RNG_HUD:getRNGTable().OW }
  self.pos = 1
  self.cur = 1
  self:updateState()
end

function BattlesHUD:run()
  local stateChanged = false
  self.RefreshCounter = self.RefreshCounter + 1
  if self.RefreshCounter == REFRESH_RATE and not self.Locked then
    stateChanged = self:updateState()
  end

  self.RefreshCounter = self.RefreshCounter % REFRESH_RATE

  if not next(self.State) then return end

  if self.RNG_HUD.State.RNG_CHANGED or stateChanged then
    self:updateTablePosition()
  end
end

return BattlesHUD
