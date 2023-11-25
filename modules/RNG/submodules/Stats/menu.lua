local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local MenuProperties = require "menus.Properties"

local Menu = {
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'RNG_HANDLER_MENU',
    control = MenuProperties.CONTROL_TYPES.buttons,
  }
}

function Menu:draw()
  Drawer:draw({
    "Do: RNGIndex -1",
    "Le: RNGIndex -25",
    "Up: RNGIndex +1",
    "Ri: RNGIndex +25",
  }, Drawer.anchors.TOP_RIGHT)
end

function Menu:init() end

function Menu:run()
  if Buttons.Down:pressed() then
  elseif Buttons.Up:pressed() then
  elseif Buttons.Left:pressed() then
  elseif Buttons.Right:pressed() then
  end
end

return Menu
