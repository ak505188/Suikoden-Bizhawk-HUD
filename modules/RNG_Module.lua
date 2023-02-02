local Utils = require "lib.Utils"
local buttons = require "lib.Buttons"

local Menu = {}

function Menu.draw()
  local opts = {
    x = 0,
    y = 0,
    gap = 16,
    anchor = "topright"
  }
  Utils.drawTable({
    "Up: RNGIndex -1",
    "Dn: RNGIndex +1",
    "Le: RNGIndex -25",
    "Ri: RNGIndex +25",
  }, opts)
end

function Menu:run()
  if buttons.Down:pressed() then
    self.RNG_Monitor:adjustRNGIndex(-1)
  elseif buttons.Up:pressed() then
    self.RNG_Monitor:adjustRNGIndex(1)
  elseif buttons.Left:pressed() then
    self.RNG_Monitor:adjustRNGIndex(-25)
  elseif buttons.Right:pressed() then
    self.RNG_Monitor:adjustRNGIndex(25)
  end
end

local RNG_Module = {
  Name = "RNG",
  Menu = Menu
}

function RNG_Module:init(RNG_Monitor)
  self.RNG_Monitor = RNG_Monitor
  self.Menu.RNG_Monitor = RNG_Monitor
end

function RNG_Module:run() end

function RNG_Module:draw()
  self.RNG_Monitor:draw()
end

return RNG_Module
