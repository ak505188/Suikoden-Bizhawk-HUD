local Drawer = require "controllers.drawer"
local RNGLib = require "lib.RNG"
local Buttons = require "lib.Buttons"
local Address = require "lib.Address"
local RNGMonitor = require "monitors.RNG_Monitor"
local MenuProperties = require "menus.Properties"

local Menu = {
  properties = {
    type = MenuProperties.MENU_TYPES.custom,
    name = 'RNG_RESET_MENU',
    control = MenuProperties.CONTROL_TYPES.buttons
  }
}

function Menu:init()
  local eventID = memory.read_u8(Address.EVENT_ID)
  self.initRNG = RNGMonitor.RNG
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

-- TODO: Maybe add flag to not create table in RNGMonitor:setRNG
-- Not sure if possible
function Menu:run()
  if Buttons.Cross:pressed() then
    RNGMonitor.StartingRNG = RNGMonitor.RNG
    RNGMonitor.RNGIndex = 0
    RNGMonitor:setRNG()
    return true
  elseif Buttons.Square:pressed() then
    RNGMonitor:setRNG(self.initRNG)
    RNGMonitor:switchTable()
    return true
  elseif Buttons.Circle:pressed() then
    RNGMonitor:setRNG(self.resetData:getRandomRNG())
  elseif Buttons.Up:pressed() then
    RNGMonitor:setRNG(RNGMonitor.RNG + 1)
  elseif Buttons.Down:pressed() then
    RNGMonitor:setRNG(RNGMonitor.RNG - 1)
  end
  return false
end

return Menu
