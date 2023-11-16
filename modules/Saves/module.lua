local Menu = require "modules.Saves.menus.menu"
local Worker = require "modules.Saves.worker"

local Saves_Module = {
  Name = "Saves",
  Menu = Menu,
  Worker = Worker
}

return Saves_Module
