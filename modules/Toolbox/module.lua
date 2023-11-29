local Menu = require "modules.Toolbox.menu"
local Worker = require "modules.Toolbox.worker"

local Toolbox_Module = {
  Name = "Toolbox",
  Menu = Menu,
  Worker = Worker,
  Settings = {
    RunInBackground = false
  }
}


return Toolbox_Module
