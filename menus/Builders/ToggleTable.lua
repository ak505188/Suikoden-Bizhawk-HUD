local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local Utils = require "lib.Utils"

local ToggleTableBuilder = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'Toggle Selection',
    control = MenuProperties.CONTROL_TYPES.cursor,
  },
  pos = 1,
})

function ToggleTableBuilder:draw()
  local tbl_draw_table = {}

  for _, key in ipairs(self.keys) do
    local value = self.tbl[key] and "y" or "n"
    local str = string.format("%s %s", key, value)
    table.insert(tbl_draw_table, str)
  end

  tbl_draw_table[self.pos] = "> " .. tbl_draw_table[self.pos]

  Drawer:draw(tbl_draw_table, Drawer.anchors.TOP_LEFT)
  Drawer:draw({
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
    "X: Toggle",
    "O: Back",
  }, Drawer.anchors.TOP_RIGHT)
end

function ToggleTableBuilder:run()
  if Buttons.Down:pressed() then
    self:adjust(1)
  elseif Buttons.Up:pressed() then
    self:adjust(-1)
  elseif Buttons.Left:pressed() then
    self:adjust(-10)
  elseif Buttons.Right:pressed() then
    self:adjust(10)
  elseif Buttons.Cross:pressed() then
    local key = self.keys[self.pos]
    self.tbl[key] = not self.tbl[key]
  elseif Buttons.Circle:pressed() then
    return true,self.tbl
  end
  return false
end

function ToggleTableBuilder:adjust(amount)
  local new_pos = self.pos + amount
  if new_pos < 1 then self.pos = 1
  elseif new_pos > #self.keys then self.pos = #self.keys
  else self.pos = new_pos end
end

function ToggleTableBuilder:new(tbl, keys, options)
  local copy_of_self = Utils.cloneTableDeep(self)
  options = options or {}
  local menu = {}
  setmetatable(menu, copy_of_self)
  copy_of_self.__index = copy_of_self
  menu.tbl = tbl
  menu.keys = keys
  if options.type then menu.properties.type = options.type end
  if options.name then menu.properties.name = options.name end
  return menu
end

return ToggleTableBuilder
