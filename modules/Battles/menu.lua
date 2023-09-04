local Buttons = require "lib.Buttons"
local Worker = require "modules.Battles.worker"
local Drawer = require "controllers.drawer"

local Menu = {
  CursorPos = 1,

}

function Menu:draw()
  Drawer:draw({
    "X: Go to Battle",
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
  }, Drawer.anchors.TOP_RIGHT)
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
