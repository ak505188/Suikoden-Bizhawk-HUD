local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local ModuleManager = require "modules.Manager"
local ModuleMenu = require "modules.Menu"

local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.RNG_Monitor"

local MenuController = {
  stack = {},
  current = {},
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

-- Module switching and drawing should probably be part of the worker's menu function
-- Doesn't make sense to have it in here, as it forces all menus to have it
-- RNGResetMenu doesn't care about modules
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
  RNGMonitor:draw()
  StateMonitor:draw()
eng

return MenuController

-- StackMenuAPI
-- Will be defined within module as its own structure / class attached to the Module
-- Attach dependencies with initialization in module. Part of Module
-- Methods:
-- draw()
-- close()
-- run/poll or onButton?


--[[
Responsibilities of MenuController:
  runs when paused

  needs to handle open/close properly:
    probably inits on open with self.open = true sort of thing
    in run check if not paused and self.open = true, handle onclose here

  how do we handle modulemanager menu?
    perhaps tie it to worker?
    or have property in menu/menucontroller, worker or custom
    and if custom dont run modulemanager menu

  how do we handle monitor drawing?
    this should always be done
    guess just part of menucontroller:draw?
    can maybe add a property to menu to pass that can disable it
]]--
