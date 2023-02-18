local Menu = require "modules.Battles.menu"

local Battles_Module = {
  Name = "Battles",
  Menu = Menu
}

function Battles_Module:run()
  local stateChanged = stateChanged = self:updateState()

  -- What does this line do?
  if not next(self.State) then return end

  if self.RNG_HUD.State.RNG_CHANGED or stateChanged then
    self:updateTablePosition()
  end

end

function Battles_Module:draw(opts) return opts end

return Battles_Module
