local fs = require "lib.fs"
local OS = require "lib.os"
local Address = require "lib.Address"
local Gamestates = require "lib.Enums.Gamestate"
local Charmap = require "lib.Charmap"
local Config = require "Config"
local ZoneInfo = require "lib.ZoneInfoComplete"
local StateMonitor = require "monitors.State_Monitor"

local function readNameFromMemory()
  return Charmap.readStringFromMemory(Address.Names.HERO_2, 8)
end

local function areaDataToStr(wm, area, gamestate)
  local name = "Unknown"
  if ZoneInfo[wm] == nil then return name end

  if gamestate == Gamestates.WORLD_MAP then
    return ZoneInfo[wm].name
  end

  -- TODO: Add events using event index and state check

  name = ZoneInfo[wm].name
  if ZoneInfo[wm][area] == nil then return name end
  name = ZoneInfo[wm][area]
  return name
end

local function getSaveName()
  local area_name = areaDataToStr(StateMonitor.WM_ZONE.current, StateMonitor.AREA_ZONE.current, StateMonitor.IG_CURRENT_GAMESTATE.current):gsub(" ", "_")
  local igt = string.format("%02dh%02dm%02ds", StateMonitor.IGT_HOURS.current, StateMonitor.IGT_MINUTES.current, StateMonitor.IGT_SECONDS.current)
  return string.format("%s-%s.State", igt, area_name)
end

local function getCategoryName()
  local category_dir = Config.Saves.CATEGORY_DIRECTORY
  if category_dir == nil or #category_dir == 0 then
    return readNameFromMemory()
  end
  return category_dir
end

local function getSavePath(save_name)
  save_name = save_name or ""
  local path = OS:convertPath(string.format("%s/%s/%s", Config.Saves.SAVE_DIRECTORY, getCategoryName(), save_name))
  return path
end

local function getAutoSavePath(save_name)
  save_name = save_name or ""
  local path = OS:convertPath(string.format("%s/%s/%s", Config.Saves.AUTOSAVE_DIRECTORY, getCategoryName(), save_name))
  return path
end

local function setupSaveDirectories()
  if not fs.isDir(Config.Saves.SAVE_DIRECTORY) then
    fs.mkdir(Config.Saves.SAVE_DIRECTORY)
  end
  if not fs.isDir(getSavePath()) then
    fs.mkdir(getSavePath())
  end

  if Config.Saves.AUTOSAVE_ENABLED then
    if not fs.isDir(Config.Saves.AUTOSAVE_DIRECTORY) then
      fs.mkdir(Config.Saves.AUTOSAVE_DIRECTORY)
    end
    if not fs.isDir(getAutoSavePath()) then
      fs.mkdir(getAutoSavePath())
    end
  end
end

local function getIGTinSeconds()
  local hours = StateMonitor.IGT_HOURS.current
  local minutes = StateMonitor.IGT_MINUTES.current
  local seconds = StateMonitor.IGT_SECONDS.current

  minutes = minutes + hours * 60
  seconds = seconds + minutes * 60
  return seconds
end

local function hasIGTChanged()
  return StateMonitor.IGT_HOURS.changed or  StateMonitor.IGT_MINUTES.changed or StateMonitor.IGT_SECONDS.changed
end

return {
  getAutoSavePath = getAutoSavePath,
  getCategoryName = getCategoryName,
  getIGTinSeconds = getIGTinSeconds,
  getSaveName = getSaveName,
  getSavePath = getSavePath,
  hasIGTChanged = hasIGTChanged,
  readNameFromMemory = readNameFromMemory,
  setupSaveDirectories = setupSaveDirectories
}
