local Buttons = require "lib.Buttons"
local ListMenuBuilder = require "menus.Builders.List"
local StatsMenu = require "modules.Toolbox.Tools.CharacterEditor.StatsMenu"

local function SelectionMenu(character)
  local list = {
    'Stats',
    'Inventory',
    'Weapon & Rune',
    'Unknowns',
  }
  local options = {
    name = string.format("%s Editor", character.Name),
  }
  local menu = ListMenuBuilder:new(list, options)
  menu.character = character

  function menu:run()
    self:adjustHandler()
    if Buttons.Cross:pressed() then
      local selection = self.list[self.pos]
      print(selection)
      if selection == self.list[1] then
        local stats_menu = StatsMenu(self.character)
        self:openMenu(stats_menu)
      elseif selection == self.list[2] then
      elseif selection == self.list[3] then
      elseif selection == self.list[4] then
      end
    elseif Buttons.Circle:pressed() then
      return true
    end
    return false
  end

  return menu
end

return SelectionMenu
