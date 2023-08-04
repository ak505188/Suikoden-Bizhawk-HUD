local Utils = require "lib.Utils"
local Buttons = require "lib.Buttons"
local ModuleManager = require "modules.Manager"

local Menu = {}

function Menu:draw()
  local opts = {
    x = 0,
    y = 0,
    gap = 16,
    anchor = "topright"
  }
  local drawOpts = Utils.drawTable({
    "L1: Previous Module",
    "R1: Next Module"
  }, opts)
  return drawOpts
end

function Menu:run()
  if Buttons.L1:pressed() then
    ModuleManager:prevModule()
  elseif Buttons.R1:pressed() then
    ModuleManager:nextModule()
  end
end

return Menu
