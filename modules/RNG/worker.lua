local RNGMonitor = require "monitors.RNG_Monitor"
local Drawer = require "controllers.drawer"
local StatsSubmodule = require "modules.RNG.submodules.Stats.submodule"
local Modes = require "modules.RNG.modes"

local Worker = {
  mode = Modes.Table.None,
  submodules = {
    [Modes.Table.Stats] = StatsSubmodule
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
  if self.mode ~= Modes.None and self.submodules[self.mode] ~= nil then
    self.submodules[self.mode].Worker:draw()
  else
    Drawer:draw({ "RNG Module" }, Drawer.anchors.TOP_LEFT)
  end
end

function Worker:adjustIndex(amount)
  RNGMonitor:adjustIndex(amount)
end

return Worker
