local Buttons = require "lib.Buttons"
local ModuleManager = require "modules.Manager"
local ModuleMenu = require "modules.Menu"
local Utils = require "lib.Utils"

local MenuController = {
  stack = {},
  current = {},
}

function MenuController:init(monitors)
  self.monitors = monitors
end

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
  if menu then
    self:push(menu)
  else
    local currentModule = ModuleManager:getCurrent()
    local moduleMenu = currentModule.Menu;
    self:push(moduleMenu)
  end
  self:run()
end

function MenuController:run()
  while client.ispaused() do
    emu.yield()
    gui.cleartext()
    Buttons:update()

    local monitorModuleDrawOpts = self:draw()

    local currentModule = ModuleManager:getCurrent()
    currentModule:run()
    monitorModuleDrawOpts = currentModule:draw(monitorModuleDrawOpts)

    local menuDrawOpts = ModuleMenu:draw()
    local menuFinished = ModuleMenu:run()

    if not menuFinished then
      local currentMenu = self:getCurrentMenu()
      menuDrawOpts = currentMenu.draw(menuDrawOpts)
      menuFinished = currentMenu:run()
    end

    self:draw()
    if menuFinished then
      self:pop()
      if #self.stack == 0 then
        client.unpause()
      end
    end
  end

  while not client.ispaused() and #self.stack > 0 do
    self:pop()
  end
end

function MenuController:draw()
  local drawOpts = {}
  for _,monitor in pairs(self.monitors) do
    drawOpts = monitor:draw(drawOpts)
  end
  return drawOpts
end

return MenuController

-- StackMenuAPI
-- Will be defined within module as its own structure / class attached to the Module
-- Attach dependencies with initialization in module. Part of Module
-- Methods:
-- draw()
-- close()
-- run/poll or onButton?
