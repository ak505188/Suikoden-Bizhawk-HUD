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

function MenuController:openMenu()
  local menuBtn = Buttons.R2


end

return MenuController
