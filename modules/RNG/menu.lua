local Buttons = require "lib.Buttons"
--
-- StackMenuAPI
-- Will be defined within module as its own structure / class attached to the Module
-- Attach dependencies with initialization in module. Part of Module
-- Methods:
-- draw()
-- close()
-- run/poll or onButton?

local RNG_Menu = {}

function RNG_Menu:init(RNG_Monitor)
  self.RNG_Monitor = RNG_Monitor
  self.drawTable = {
    "Up: RNGIndex -1",
    "Dn: RNGIndex +1",
    "Le: RNGIndex -25",
    "Ri: RNGIndex +25",
  }
end

-- true to keep open, false to close
function RNG_Menu:run(buttons)
  if buttons.Down:pressed() then
    self.RNG_Monitor:adjustRNGIndex(-1)
  elseif buttons.Up:pressed() then
    self.RNG_Monitor:adjustRNGIndex(1)
  elseif buttons.Left:pressed() then
    self.RNG_Monitor:adjustRNGIndex(-25)
  elseif buttons.Right:pressed() then
    self.RNG_Monitor:adjustRNGIndex(25)
  end
  return true
end

return RNG_Menu
