local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local ModuleManager = require "modules.Manager"
local MenuProperties = require "menus.Properties"
local ListMenuBuilder = require "menus.Builders.List"

local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

local MenuController = {
  stack = {},
  onCloseDone = true
}

function MenuController:push(menu)
  table.insert(self.stack, menu)
end

function MenuController:pop()
  return table.remove(self.stack)
end

function MenuController:getCurrentMenu()
  return self.stack[#self.stack]
end

function MenuController:open(menu)
  client.pause()
  emu.yield()
  menu = menu or ModuleManager:getCurrent().Menu
  function menu:openMenu(m)
    return MenuController:open(m)
  end
  menu:init()
  self:push(menu)
  local _,result = self:run()
  return result
end

-- Module switching and drawing should probably be part of the worker's menu function
-- Doesn't make sense to have it in here, as it forces all menus to have it
-- RNGResetMenu doesn't care about modules

function MenuController:switchToModule(module_name)
  ModuleManager:switchToModule(module_name)
  self.stack = {}
  local currentMenu = ModuleManager:getCurrent().Menu
  currentMenu:init()
  self:open(currentMenu)
end

function MenuController:run()
  local ModulesList = ModuleManager:getModuleNames()
  local ModuleSelectionMenu = ListMenuBuilder:new(ModulesList, { name = 'Module Selection Menu', type = MenuProperties.MENU_TYPES.module_menu })

  while client.ispaused() do
    emu.yield()
    Drawer:clear()

    StateMonitor:run()
    RNGMonitor:run()

    Buttons:update()

    self:draw()

    local currentMenu = self:getCurrentMenu()
    local menu_type = currentMenu.properties.type

    if menu_type == MenuProperties.MENU_TYPES.module then
      if Buttons.Select:pressed() then
        self:open(ModuleSelectionMenu)
      end

      local worker = ModuleManager:getCurrent().Worker
      worker:run()
    end

    local menu_finished, menu_result = currentMenu:run()
    currentMenu:draw()

    if menu_finished then
      self:pop()
    end

    if menu_type == MenuProperties.MENU_TYPES.module_menu then
      if menu_result then
        self:switchToModule(menu_result)
      end
    end

    if menu_finished then
      if #self.stack == 0 then
        client.unpause()
      end
      return menu_finished,menu_result
    end

    while not client.ispaused() and #self.stack > 0 do
      self:pop()
    end
  end
end

function MenuController:draw()
  local module_draw_table = {
    "Select: Switch Module",
  }

  if self:getCurrentMenu().properties.type == MenuProperties.MENU_TYPES.module then
    Drawer:draw(module_draw_table, Drawer.anchors.TOP_RIGHT)
  end
  RNGMonitor:draw()
  StateMonitor:draw()
end

return MenuController

