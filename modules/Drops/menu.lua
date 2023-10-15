local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local Worker = require "modules.Drops.worker"
local MenuProperties = require "menus.Properties"

local Menu = {
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'DROPS_MENU',
    control = MenuProperties.CONTROL_TYPES.buttons,
  }
}

function Menu:draw()
  Worker:draw()
end

function Menu:init() end

function Menu:run() end

return Menu
