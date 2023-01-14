local Buttons = require "lib.Buttons"

local MenuController = {
  stack = {},
  current = {},
  open = false,
}

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
  -- Probably want to pass this down
  Buttons:update()
  if not self.open then return end
end

function MenuController:draw()
  local x = 0
  local y = 0
  local anchor = "topright"
  -- Should Draw

end

return MenuController

-- StackMenuAPI
-- Will be defined within module as its own structure / class attached to the Module
-- Attach dependencies with initialization in module. Part of Module
-- Methods:
-- draw()
-- close()
-- run/poll or onButton?
