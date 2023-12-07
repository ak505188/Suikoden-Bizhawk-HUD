local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local Utils = require "lib.Utils"

local NumberEditorMenu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'Number Editor',
    control = MenuProperties.CONTROL_TYPES.buttons,
  },
})

function NumberEditorMenu:draw()
  local num_str = string.format("0x%08x", self.num)
  Drawer:draw({
    "Up: Increase",
    "Do: Decrease",
    "Le: Left 1 Digit",
    "Ri: Right 1 Digit",
    "X: Confirm",
    "O: Back",
  }, Drawer.anchors.TOP_RIGHT)

  local cursor_tbl = { " ", " ", " ", " ", " ", " ", " ", " " }
  cursor_tbl[#cursor_tbl - self.pos] = "-"

  local cur_drawer_opts = Drawer.anchorOpts[Drawer.anchors.TOP_RIGHT]
  Drawer:draw({ num_str }, Drawer.anchors.TOP_RIGHT)
  gui.text(cur_drawer_opts.x, cur_drawer_opts.y+8, table.concat(cursor_tbl, ""), nil, Drawer.anchors.TOP_RIGHT)
end

function NumberEditorMenu:run()
  self:adjustHandler()
  if Buttons.Cross:pressed() then
    return true,self.num
  elseif Buttons.Circle:pressed() then
    return true
  end
  return false
end

function NumberEditorMenu:adjustValue(amount)
  local base = 16
  amount = amount * base ^ self.pos
  local new_value = (self.num + amount) & 0xffffffff
  self.num = new_value
end

function NumberEditorMenu:adjustPos(amount)
  local new_pos = self.pos + amount
  if new_pos < 0 then new_pos = 0
  elseif new_pos > 7 then new_pos = 7 end
  self.pos = new_pos
end

function NumberEditorMenu:adjustHandler()
  if Buttons.Down:pressed() then
    self:adjustValue(-1)
  elseif Buttons.Up:pressed() then
    self:adjustValue(1)
  elseif Buttons.Left:pressed() then
    self:adjustPos(1)
  elseif Buttons.Right:pressed() then
    self:adjustPos(-1)
  end
end

function NumberEditorMenu:new(num, options)
  local copy_of_self = Utils.cloneTableDeep(self)
  options = options or {}
  local menu = {}
  setmetatable(menu, copy_of_self)
  copy_of_self.__index = copy_of_self
  menu.num = num
  menu.pos = 0
  if options.type then menu.properties.type = options.type end
  if options.name then menu.properties.name = options.name end
  return menu
end

return NumberEditorMenu
