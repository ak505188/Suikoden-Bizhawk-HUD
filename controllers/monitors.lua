local StateMonitor = require "monitors.State_Monitor"
local RNGMonitor = require "monitors.RNG_Monitor"

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
  for _,monitor in ipairs(self.monitors) do
    monitor:run()
  end
end

function MonitorsController:draw()
  for _,monitor in ipairs(self.monitors) do
    monitor:draw()
  end
end

return MonitorsController
