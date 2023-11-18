local Menu = require "modules.RoomInfo.menu"
local Worker = require "modules.RoomInfo.worker"

local RoomInfo_Module = {
  Name = "RoomInfo",
  Menu = Menu,
  Worker = Worker,
  Settings = {
    RunInBackground = false
  }
}

return RoomInfo_Module
