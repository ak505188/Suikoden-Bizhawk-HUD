local StateMonitor = require "monitors.State_Monitor"
local RNGMonitor = require "monitors.RNG_Monitor"

local MenuController = require "menus.MenuController"

local ModuleManager = require "modules.Manager"
local RNGModule = require "modules.RNG.module"
local BattleModule = require "modules.Battles.module"

ModuleManager:addModule(BattleModule)
ModuleManager:addModule(RNGModule)

StateMonitor:init()
RNGMonitor:init()
MenuController:init({ RNGMonitor, StateMonitor })

local function draw()
  local opts = RNGMonitor:draw()
  opts = StateMonitor:draw(opts)
  ModuleManager:getCurrent():draw(opts)
end

while true do
  emu.frameadvance()
  if (client.ispaused()) then MenuController:run() end
  StateMonitor:run()
  RNGMonitor:run()

  draw()

  ModuleManager:run()

  emu.yield()
  if client.ispaused() then
    MenuController:open()
  end
end
