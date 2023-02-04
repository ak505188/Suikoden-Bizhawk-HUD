local StateMonitor = require "monitors.State_Monitor"
local RNGMonitor = require "monitors.RNG_Monitor"

local MenuController = require "Menu"

local ModuleManager = require "modules.Manager"
local RNGModule = require "modules.RNG_Module"

ModuleManager:addModule(RNGModule)


StateMonitor:init()
RNGMonitor:init()

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
