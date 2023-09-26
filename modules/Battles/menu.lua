local Buttons = require "lib.Buttons"
local Worker = require "modules.Battles.worker"
local Drawer = require "controllers.drawer"
local MenuProperties = require "menus.Properties"
local MenuController = require "menus.MenuController"
local Utils = require "lib.Utils"

local CustomStateMenu = {
  properties = {
    type = MenuProperties.TYPES.module,
    name = 'BATTLE_HANDLER_MENU'
  },
}

function CustomStateMenu:init() end

function CustomStateMenu:draw()
  Drawer:draw({
    "Area",
    "Champ Rune",
    "Champ Val",
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

function CustomStateMenu:run() end

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
    "□: Customize",
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
  -- this isn't actually accurate, because there can be hidden battles
  -- want this to go to index of first valid battle
  self.worker_table_position = self:getAdjustedTablePosition(0, Worker.TablePosition)
end

function Menu:getAdjustedTablePosition(amount, pos)
  if Worker:getTable() == nil then return end
  pos = pos or self.worker_table_position

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

-- bug: going up puts you at top of list
function Menu:adjustTablePosition(amount)
  self.worker_table_position = self:getAdjustedTablePosition(amount)
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
    Worker:jumpToBattle(self.worker_table_position)
  elseif Buttons.Square:pressed() then
    MenuController:open(CustomStateMenu)
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
