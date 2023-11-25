local RNGMonitor = require "monitors.RNG_Monitor"
local Drawer = require "controllers.drawer"
local StatsSubmodule = require "modules.RNG.submodules.Stats.submodule"

local Modes = {
  None = 'RNG',
  Stats = 'STATS',
  Chinchironin = 'CHINCHIRONIN',
  Combat = 'COMBAT' -- Accuracy & Crit Rolls
}

local Worker = {
  mode = Modes.Stats,
  submodules = {
    [Modes.Stats] = StatsSubmodule
  }
}


function Worker:run()
  if self.mode ~= Modes.None and self.submodules[self.mode] ~= nil then
    self.submodules[self.mode].Worker:run()
  end
end

function Worker:onChange() end

function Worker:init() end

function Worker:draw()
  Drawer:draw({ self.mode }, Drawer.anchors.TOP_LEFT, nil, true)
  self.submodules[self.mode].Worker:draw()
end

function Worker:adjustIndex(amount)
  RNGMonitor:adjustIndex(amount)
end

return Worker
