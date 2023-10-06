local Drawer = require "controllers.drawer"
local Worker = require "modules.Battles.worker"
local MenuProperties = require "menus.Properties"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local Utils = require "lib.Utils"
local AreasWithRandomBattlesList = require "lib.Lists.Areas.Areas_Random"

local AreaSelectionMenu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'BATTLE_HANDLER_MENU',
    control = MenuProperties.CONTROL_TYPES.scrolling_cursor,
  },
  options = Utils.cloneTable(AreasWithRandomBattlesList),
})

function AreaSelectionMenu:init()
  self.pos = 1
end

function AreaSelectionMenu:draw()
  local state_handler = Worker.StateHandler
  local state_handler_custom_state = state_handler:getCustomState()
  local custom_on = state_handler.use_custom and "Y" or "N"
  local current_area = state_handler.custom_state.AreaName
  local party_level = state_handler_custom_state.PartyLevel
  local champion_on = state_handler_custom_state.IsChampion and "Y" or "N"
  Drawer:draw({
    "X: Select Area",
    "O: Back",
    "",
    string.format("%s", current_area),
    string.format("CS:%s CR:%s PL:%d", custom_on, champion_on, party_level)
  }, Drawer.anchors.TOP_RIGHT)

  local i = 0
  local areaDrawTable = {}
  while i < 10 and i + self.pos <= #self.options do
    table.insert(areaDrawTable, self.options[self.pos+ i])
    i = i + 1
  end

  areaDrawTable[1] = string.format("> %s", areaDrawTable[1])
  Drawer:draw(areaDrawTable, Drawer.anchors.TOP_LEFT)
end

function AreaSelectionMenu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
    Worker.StateHandler:updateCustomStateArea(self.options[self.pos])
  elseif Buttons.Down:pressed() then
    self:adjustCursor(1)
  elseif Buttons.Up:pressed() then
    self:adjustCursor(-1)
  elseif Buttons.Left:pressed() then
    self:adjustCursor(-10)
  elseif Buttons.Right:pressed() then
    self:adjustCursor(10)
  end
  return false
end

function AreaSelectionMenu:adjustCursor(amount)
  local new_cursor = self.pos + amount
  if new_cursor < 1 then self.pos = 1
  elseif new_cursor > #self.options then self.pos = #self.options
  else self.pos = new_cursor end
end

return AreaSelectionMenu
