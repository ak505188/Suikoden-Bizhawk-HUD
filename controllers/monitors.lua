function MonitorsController:init()
  for _,monitor in ipairs(self.monitors) do
    monitor:init()
  end
end

function MonitorsController:run()
  local RNGMonitorEvent = self.RNG:run()
  if RNGMonitorEvent then
    RNGResetMenu:init()
    MenuController:open(RNGResetMenu)
  end

  self.State:run()
end

function MonitorsController:draw()
  for _,monitor in ipairs(self.monitors) do
    monitor:draw()
  end
end

return MonitorsController
