local RNGMonitor = require "monitors.RNG_Monitor"
local Utils = require "lib.Utils"

local Worker = {}

function Worker:run() end

function Worker:onChange() end

function Worker:draw(drawOpts)
  local opts = {
    x = drawOpts.x or 0,
    y = drawOpts.y or 0,
    gap = drawOpts.gap or 16,
    anchor = drawOpts.anchor or "topright"
  }
  local newDrawOpts = Utils.drawTable({
    "RNG Module Draw"
  }, opts)
  return newDrawOpts
end

function Worker:adjustIndex(amount)
  RNGMonitor:adjustIndex(amount)
end

return Worker
