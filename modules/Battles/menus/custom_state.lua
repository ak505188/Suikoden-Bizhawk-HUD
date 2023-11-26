local Drawer = require "controllers.drawer"
local Worker = require "modules.Battles.worker"
local MenuProperties = require "menus.Properties"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local MenuController = require "menus.MenuController"
local AreaSelectionMenu = require "modules.Battles.menus.area_selection"

local CustomStateMenu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'BATTLE_HANDLER_MENU',
    control = MenuProperties.CONTROL_TYPES.buttons
  },
})

function CustomStateMenu:init()
  Worker.StateHandler:initCustomState()
end

function CustomStateMenu:draw()
  local state_handler = Worker.StateHandler
  local state_handler_custom_state = state_handler:getCustomState()
  local custom_on = state_handler.use_custom and "Y" or "N"
  local party_level = state_handler_custom_state.PartyLevel
  local champion_on = state_handler_custom_state.IsChampion and "Y" or "N"
  Drawer:draw({
    "X: Toggle Custom State",
    "O: Back",
    "[]: Switch Area",
    "^: Toggle Champ Rune",
    "Up: Party Lvl +1",
    "Do: Party Lvl -1",
    "Le: Party Lvl -10",
    "Ri: Party Lvl +10",
    "",
    string.format("CS:%s CR:%s PL:%d", custom_on, champion_on, party_level)
  }, Drawer.anchors.TOP_RIGHT)
  local options = {
    cursor = self.cursor,
    table_position = self.table_position
  }
  Worker:draw(options)
end

function CustomStateMenu:run()
  local customState = Worker.StateHandler:getCustomState()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
    Worker.StateHandler:toggleCustomState()
  elseif Buttons.Triangle:pressed() then
    customState.IsChampion = not customState.IsChampion
    Worker.StateHandler:updateCustomState(customState)
  elseif Buttons.Square:pressed() then
    local area_selection_menu = self:new(AreaSelectionMenu)
    MenuController:open(area_selection_menu)
  elseif Buttons.Down:pressed() then
    self.adjustCustomPartyLevel(-1)
  elseif Buttons.Up:pressed() then
    self.adjustCustomPartyLevel(1)
  elseif Buttons.Left:pressed() then
    self.adjustCustomPartyLevel(-10)
  elseif Buttons.Right:pressed() then
    self.adjustCustomPartyLevel(10)
  end
  return false
end

function CustomStateMenu.adjustCustomPartyLevel(amount)
  local custom_state = Worker.StateHandler:getCustomState()
  local party_level = custom_state.PartyLevel + amount
  if party_level > 594 then party_level = 594 end
  if party_level < 1 then party_level = 1 end
  custom_state.PartyLevel = party_level
  Worker.StateHandler:updateCustomState(custom_state)
end

return CustomStateMenu
