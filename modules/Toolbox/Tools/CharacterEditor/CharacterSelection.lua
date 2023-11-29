local Buttons = require "lib.Buttons"
local MenuProperties = require "menus.Properties"
local CombatCharacters = require "lib.Characters.CombatCharacters"
local ScrollingListMenuBuilder = require "menus.Builders.ScrollingList"
local DataSelectionMenu = require "modules.Toolbox.Tools.CharacterEditor.DataSelectionMenu"

local Characters = CombatCharacters.Characters
local CharacterNamesList = CombatCharacters.NamesList

local Menu = ScrollingListMenuBuilder:new(CharacterNamesList, {
  type = MenuProperties.MENU_TYPES.module,
  name = 'Character Editor Character Selection',
})

function Menu:run()
  self:adjustHandler()
  if Buttons.Cross:pressed() then
    local character_name = self.list[self.pos]
    local character = Characters[character_name]
    local selection_menu = DataSelectionMenu(character)
    self:openMenu(selection_menu)
  elseif Buttons.Circle:pressed() then
    return true
  end
  return false
end

return Menu
