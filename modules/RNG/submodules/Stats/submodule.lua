local Menu = require "modules.RNG.submodules.Stats.menu"
local Worker = require "modules.RNG.submodules.Stats.worker"

local Stats_Submodule = {
  Name = "Stats",
  Menu = Menu,
  Worker = Worker,
  Settings = {
    RunInBackground = false
  }
}

return Stats_Submodule
