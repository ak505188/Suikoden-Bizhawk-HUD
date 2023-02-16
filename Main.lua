local StateMonitor = require "monitors.State_Monitor"
local RNGMonitor = require "monitors.RNG_Monitor"

local MenuController = require "menus.MenuController"

local ModuleManager = require "modules.Manager"
local RNGModule = require "modules.RNG_Module"

ModuleManager:addModule(RNGModule)
StateMonitor:init()
RNGMonitor:init()
MenuController:init({ RNGMonitor, StateMonitor })

function draw()
  local opts = RNGMonitor:draw()
  opts = StateMonitor:draw(opts)
  ModuleManager:getCurrentModule():draw(opts)
end

while true do
  emu.frameadvance()
  StateMonitor:run()
  RNGMonitor:run()

  draw()

  emu.yield()
  if client.ispaused() then
    MenuController:open()
  end
end
