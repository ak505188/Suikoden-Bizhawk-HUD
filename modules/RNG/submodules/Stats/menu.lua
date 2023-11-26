local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local CombatCharacters = require "lib.Characters.CombatCharacters"
local MenuProperties = require "menus.Properties"
local MenuBuilders = require "menus.MenuBuilders"
local MenuController = require "menus.MenuController"
local Worker = require "modules.RNG.submodules.Stats.worker"

local CharacterSelectionMenu = MenuBuilders.ScrollingListSelectionMenuBuilder(CombatCharacters.NamesList)

local OptionNames = {
  CHARACTER = "Select Character",
  STATS_TO_SHOW = "Select Stats to Show",
  STARTING_LEVEL = "Adjust Starting Level",
  LEVELS_GAINED = "Adjust Levels Gained",
}

local Options = {
  OptionNames.CHARACTER,
  OptionNames.STATS_TO_SHOW,
  OptionNames.STARTING_LEVEL,
  OptionNames.LEVELS_GAINED,
}

local StatsToShowKeysList = {
  'PWR',
  'SKL',
  'DEF',
  'SPD',
  'MGC',
  'LUK',
  'HP'
}

local Menu = {
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'RNG_HANDLER_MENU',
    control = MenuProperties.CONTROL_TYPES.cursor,
  },
  cursor = 1,
  option = Options[1]
}

function Menu:draw()
  local draw_table = {
    "Select Character",
    "Select Stats to Show",
    string.format("Starting Level: %2d", Worker.StartingLevel),
    string.format("Levels Gained: %2d", Worker.LevelsGained)
  }

  draw_table[self.cursor] = "> " .. draw_table[self.cursor]

  local controls_table = {
    "O: Back"
  }

  if self.option == OptionNames.CHARACTER or self.option == OptionNames.STATS_TO_SHOW then
    table.insert(controls_table, "X: Select")
  else
    table.insert(controls_table, "Left: Decrease")
    table.insert(controls_table, "Right: Increase")
    table.insert(controls_table, "Hold R2: Amount * 10")
  end

  Drawer:draw(draw_table, Drawer.anchors.TOP_RIGHT)
  Drawer:draw(controls_table, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function Menu:init() end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Up:pressed() then
    self:adjustCursor(-1)
  elseif Buttons.Down:pressed() then
    self:adjustCursor(1)

  -- Character Selection
  elseif self.option == OptionNames.CHARACTER then
    if Buttons.Cross:pressed() then
      local character_name = MenuController:open(CharacterSelectionMenu)
      local character = CombatCharacters.Characters[character_name]
      Worker.Character = character
    end

  -- Stats to Show
  elseif self.option == OptionNames.STATS_TO_SHOW then
    if Buttons.Cross:pressed() then
      local toggle_menu = MenuBuilders.ToggleTableMenuBuilder(Worker.StatsToShow, StatsToShowKeysList)
      local stats_to_show = MenuController:open(toggle_menu)
      if stats_to_show then Worker.StatsToShow = stats_to_show end
    end

  -- Adjust Starting Level
  elseif self.option == OptionNames.STARTING_LEVEL or self.option == OptionNames.LEVELS_GAINED then
    local modifier = 1
    local amount = 0
    if Buttons.R2:held() then
      modifier = 10
    end
    if Buttons.Left:pressed() then
      amount = modifier * -1
    elseif Buttons.Right:pressed() then
      amount = modifier * 1
    end
    if amount ~= 0 then
      self:adjustLevels(amount)
    end
  elseif Buttons.Circle:pressed() then
    return true
  end
  return false
end

function Menu:adjustLevels(amount)
  local starting_level = Worker.StartingLevel
  local levels_gained = Worker.LevelsGained
  if self.option == OptionNames.STARTING_LEVEL then
    starting_level = starting_level + amount
    if starting_level < 1 then starting_level = 1 end
    if starting_level > 98 then starting_level = 98 end
    local sum = starting_level + levels_gained
    if sum > 99 then
      starting_level = 99 - levels_gained
    end
    Worker.StartingLevel = starting_level
  elseif self.option == OptionNames.LEVELS_GAINED then
    levels_gained = levels_gained + amount
    if levels_gained < 1 then levels_gained = 1 end
    if levels_gained > 98 then levels_gained = 98 end
    local sum = starting_level + levels_gained
    if sum > 99 then
      levels_gained = 99 - starting_level
    end
    Worker.LevelsGained = levels_gained
  end
end

function Menu:adjustCursor(amount)
  local new_cursor = self.cursor + amount
  if new_cursor < 1 then new_cursor = 1 end
  if new_cursor > #Options then new_cursor = #Options end

  self.cursor = new_cursor
  self.option = Options[new_cursor]
end

return Menu
