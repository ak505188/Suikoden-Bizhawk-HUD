local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local Utils = require "lib.Utils"
local BaseMenu = require "menus.Base"
local Worker = require "modules.Drops.worker"
local DropFilterMenu = require "modules.Drops.menus.drop_filter"
local MenuProperties = require "menus.Properties"
local MenuController = require "menus.MenuController"

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'DROPS_MENU',
    control = MenuProperties.CONTROL_TYPES.buttons,
  }
})

function Menu:draw()
  local drawtable = {
    "O: Back",
  }
  if Worker.DropTable ~= nil then
    drawtable = Utils.concatTables(drawtable, {
      "[]: Filter Drops",
      string.format("^: %s Table Position", Worker.DropTable.locked_pos == -1 and "Lock" or "Unlock"),
      "Up: Scroll 1 Up",
      "Do: Scroll 1 Down",
      "Le: Scroll 10 Up",
      "Ri: Scroll 10 Down",
      "Se: Print Battle to Console"
    })
  end
  Drawer:draw(drawtable, Drawer.anchors.TOP_RIGHT)
  Worker:draw(self.table_pos)
end

function Menu:init()
  if Worker.DropTable == nil then
    self.table_pos = 1
  elseif Worker.DropTable.locked_pos == -1 then
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
  elseif Worker.DropTable == nil then
    return false
  elseif Buttons.Triangle:pressed() then
    if Worker.DropTable.locked_pos == -1 then
      Worker.DropTable.locked_pos = self.table_pos
    else
      Worker.DropTable.locked_pos = -1
    end
  elseif Buttons.Square:pressed() then
    local drop_filter_menu = self:new(DropFilterMenu)
    MenuController:open(drop_filter_menu)
  elseif Buttons.Up:pressed() then
    self:adjustTablePos(-1)
  elseif Buttons.Down:pressed() then
    self:adjustTablePos(1)
  elseif Buttons.Left:pressed() then
    self:adjustTablePos(-10)
  elseif Buttons.Right:pressed() then
    self:adjustTablePos(10)
  elseif Buttons.Select:pressed() then
    print(Utils.tableToStr(Worker.State.Battle))
  end
  return false
end

return Menu
