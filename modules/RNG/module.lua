local Menu = require "modules.RNG.menu"

local RNG_Module = {
  Name = "RNG",
  Menu = Menu
}

function RNG_Module:run() end

function RNG_Module:draw(opts) return opts end

return RNG_Module
