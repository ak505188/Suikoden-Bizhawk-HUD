local Buttons = require "lib.Buttons"
local Worker = require "modules.RoomInfo.worker"
local Drawer = require "controllers.drawer"
local MenuProperties = require "menus.Properties"
local BaseMenu = require "menus.Base"

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'ROOM_INFO_MENU'
  },
})

function Menu:draw()
  Drawer:draw({
    "X: Go to Battle",
    "O: Back",
    "[]: Customize",
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
  }, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function Menu:init() end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
  elseif Buttons.Square:pressed() then
  elseif Buttons.Down:pressed() then
  elseif Buttons.Up:pressed() then
  elseif Buttons.Left:pressed() then
  elseif Buttons.Right:pressed() then
  end
  return false
end

return Menu
