local Menu = require "modules.RNG.submodules.Combat.menu"
local Worker = require "modules.RNG.submodules.Combat.worker"

local Combat_Submodule = {
  Name = "Combat",
  Menu = Menu,
  Worker = Worker,
  Settings = {
    RunInBackground = false
  }
}

return Combat_Submodule
