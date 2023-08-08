local RNGLib = require "lib.RNG"
local Address = require "lib.Address"
local Buttons = require "lib.Buttons"
local Utils = require "lib.Utils"

local Menu = {}

-- Can't import RNG_Monitor due to circular dependency, so passing it through along with other relevant data.
function Menu:init(RNGMonitor, eventID)
  self.RNGMonitor = RNGMonitor
  self.eventID = eventID
  self.resetData = RNGLib.GetResetData(eventID)
end

function Menu:draw(opts)
  local drawOpts = {
    x = 0,
    y = 96,
    gap = 16,
    anchor = "topleft"
  }
  if opts then
    for k,v in pairs(opts) do
      drawOpts[k] = v
    end
  end
  Utils.drawTable({
    "Unknown RNG, assuming RNG Reset",
    "Event:" .. self.resetData.name,
    string.format("RNG: %x", self.RNGMonitor.RNG),
    "X: Continue",
    "O: Reset",
    "Sq: Was Load State",
    "Up: Increase RNG Value",
    "Down: Decrease RNG Value"
  }, drawOpts)
end

function Menu:run()
  local RNGMonitor = self.RNGMonitor

  if Buttons.Cross:pressed() then
    RNGMonitor.StartingRNG = RNGMonitor.RNG
    RNGMonitor.RNGIndex = 0
    -- memory.write_u32_le(Address.RNG, RNGMonitor.RNG)
    -- RNGMonitor:createNewRNGTable()
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
