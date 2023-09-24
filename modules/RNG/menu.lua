local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local Worker = require "modules.RNG.worker"
local MenuProperties = require "menus.Properties"

local Menu = {
  properties = {
    type = MenuProperties.TYPES.module,
    name = 'RNG_HANDLER_MENU'
  }
}

function Menu:draw()
  Drawer:draw({
    "Do: RNGIndex -1",
    "Le: RNGIndex -25",
    "Up: RNGIndex +1",
    "Ri: RNGIndex +25",
  }, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function Menu:init() end

function Menu:run()
  if Buttons.Down:pressed() then
    Worker:adjustIndex(-1)
  elseif Buttons.Up:pressed() then
    Worker:adjustIndex(1)
  elseif Buttons.Left:pressed() then
    Worker:adjustIndex(-25)
  elseif Buttons.Right:pressed() then
    Worker:adjustIndex(25)
  end
end

return Menu
