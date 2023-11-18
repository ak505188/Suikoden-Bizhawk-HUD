local ModuleManager = {
  modules = {},
  modulePositionsByName = {},
  currentModule = nil
}

function ModuleManager:addModule(module)
  module.Worker:init()
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
  self:getCurrent().Worker:onChange()
end

function ModuleManager:prevModule()
  if #self.modules > 1 then
    self.currentModule = self.currentModule - 1
    if self.currentModule == 0 then self.currentModule = #self.modules end
  end
  self:getCurrent().Worker:onChange()
end

function ModuleManager:getCurrent()
  return self.modules[self.currentModule]
end

function ModuleManager:draw(opts)
  return self:getCurrent().Worker:draw(opts)
end

function ModuleManager:run()
  local current_module = self:getCurrent()
  current_module.Worker:run()

  -- Run background modules
  for _, module in ipairs(self.modules) do
    if module.Name ~= current_module.Name and module.Settings.RunInBackground then
      module.Worker:run()
    end
  end

end

return ModuleManager
