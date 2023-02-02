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
end

function ModuleManager:prevModule()
end

function ModuleManager:getCurrentModule()
  return self.modules[self.currentModule]
end

return ModuleManager
