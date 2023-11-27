local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local Utils = require "lib.Utils"

local ScrollingListSelectionMenu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'List Selection',
    control = MenuProperties.CONTROL_TYPES.scrolling_cursor,
  },
  pos = 1,
  list = {},
})

function ScrollingListSelectionMenu:draw()
  local list_draw_table = {}
  local count = 0
  while count < 10 and count + self.pos <= #self.list do
    table.insert(list_draw_table, self.list[self.pos + count])
    count = count + 1
  end

  list_draw_table[1] = "> " .. list_draw_table[1]

  Drawer:draw(list_draw_table, Drawer.anchors.TOP_LEFT)
  Drawer:draw({
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
    "X: Select",
    "O: Back",
  }, Drawer.anchors.TOP_RIGHT)
end

function ScrollingListSelectionMenu:run()
  self:adjustHandler()
  if Buttons.Cross:pressed() then
    return true,self.list[self.pos]
  elseif Buttons.Circle:pressed() then
    return true
  end
  return false
end

function ScrollingListSelectionMenu:adjustHandler()
  if Buttons.Down:pressed() then
    self:adjust(1)
  elseif Buttons.Up:pressed() then
    self:adjust(-1)
  elseif Buttons.Left:pressed() then
    self:adjust(-10)
  elseif Buttons.Right:pressed() then
    self:adjust(10)
  end
end

function ScrollingListSelectionMenu:adjust(amount)
  local new_pos = self.pos + amount
  if new_pos < 1 then self.pos = 1
  elseif new_pos > #self.list then self.pos = #self.list
  else self.pos = new_pos end
end

function ScrollingListSelectionMenu:new(list, options)
  local copy_of_self = Utils.cloneTableDeep(self)
  options = options or {}
  local menu = {}
  setmetatable(menu, copy_of_self)
  copy_of_self.__index = copy_of_self
  menu.list = list
  if options.type then menu.properties.type = options.type end
  if options.name then menu.properties.name = options.name end
  return menu
end

return ScrollingListSelectionMenu
