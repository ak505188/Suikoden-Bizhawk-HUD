local Drawer = require "controllers.drawer"
local BaseMenu = require "menus.Base"
local Buttons = require "lib.Buttons"
local MenuProperties = require "menus.Properties"
local Worker = require "modules.RNG.submodules.Combat.worker"

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'RNG_HANDLER_MENU',
    control = MenuProperties.CONTROL_TYPES.cursor,
  },
})

function Menu:draw()
  local draw_table = {
    string.format("%s Show HP section", Worker.ShowHPExperimental and "[X]" or "[ ]"),
  }

  local controls_table = {
    "O: Back",
    "X: Toggle",
  }

  Drawer:draw(draw_table, Drawer.anchors.TOP_RIGHT)
  Drawer:draw(controls_table, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
    Worker.ShowHPExperimental = not Worker.ShowHPExperimental
  end
  return false
end

return Menu
