local MenuProperties = require "menus.Properties"

local BaseMenu = {
  properties = {
    type = MenuProperties.MENU_TYPES.base,
    name = 'BASE'
  }
}

function BaseMenu:new(menu)
  menu = menu or {}
  setmetatable(menu, self)
  self.__index = self
  return menu
end

function BaseMenu:draw() end

function BaseMenu:init() end

function BaseMenu:run()
  return false
end

return BaseMenu
