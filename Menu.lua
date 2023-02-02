local Buttons = require "lib.Buttons"

local MenuController = {
  stack = {},
  current = {},
}

function MenuController:init(moduleManager)
  self.moduleManager = moduleManager
end

function MenuController:push(menu)
  self.stack.insert(menu)
end

function MenuController:pop()
  return self.stack.remove()
end

function MenuController:openMenu(menu)
  self.push(menu)
  self.open = false
end

function MenuController:run()
  while client.ispaused() do
    emu.yield()
    gui.cleartext()
    Buttons:update()
    local currentModule = self.moduleManager:getCurrentModule()
    currentModule.Menu.draw()
    currentModule.Menu:run()
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
