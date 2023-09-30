local Drawer = require "controllers.drawer"
local Worker = require "modules.Battles.worker"
local MenuProperties = require "menus.Properties"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local Utils = require "lib.Utils"

local AreaSelectionMenu = BaseMenu:new({
  properties = {
    type = MenuProperties.TYPES.module,
    name = 'BATTLE_HANDLER_MENU'
  },
})

-- This is needed because it inherits the module menus init otherwise. It then resets the table position
function AreaSelectionMenu:init() end

function AreaSelectionMenu:draw()
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
end

function AreaSelectionMenu:run()
  local customState = Worker.StateHandler:getCustomState()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
  elseif Buttons.Triangle:pressed() then
  elseif Buttons.Square:pressed() then
  elseif Buttons.Down:pressed() then
  elseif Buttons.Up:pressed() then
  elseif Buttons.Left:pressed() then
  elseif Buttons.Right:pressed() then
  end
  return false
end

return AreaSelectionMenu
