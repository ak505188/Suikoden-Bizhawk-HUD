local Menu = require "modules.RNG.menu"
local Worker = require "modules.RNG.worker"

local RNG_Module = {
  Name = "RNG",
  Menu = Menu,
  Worker = Worker,
  Settings = {
    RunInBackground = false
  }
}

return RNG_Module
