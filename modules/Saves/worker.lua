local Config = require "Config"
local Drawer = require "controllers.drawer"
local lib = require "modules.Saves.lib"

local Worker = {}

function Worker:init() end

function Worker:draw()
  Drawer:draw({ "Save Module" }, Drawer.anchors.TOP_LEFT, nil, true)
end

function Worker:run()
  if not Config.Saves.AUTOSAVE_ENABLED then return end
  if not lib.hasIGTChanged() then return end

  local igtInSeconds = lib.getIGTinSeconds()

  if igtInSeconds <= 0 then return end
  if igtInSeconds % Config.Saves.AUTOSAVE_INTERVAL ~= 0 then return end

  local save_name = lib.getSaveName()
  savestate.save(lib.getAutoSavePath(save_name))
end

return Worker
