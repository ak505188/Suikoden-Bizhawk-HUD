local Utils = require "lib.Utils"
local Buttons = require "lib.Buttons"
local Worker = require "modules.Battles.worker"

local Menu = {
  CursorPos = 1,

}

function Menu:draw(drawOpts)
  local opts = {
    x = drawOpts.x or 0,
    y = drawOpts.y or 0,
    gap = drawOpts.gap or 16,
    anchor = drawOpts.anchor or "topright"
  }
  return Utils.drawTable({
    "X: Go to Battle",
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
  }, opts)
end

function Menu:init()
  self.CursorPos = 1
  self.WorkerOriginalTablePos = Worker.TablePosition
end

function Menu:run()
  if Buttons.Cross:pressed() then
  elseif Buttons.Down:pressed() then
    Worker:adjustPos(-1)
  elseif Buttons.Up:pressed() then
    Worker:adjustPos(1)
  elseif Buttons.Left:pressed() then
    Worker:adjustPos(-10)
  elseif Buttons.Right:pressed() then
    Worker:adjustPos(10)
  end
end

return Menu
