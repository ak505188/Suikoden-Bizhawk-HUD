local Menu = require "modules.Drops.menu"
local Worker = require "modules.Drops.worker"

local Drops_Module = {
  Name = "Drops",
  Menu = Menu,
  Worker = Worker,
  Settings = {
    RunInBackground = false
  }
}

return Drops_Module
