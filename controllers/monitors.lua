local StateMonitor = require "monitors.State_Monitor"
local RNGMonitor = require "monitors.RNG_Monitor"
local MenuController = require "menus.MenuController"
local RNGResetMenu = require "menus.RNG_Reset_Menu"

StateMonitor:init()
RNGMonitor:init()

local MonitorsController = {
  monitors = { RNGMonitor, StateMonitor },
  RNG = RNGMonitor,
  State = StateMonitor,
}

function MonitorsController:init()
  for _,monitor in ipairs(self.monitors) do
    monitor:init()
  end
end

function MonitorsController:run()
  local RNGMonitorEvent = self.RNG:run()
  if RNGMonitorEvent then
    RNGResetMenu:init()
    MenuController:open(RNGResetMenu)
  end

  self.State:run()
end

function MonitorsController:draw()
  for _,monitor in ipairs(self.monitors) do
    monitor:draw()
  end
end

return MonitorsController
