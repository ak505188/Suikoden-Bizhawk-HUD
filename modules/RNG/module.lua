local Menu = require "modules.RNG.menu"
local Utils = require "lib.Utils"

local RNG_Module = {
  Name = "RNG",
  Menu = Menu
}

function RNG_Module:run() end

function RNG_Module:onChange() end

function RNG_Module:draw(drawOpts)
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

return RNG_Module
