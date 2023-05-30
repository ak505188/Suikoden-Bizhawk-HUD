local Buttons = require "lib.Buttons"

local MenuController = {
  stack = {},
}

function MenuController:registerModuleManager(ModuleManager)
  self.ModuleManager = ModuleManager
end

function MenuController:open(menu)
  if not client.ispaused() then client.pause() end
  table.insert(self.stack, menu)
end

function MenuController:pop()
  return table.remove(self.stack)
end

function MenuController:run()
  emu.yield()
  while client.ispaused() do
    emu.yield()
    if #self.stack < 1 then
      self:open(self.ModuleManager:getCurrent().Menu)
    end
    self:current():draw()
    local shouldKeepMenuOpen = self:current():run()
    if not shouldKeepMenuOpen then
      self:pop()
      if #self.stack < 1 then
        client.unpause()
      end
    end
  end
end

function MenuController:current()
  return self.stack[#self.stack]
end

return MenuController
