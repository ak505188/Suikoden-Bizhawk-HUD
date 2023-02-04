local Buttons = require "lib.Buttons"

local MenuController = {
  stack = {},
  current = {},
}

function MenuController:init(moduleManager)
  self.moduleManager = moduleManager
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
    local currentModule = self.moduleManager:getCurrentModule()
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

    local currentMenu = self:getCurrentMenu()
    currentMenu:draw()
    currentMenu:run()

    local currentModule = self.moduleManager:getCurrentModule()
    currentModule:run()
    currentModule:draw()
  end
  -- Probably want to pass this down
end

function MenuController:draw() end

return MenuController

-- StackMenuAPI
-- Will be defined within module as its own structure / class attached to the Module
-- Attach dependencies with initialization in module. Part of Module
-- Methods:
-- draw()
-- close()
-- run/poll or onButton?
