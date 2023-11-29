local ListSelectionMenuBuilder = require "menus.Builders.List"
local MenuProperties = require "menus.Properties"
local Tools = require "menus.Tools.List"

local Menu = ListSelectionMenuBuilder:new(Tools.List, {
  type = MenuProperties.MENU_TYPES.tool_menu,
  name = 'Tool Selection Menu'
})

return Menu
