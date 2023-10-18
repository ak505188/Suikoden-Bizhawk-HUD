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
    "Up: Up 1 Slot",
    "Do: Down 1 Slot",
    "Le: Up 10 Slots",
    "Ri: Down 10 Slots",
  }, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function Menu:init()
  self.slot = 0
end

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

function Menu:adjustSlot()

end

return Menu
