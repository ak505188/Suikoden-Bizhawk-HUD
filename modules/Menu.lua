local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local ModuleManager = require "modules.Manager"

local Menu = {
  properties = {
    name = 'MODULE_HANDLER_MENU'
  }
}

function Menu:draw()
  Drawer:draw({
    "L1: Previous Module",
    "R1: Next Module"
  }, Drawer.anchors.TOP_RIGHT)
end

function Menu:run()
  if Buttons.L1:pressed() then
    ModuleManager:prevModule()
    return true
  elseif Buttons.R1:pressed() then
    ModuleManager:nextModule()
    return true
  end
  return false
end

return Menu
