local Buttons = require "lib.Buttons"
local Worker = require "modules.Saves.worker"
local Drawer = require "controllers.drawer"
local MenuProperties = require "menus.Properties"
local MenuController = require "menus.MenuController"
local BaseMenu = require "menus.Base"
local LoadMenu = require "modules.Saves.menus.load_menu"
local lib = require "modules.Saves.lib"

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'SAVES_MENU'
  },
})

function Menu:draw()
  Worker:draw()
  local draw_table = {
    "Sq: Open Load State Menu",
    "X: Save State",
  }
  Drawer:draw(draw_table, Drawer.anchors.TOP_RIGHT)
end

function Menu:init()
  lib.setupSaveDirectories()
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Square:pressed() then
    local load_menu = self:new(LoadMenu)
    MenuController:open(load_menu)
    return false
  elseif Buttons.Cross:pressed() then
    self:saveState()
  end
  return false
end

function Menu:saveState()
  local path = lib.getSavePath(lib.getSaveName())
  savestate.save(path)
end

return Menu
