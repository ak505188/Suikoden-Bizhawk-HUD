local StateMonitor = require "monitors.State_Monitor"
local RNGMonitor = require "monitors.RNG_Monitor"

local MenuController = require "menus.MenuController"

local ModuleManager = require "modules.Manager"
local RNG_Module = require "modules.RNG.module"
local Battles_Module = require "modules.Battles.module"

ModuleManager:addModule(Battles_Module)
ModuleManager:addModule(RNG_Module)

StateMonitor:init()
RNGMonitor:init()
MenuController:init({ RNGMonitor, StateMonitor })

local function draw()
  local opts = RNGMonitor:draw()
  opts = StateMonitor:draw(opts)
  ModuleManager:draw(opts)
end

while true do
  emu.frameadvance()
  if (client.ispaused()) then MenuController:run() end
  StateMonitor:run()
  RNGMonitor:run()
  ModuleManager:run()

  draw()

  emu.yield()
  if client.ispaused() then
    MenuController:open()
  else
    MenuController:onClose()
  end
end
