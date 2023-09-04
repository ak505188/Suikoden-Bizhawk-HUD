local Monitors = require "controllers.monitors"
local Drawer = require "controllers.drawer"
local MenuController = require "menus.MenuController"

-- This is required due to a circular dependancy.
-- RNG_Monitor require MenuController so it can open RNG_Reset_Menu
MenuController:init(Monitors)

local ModuleManager = require "modules.Manager"
local RNG_Module = require "modules.RNG.module"
local Battles_Module = require "modules.Battles.module"

ModuleManager:addModule(Battles_Module)
ModuleManager:addModule(RNG_Module)

local function draw()
  local opts = Monitors:draw()
  ModuleManager:draw(opts)
end

while true do
  emu.frameadvance()
  -- if (client.ispaused()) then MenuController:run() end
  Monitors:run()
  ModuleManager:run()

  Drawer:clear()
  draw()

  emu.yield()
  if client.ispaused() then
    MenuController:open()
    Monitors:draw()
  else
    MenuController:onClose()
  end
end
