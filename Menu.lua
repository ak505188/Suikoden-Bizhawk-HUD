local MenuController = {}
MenuController.stack = {
  stack = {},
}

function MenuController:push(menu)
  self.stack.insert(menu)
end

function MenuController:pop()
  return self.stack.remove()
end
