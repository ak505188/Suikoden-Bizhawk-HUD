local Buttons = require "lib.Buttons"
local Worker = require "modules.Battles.worker"
local CustomStateMenu = require "modules.Battles.menus.custom_state"
local Drawer = require "controllers.drawer"
local MenuProperties = require "menus.Properties"
local BaseMenu = require "menus.Base"

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'BATTLE_HANDLER_MENU',
  },
  cursor = 1,
})

function Menu:draw()
  Drawer:draw({
    "X: Go to Battle",
    "O: Back",
    "[]: Customize",
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
  }, Drawer.anchors.TOP_RIGHT)
  local options = {
    cursor = self.cursor,
    table_position = self.table_position
  }
  Worker:draw(options)
end

function Menu:init()
  self.cursor = 1
  self.table_position = self:getAdjustedTablePosition(0, Worker.TablePosition)
end

function Menu:getAdjustedTablePosition(amount, pos)
  if Worker:getTable() == nil then return end
  pos = pos or self.table_position

  -- if amount = 0 check if current position is valid and if not find first valid one
  -- can get this behavior by setting it to 1 if invalid battle
  if amount == 0 then
    if Worker:isValidEncounter(pos) then
      return pos
    else
      amount = 1
    end
  end

  local direction = 1
  local tableLength = #Worker:getTable()
  local last_good_pos = pos

  if amount < 0 then
    direction = -1
  end

  if direction == 1 and pos == tableLength - 1 then return pos end
  if direction == -1 and pos == 1 then return pos end

  repeat
    pos = pos + direction
    local isValid = Worker:isValidEncounter(pos)

    if isValid then
      last_good_pos = pos
      amount = amount - direction
    end
    if amount == 0 then
      return pos
    end
  until pos == 1 or pos == tableLength - 1

  return last_good_pos
end

function Menu:adjustTablePosition(amount)
  self.table_position = self:getAdjustedTablePosition(amount)
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
    Worker:jumpToBattle(self.table_position)
  elseif Buttons.Square:pressed() then
    local custom_state_menu = self:new(CustomStateMenu)
    self:openMenu(custom_state_menu)
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
