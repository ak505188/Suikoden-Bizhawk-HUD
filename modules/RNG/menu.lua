local Utils = require "lib.Utils"
local Buttons = require "lib.Buttons"
local RNGWorker = require "modules.RNG.worker"

local Menu = {}

function Menu:draw(drawOpts)
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

function Menu:init() end

function Menu:onClose() end

function Menu:run()
  if Buttons.Down:pressed() then
    RNGWorker:adjustRNGIndex(-1)
  elseif Buttons.Up:pressed() then
    RNGWorker:adjustRNGIndex(1)
  elseif Buttons.Left:pressed() then
    RNGWorker:adjustRNGIndex(-25)
  elseif Buttons.Right:pressed() then
    RNGWorker:adjustRNGIndex(25)
  end
end

return Menu
