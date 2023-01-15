local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local MenuController = require "Menu"


local ModuleManager = require "modules.Manager"
local RNGModule = require "modules.RNG.main"


StateMonitor:run()
RNGMonitor:init(StateMonitor)

-- For controls/menus, should probably use a stack of structs with functions

while true do
  -- Controls:run()
  emu.frameadvance()
  StateMonitor:run()
  RNGMonitor:run()
  RNGMonitor:draw()
end
