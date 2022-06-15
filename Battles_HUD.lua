local EncounterTable = require "EncounterTable"
local EncounterLib = require "EncounterLib"
local ZoneInfo = require "ZoneInfo"
local Address = require "Address"

local Config = {
  ["REFRESH_RATE"] = 60, -- Refresh data every X frames
  ["BATTLES_BUFFER"] = 30, -- Size of encounter table to store
  ["BATTLES_DISPLAY_LENGTH"] = 15, -- How many upcoming encounters to show
  ["BUFFER_ADD_SIZE"] = 15, -- How much to increase buffer size by
  ["GUI_GAP"] = 16,
  ["GUI_X"] = 0,
  ["NUM_TO_DISPLAY"] = 15,
}
Config.GUI_Y = Config.GUI_GAP * 6

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
}

function BattlesHUD:toggleLock()
  self.Locked = not self.Locked
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

  -- Check if change, if not do nothing.
  if (location == self.State.Location and
      wm_zone == self.State.WM_ZONE and
      area_zone == self.State.Area_Zone and
      inGameEncounterRate == self.State.EncounterRate) then
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
    WM_Zone = wm_zone,
    Area_Zone = area_zone,
  }
  return true
end

function BattlesHUD:getTable(location)
  location = location or self.State.Location
  local locationKey = EncounterLib.locationIntToKey(location)
  return self.Tables[locationKey]
end

function BattlesHUD:findTablePosition(table, RNGIndex)
  table = table or self:getTable()
  if #table <= 0 then return end
  RNGIndex = RNGIndex or self.RNGIndex

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
  RNGIndex = RNGIndex or self.RNGIndex
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

  local group = self.State.EncounterTable[table[tableIndex].battles[self.State.EncounterTableSize]]

  return {
    index = possibleBattle.index,
    rng = possibleBattle.rng,
    run = possibleBattle.run,
    group = group
  }
end

-- function getEncounterTable(areaName)
--   areaName = areaName or self.State.Name
--   return self.State.EncounterTable

function BattlesHUD:drawUpcomingEncounters(locked)
  locked = locked or self.Locked
  local cur = self.cur
  if locked then
    cur = self.pos
  else
    self.pos = cur
  end

  local i = 0
  local d = 0 -- Number of entries displayed
  local tableLength = #self:getTable()

  gui.text(Config.GUI_X, Config.GUI_Y, self.State.Name)
  repeat
    local battle = self:getEncounter(cur + i)
    if battle then
      local run = "F"
      if battle.run then run = "R" end
      gui.text(Config.GUI_X, Config.GUI_Y + (d+1) * Config.GUI_GAP, string.format("%d: %s %s", battle.index, run, battle.group))
      d = d + 1
    end
    i = i + 1
  until d >= Config.NUM_TO_DISPLAY or (cur + i) > tableLength
end

function BattlesHUD:drawAreaEnemies()
  local s = ""
  for k,v in ipairs(self.State.Enemies) do
    s = s .. string.format("%d:%s ", k, v)
  end

  gui.text(Config.GUI_X, client.bufferheight()-16, s)
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
  self.RNGIndex = RNG_HUD.RNGIndex
  self:updateState()
end

function BattlesHUD:run(RNGIndex)
  local stateChanged = false
  self.RefreshCounter = self.RefreshCounter + 1
  if self.RefreshCounter == Config.REFRESH_RATE then
    stateChanged = self:updateState()
  end

  if not next(self.State) then return end

  if RNGIndex ~= self.RNGIndex or stateChanged then
    self.RNGIndex = RNGIndex
    self:updateTablePosition(RNGIndex)
  end

  self.RefreshCounter = self.RefreshCounter % Config.REFRESH_RATE
end

return BattlesHUD
