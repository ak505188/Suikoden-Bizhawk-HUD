local Menu = require "modules.RNG.menu"
local RNG_Module = {
  Name = "RNG",
  Menu = Menu
}

function RNG_Module:init(RNG_Monitor)
  self.RNG_Monitor = RNG_Monitor
end

return RNG_Module
