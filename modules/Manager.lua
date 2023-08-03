local ModuleManager = {
  modules = {},
  modulePositionsByName = {},
  currentModule = nil
}

function ModuleManager:addModule(module)
  table.insert(self.modules, module)
  self.modulePositionsByName[module.Name] = #self.modules
  if self.currentModule == nil then
    self.currentModule = #self.modules
  end
end

function ModuleManager:switchToModule(name)
  if self.modulePositionsByName[name] then
    self.currentModule = self.modulePositionsByName[name]
  end
end

function ModuleManager:nextModule()
  if #self.modules > 1 then
    self.currentModule = self.currentModule % #self.modules + 1
  end
  self:getCurrent():onChange()
end

function ModuleManager:prevModule()
  -- TODO: Implement, this is just copy of nextModule
  if #self.modules > 1 then
    self.currentModule = self.currentModule % #self.modules + 1
  end
  self:getCurrent():onChange()
end

function ModuleManager:onMenuClose()
  for _,module in pairs(self.modules) do
    module.Menu:onClose()
  end
end

function ModuleManager:getCurrent()
  return self.modules[self.currentModule]
end

function ModuleManager:draw(opts)
  return self:getCurrent():draw(opts)
end

function ModuleManager:run()
  self:getCurrent():run()
end

return ModuleManager
