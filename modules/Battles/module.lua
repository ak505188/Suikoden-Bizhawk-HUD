local Menu = require "modules.Battles.menus.menu"
local Worker = require "modules.Battles.worker"

local Battles_Module = {
  Name = "Battles",
  Menu = Menu,
  Worker = Worker,
  Settings = {
    RunInBackground = false
  }
}

return Battles_Module
