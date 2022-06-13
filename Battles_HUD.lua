local EncounterTable = require "EncounterTable"
local EncounterLib = require "EncounterLib"
local ZoneInfo = require "ZoneInfo"
local RNGLib = require "RNGLib"
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
Config.GUI_Y = 0 + Config.GUI_GAP * 4

local Gamestates = {
  ["TITLE"] = 0,
  ["WORLD_MAP"] = 1,
  ["OVERWORLD"] = 2,
  ["BATTLE"] = 3,
  ["EVENT"] = 4,
  ["GAME_OVER"] = 99,
}

local BattlesHUD = {
  Tables = {}, -- Should be key'd by area name from State
  State = {},
  RefreshCounter = 0
}

-- Returns whether or not state changed
function BattlesHUD:updateState()
  local location = EncounterLib.onWorldMapOrOverworld()
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
    EncounterTableSize = data.tableSize,
    WM_Zone = wm_zone,
    Area_Zone = area_zone,
  }
  return true
end

function BattlesHUD:getTable(name)
  name = name or self.State.Name
  return self.Tables[name]
end

function BattlesHUD:findTablePosition(table, rngIndex)
  table = table or self:getTable()
  local startIndex = table.startIndex
  local battles = table.battles

  if rngIndex < startIndex or rngIndex > battles[#battles].index then return 0 end

  -- Eventually want to do a binary or ternary search here
  -- For now, just going to iterate through the list
  local pos = 1

  -- Shortcut if rngIndex >= current position index, which should be most common scenario
  if rngIndex >= battles[battles.cur].index then
    pos = battles.cur
  end
  repeat
    -- This only works because we're going in order.
    -- If doing more optimal search we would need to
    -- compare both current and next entry
    if rngIndex < battles[pos].index then return pos end
    pos = pos + 1
  until pos > #battles
  return -1
end

---@param referenceTables? { WM: {}, OW: {} }
-- Create Initial Battle Buffer
function BattlesHUD:createBattlesTable(referenceTables)
  referenceTables = referenceTables or self.ReferenceTables
  local encounterRate = State.EncounterRate
  local encounterTable = State.EncounterTable
  local encounterTableSize = State.EncounterTableSize
  local areaName = State.Name
  if not encounterTable then return end

  local currentTable = {
    pos = 1,
    cur = 1,
    battles = {},
  }

  local referenceTable
  local location = State.Location
  if location == 1 then
    referenceTable = referenceTables.WM
  else
    referenceTable = referenceTables.OW
  end

  -- Start iterating through the list, adding battles whenever it's a real battle
  local i = 1

  repeat
    local curPossibleBattle = referenceTable[i]
    if location == 1 or curPossibleBattle.value < encounterRate then
      local nextRNG = RNGLib.nextRNG(curPossibleBattle.rng)
      local encounterIndex = EncounterLib.getEncounterIndex(nextRNG, encounterTableSize)
      local battle = {
        rng = curPossibleBattle.rng,
        index = curPossibleBattle.index,
        group = encounterTable[encounterIndex]
      }
      table.insert(currentTable.battles, battle)
      if not currentTable.startIndex then
        currentTable.startIndex = curPossibleBattle.index
      end
    end
    i = i + 1
  until #currentTable.battles >= Config.BATTLES_BUFFER or i > #referenceTable
  Tables[areaName] = currentTable
end

function BattlesHUD:drawUpcomingEncounters()
  local table = self.Tables[self.State.Name]
  local battles = table.battles
  local cur = table.cur
  for i = 0, Config.NUM_TO_DISPLAY do
    local battle = battles[cur + i]
    if not battle then break end
    gui.text(Config.GUI_X, Config.GUI_Y + i * Config.GUI_GAP, string.format("%d: %s", battle.index, battle.group))
  end
end

function BattlesHUD:init(referenceTables)
  self.ReferenceTables = referenceTables
  self:updateState()
  self:createBattlesTable()
end

function BattlesHUD:run()
  local stateChanged = false

  self.RefreshCounter = self.RefreshCounter + 1
  if self.RefreshCounter == Config.REFRESH_RATE then
    stateChanged = self:updateState()
    -- TODO: Handle state change
  end

  -- TODO: Handle RNG Change
  self:drawUpcomingEncounters(Config.GUI_X, Config.GUI_Y + 4 * Config.GUI_GAP, Config.GUI_GAP, Config.BATTLES_DISPLAY_LENGTH)
  self.RefreshCounter = self.RefreshCounter % REFRESH_RATE
end

return BattlesHUD
