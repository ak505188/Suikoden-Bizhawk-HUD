local Utils = require "lib.Utils"
local Buttons = require "lib.Buttons"
local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.StateMonitor"

local Menu = {}

function Menu.draw()
  local opts = {
    x = 0,
    y = 0,
    gap = 16,
    anchor = "topright"
  }
  return Utils.drawTable({
    "X: Go to Battle",
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
  }, opts)
end

function Menu:run()
  if Buttons.Cross:pressed() then
  elseif Buttons.Down:pressed() then
  elseif Buttons.Up:pressed() then
  elseif Buttons.Left:pressed() then
  elseif Buttons.Right:pressed() then
  end
end

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
