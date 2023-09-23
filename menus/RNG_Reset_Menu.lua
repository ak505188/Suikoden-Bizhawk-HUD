local Drawer = require "controllers.drawer"
local RNGLib = require "lib.RNG"
local Buttons = require "lib.Buttons"
local Address = require "lib.Address"
local RNGMonitor = require "monitors.RNG_Monitor"
local MenuProperties = require "menus.Properties"

local Menu = {
  properties = {
    type = MenuProperties.TYPES.custom
  }
}

function Menu:init()
  local eventID = memory.read_u8(Address.EVENT_ID)
  self.resetData = RNGLib.GetResetData(eventID)
end

function Menu:draw()
  Drawer:draw({
    "Unknown RNG, assuming RNG Reset",
    "Event:" .. self.resetData.name,
    string.format("RNG: %x", RNGMonitor.RNG),
    "X: Continue",
    "O: Reset",
    "Sq: Was Load State",
    "Up: Increase RNG Value",
    "Down: Decrease RNG Value"
  }, Drawer.anchors.TOP_RIGHT)
end

-- Currently broken in a way, pressing X won't exit menu
function Menu:run()
  if Buttons.Cross:pressed() then
    RNGMonitor.StartingRNG = RNGMonitor.RNG
    RNGMonitor.RNGIndex = 0
    RNGMonitor:setRNG()
    return true
  elseif Buttons.Square:pressed() then
    RNGMonitor:switchTable()
    return true
  elseif Buttons.Circle:pressed() then
    RNGMonitor.RNG = self.resetData:getRandomRNG()
  elseif Buttons.Up:pressed() then
    RNGMonitor.RNG = RNGMonitor.RNG + 1
  elseif Buttons.Down:pressed() then
    RNGMonitor.RNG = RNGMonitor.RNG - 1
  end
  return false
end

return Menu
