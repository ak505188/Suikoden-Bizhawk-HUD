local Menu = require "modules.RNG.submodules.Chinchironin.menu"
local Worker = require "modules.RNG.submodules.Chinchironin.worker"

local Chinchironin_Submodule = {
  Name = "Chinchironin",
  Menu = Menu,
  Worker = Worker,
  Settings = {
    RunInBackground = false
  }
}

return Chinchironin_Submodule
