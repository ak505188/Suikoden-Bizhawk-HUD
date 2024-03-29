local StateMonitor = require "monitors.State_Monitor"
local RNGMonitor = require "monitors.RNG_Monitor"
local RoomMonitor = require "monitors.Room_Monitor"

StateMonitor:init()
RNGMonitor:init()

local ModuleManager = require "modules.Manager"
local RNG_Module = require "modules.RNG.module"
local Battles_Module = require "modules.Battles.module"
local RoomInfo_Module = require "modules.RoomInfo.module"
local Drops_Module = require "modules.Drops.module"
local Saves_Module = require "modules.Saves.module"
local Toolbox_Module = require "modules.Toolbox.module"

ModuleManager:addModule(RNG_Module)
ModuleManager:addModule(Battles_Module)
ModuleManager:addModule(Drops_Module)
ModuleManager:addModule(RoomInfo_Module)
ModuleManager:addModule(Saves_Module)
ModuleManager:addModule(Toolbox_Module)

local MenuController = require "menus.MenuController"
local Drawer = require "controllers.drawer"
local RNGResetMenu = require "menus.RNG_Reset_Menu"

local function draw()
  RNGMonitor:draw()
  StateMonitor:draw()
  -- RoomMonitor:draw()
  ModuleManager:draw()
end

while true do
  emu.frameadvance()

  local RNGMonitorEvent = RNGMonitor:run()
  if RNGMonitorEvent then MenuController:open(RNGResetMenu) end

  StateMonitor:run()
  RoomMonitor:run()

  ModuleManager:run()

  Drawer:clear()
  draw()

  emu.yield()
  if client.ispaused() then
    MenuController:open()
  end
end
