local Buttons = require "lib.Buttons"
local Worker = require "modules.Battles.worker"
local Drawer = require "controllers.drawer"
local MenuProperties = require "menus.Properties"

local Menu = {
  properties = {
    type = MenuProperties.TYPES.module,
    name = 'BATTLE_HANDLER_MENU'
  },
  cursor_position = 1,
}

function Menu:draw()
  Drawer:draw({
    "X: Go to Battle",
    "O: Exit Menu",
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
  }, Drawer.anchors.TOP_RIGHT)
  if Worker:shouldDraw() then
    local options = {
      cursor = self.cursor_position,
      table_position = self.worker_table_position
    }
    local drawData = Worker:genDrawData(options)
    Drawer:draw(drawData.Enemies, Drawer.anchors.BOTTOM_LEFT, true)
    Drawer:draw({ drawData.Area }, Drawer.anchors.TOP_LEFT, nil, true)
    Drawer:draw(drawData.Battles, Drawer.anchors.TOP_LEFT)
  end
end

function Menu:init()
  self.cursor_position = 1
  self.worker_table_position = Worker.TablePosition
end


-- This doesn't match up properly due to skipped battles
function Menu:adjustTablePosition(amount)
  local new_pos = self.worker_table_position + amount
  if new_pos < 1 then
    new_pos = 1
  elseif new_pos > #Worker:getTable() then
    new_pos = #Worker:getTable()
  end
  self.worker_table_position = new_pos
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
    Worker:jumpToBattle(self.worker_table_position)
  elseif Buttons.Down:pressed() then
    self:adjustTablePosition(1)
  elseif Buttons.Up:pressed() then
    self:adjustTablePosition(-1)
  elseif Buttons.Left:pressed() then
    self:adjustTablePosition(-10)
  elseif Buttons.Right:pressed() then
    self:adjustTablePosition(10)
  end
  return false
end

return Menu
