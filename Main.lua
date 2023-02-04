local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local MenuController = require "Menu"

local ModuleManager = require "modules.Manager"
local RNGModule = require "modules.RNG_Module"
RNGModule:init(RNGMonitor)


StateMonitor:run()
RNGMonitor:init(StateMonitor)
ModuleManager:addModule(RNGModule)
MenuController:init(ModuleManager)

-- For controls/menus, should probably use a stack of structs with functions

while true do
  emu.frameadvance()
  StateMonitor:run()
  RNGMonitor:run()
  RNGMonitor:draw()

  emu.yield()
  if client.ispaused() then
    MenuController:open()
  end
end
