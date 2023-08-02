local Utils = require "lib.Utils"
local Buttons = require "lib.Buttons"
local RNGMonitor = require "monitors.RNG_Monitor"

local Menu = {}

function Menu.draw(drawOpts)
  local opts = {
    x = drawOpts.x or 0,
    y = drawOpts.y or 0,
    gap = drawOpts.gap or 16,
    anchor = drawOpts.anchor or "topright"
  }
  local newDrawOpts = Utils.drawTable({
    "Do: RNGIndex -1",
    "Le: RNGIndex -25",
    "Up: RNGIndex +1",
    "Ri: RNGIndex +25",
  }, opts)
  return newDrawOpts
end

function Menu:run()
  if Buttons.Down:pressed() then
    RNGMonitor:adjustRNGIndex(-1)
  elseif Buttons.Up:pressed() then
    RNGMonitor:adjustRNGIndex(1)
  elseif Buttons.Left:pressed() then
    RNGMonitor:adjustRNGIndex(-25)
  elseif Buttons.Right:pressed() then
    RNGMonitor:adjustRNGIndex(25)
  end
end

return Menu
