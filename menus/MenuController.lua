local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local ModuleManager = require "modules.Manager"
local ModuleMenu = require "modules.Menu"

local MenuController = {
  stack = {},
  current = {},
  onCloseDone = true
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

function MenuController:onClose()
  if self.onCloseDone == false then
    self.stack = {}
    self.current = {}
    ModuleManager:onMenuClose()
  end
end

-- Perhaps should have methods open and push, and get rid of onclose
-- open will work the same as before + initialize stack/current/other variables
-- push will add a menu to the stack without clearing everything
-- already have a push though, so different name?

function MenuController:open(menu)
  client.pause()
  emu.yield()
  if menu then
    self:push(menu)
  else
    local currentModule = ModuleManager:getCurrent()
    local moduleMenu = currentModule.Menu;
    moduleMenu:init()
    self:push(moduleMenu)
  end
  self:run()
end

function MenuController:run()
  while client.ispaused() do
    emu.yield()
    Drawer:clear()
    Buttons:update()

    self:draw()

    local worker = ModuleManager:getCurrent().Worker
    worker:run()
    worker:draw()

    ModuleMenu:draw()
    local menuFinished = ModuleMenu:run()

    if not menuFinished then
      local currentMenu = self:getCurrentMenu()
      currentMenu:draw()
      currentMenu:run()
    end

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
  return self.monitors:draw()
end

return MenuController

-- StackMenuAPI
-- Will be defined within module as its own structure / class attached to the Module
-- Attach dependencies with initialization in module. Part of Module
-- Methods:
-- draw()
-- close()
-- run/poll or onButton?
