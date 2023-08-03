local RNGMonitor = require "monitors.RNG_Monitor"
local Utils = require "lib.Utils"

local RNG_Worker = {}

function RNG_Worker:run() end

function RNG_Worker:onChange() end

function RNG_Worker:draw(drawOpts)
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

function RNG_Worker:adjustRNGIndex(amount)
  RNGMonitor:adjustRNGIndex(amount)
end

return RNG_Worker
