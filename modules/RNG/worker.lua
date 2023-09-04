local RNGMonitor = require "monitors.RNG_Monitor"
local Drawer = require "controllers.drawer"

local Worker = {}

function Worker:run() end

function Worker:onChange() end

function Worker:draw()
  Drawer:draw({ "RNG Module Draw" }, Drawer.anchors.TOP_LEFT)
end

function Worker:adjustIndex(amount)
  RNGMonitor:adjustIndex(amount)
end

return Worker
