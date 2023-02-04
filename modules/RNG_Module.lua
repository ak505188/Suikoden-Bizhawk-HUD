local Utils = require "lib.Utils"
local Buttons = require "lib.Buttons"
local RNG_Monitor = require "monitors.RNG_Monitor"

local Menu = {}

function Menu.draw()
  local opts = {
    x = 0,
    y = 0,
    gap = 16,
    anchor = "topright"
  }
  Utils.drawTable({
    "Dn: RNGIndex -1",
    "Le: RNGIndex -25",
    "Up: RNGIndex +1",
    "Ri: RNGIndex +25",
  }, opts)
end

function Menu:run()
  if Buttons.Down:pressed() then
    RNG_Monitor:adjustRNGIndex(-1)
  elseif Buttons.Up:pressed() then
    RNG_Monitor:adjustRNGIndex(1)
  elseif Buttons.Left:pressed() then
    RNG_Monitor:adjustRNGIndex(-25)
  elseif Buttons.Right:pressed() then
    RNG_Monitor:adjustRNGIndex(25)
  end
end

local RNG_Module = {
  Name = "RNG",
  Menu = Menu
}

function RNG_Module:run() end

function RNG_Module:draw()
  RNG_Monitor:draw()
end

return RNG_Module
