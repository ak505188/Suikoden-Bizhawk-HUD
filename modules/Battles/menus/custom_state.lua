local Drawer = require "controllers.drawer"
local Worker = require "modules.Battles.worker"
local MenuProperties = require "menus.Properties"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"

local CustomStateMenu = BaseMenu:new({
  properties = {
    type = MenuProperties.TYPES.module,
    name = 'BATTLE_HANDLER_MENU'
  },
})

-- This is needed because it inherits the module menus init otherwise. It then resets the table position
function CustomStateMenu:init() end

function CustomStateMenu:draw()
  Drawer:draw({
    "O: Back",
    "Area",
    "Champ Rune",
    "Champ Val",
  }, Drawer.anchors.TOP_RIGHT)
  local options = {
    cursor = self.cursor,
    table_position = self.table_position
  }
  Worker:draw(options)
end

function CustomStateMenu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
    Worker:jumpToBattle(self.table_position)
  end
  return false
end

return CustomStateMenu
