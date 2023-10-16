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
  Drawer:draw({
    "[]: Filter Drops",
    string.format("^: %s Table Position", Worker.DropTable.locked_pos == -1 and "Lock" or "Unlock"),
    "O: Back",
    "Up: Scroll 1 Up",
    "Do: Scroll 1 Down",
    "Le: Scroll 10 Up",
    "Ri: Scroll 10 Down",
  }, Drawer.anchors.TOP_RIGHT)
  Worker:draw(self.table_pos)
end

function Menu:init()
  if Worker.DropTable.locked_pos == -1 then
    self.table_pos = Worker.DropTable.cur_table_pos
  else
    self.table_pos = Worker.DropTable.locked_pos
  end
end

function Menu:adjustTablePos(amount)
  self.table_pos = self.table_pos + amount
  if self.table_pos < 1 then
    self.table_pos = 1
  elseif self.table_pos > #Worker.DropTable.drops then
    self.table_pos = #Worker.DropTable.drops
  end
  if Worker.DropTable.locked_pos ~= -1 then
    Worker.DropTable.locked_pos = self.table_pos
  end
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Triangle:pressed() then
    if Worker.DropTable.locked_pos == -1 then
      Worker.DropTable.locked_pos = self.table_pos
    else
      Worker.DropTable.locked_pos = -1
    end
  elseif Buttons.Square:pressed() then
  elseif Buttons.Up:pressed() then
    self:adjustTablePos(-1)
  elseif Buttons.Down:pressed() then
    self:adjustTablePos(1)
  elseif Buttons.Left:pressed() then
    self:adjustTablePos(-10)
  elseif Buttons.Right:pressed() then
    self:adjustTablePos(10)
  end
  return false
end

return Menu
