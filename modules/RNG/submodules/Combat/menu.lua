local Drawer = require "controllers.drawer"
local BaseMenu = require "menus.Base"
local Buttons = require "lib.Buttons"
local MenuProperties = require "menus.Properties"
local Worker = require "modules.RNG.submodules.Combat.worker"
local ActionEditMenu = require "modules.RNG.submodules.Combat.ActionEditMenu"

local OPTIONS = {
  "Show HP section",
  "Edit Party Actions",
}

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'RNG_HANDLER_MENU',
    control = MenuProperties.CONTROL_TYPES.cursor,
  },
  pos = 1,
})

function Menu:draw()
  local draw_table = {
    string.format("%s Show HP section", Worker.ShowHPExperimental and "[X]" or "[ ]"),
    "Edit Party Actions",
  }
  draw_table[self.pos] = "> " .. draw_table[self.pos]

  local controls_table = {
    "O: Back",
    "Up/Down: Move",
    "X: Select",
  }

  Drawer:draw(draw_table, Drawer.anchors.TOP_RIGHT)
  Drawer:draw(controls_table, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function Menu:adjustCursor(amount)
  local new_pos = self.pos + amount
  if new_pos < 1 then new_pos = 1
  elseif new_pos > #OPTIONS then new_pos = #OPTIONS end
  self.pos = new_pos
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Up:pressed() then
    self:adjustCursor(-1)
  elseif Buttons.Down:pressed() then
    self:adjustCursor(1)
  elseif Buttons.Cross:pressed() then
    if self.pos == 1 then
      Worker.ShowHPExperimental = not Worker.ShowHPExperimental
    elseif self.pos == 2 then
      self:openMenu(ActionEditMenu)
    end
  end
  return false
end

return Menu
