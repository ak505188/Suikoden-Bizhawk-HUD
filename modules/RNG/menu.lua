local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local Worker = require "modules.RNG.worker"
local Modes = require "modules.RNG.modes"
local MenuProperties = require "menus.Properties"
local ListSelectionMenuBuilder = require "menus.Builders.List"

local ModeSelectionMenu = ListSelectionMenuBuilder:new(Modes.List)

local Menu = {
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'RNG_HANDLER_MENU',
    control = MenuProperties.CONTROL_TYPES.buttons,
  }
}

function Menu:draw()
  local draw_table = {
    "Tr: Select Mode",
    "O: Back",
    "Do: RNGIndex -1",
    "Le: RNGIndex -25",
    "Up: RNGIndex +1",
    "Ri: RNGIndex +25",
  }
  if Worker.submodules[Worker.mode] then
    table.insert(draw_table, 1, string.format("Sq: %s Settings", Worker.mode))
  end
  Drawer:draw(draw_table, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function Menu:init() end

function Menu:run()
  if Buttons.Triangle:pressed() then
    local new_mode = self:openMenu(ModeSelectionMenu)
    if new_mode then Worker.mode = new_mode end
  elseif Buttons.Square:pressed() then
    if Worker.submodules[Worker.mode] then
      local submodule = Worker.submodules[Worker.mode]
      self:openMenu(submodule.Menu)
    end
  elseif Buttons.Down:pressed() then
    Worker:adjustIndex(-1)
  elseif Buttons.Up:pressed() then
    Worker:adjustIndex(1)
  elseif Buttons.Left:pressed() then
    Worker:adjustIndex(-25)
  elseif Buttons.Right:pressed() then
    Worker:adjustIndex(25)
  elseif Buttons.Circle:pressed() then
    return true
  end
  return false
end

return Menu
