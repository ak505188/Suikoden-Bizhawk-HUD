local RNG_Monitor = require "monitors.RNG_Monitor"
local Buttons = require "lib.Buttons"
local Utils = require "lib.Utils"

local Menu = {}

function Menu:init(RNG_Monitor, eventName)

end

function Menu:draw()
  local opts = {
    x = 0,
    y = 0,
    gap = 16,
    anchor = "topleft"
  }
  Utils.drawTable({
    "Unknown RNG, assuming RNG Reset",
    "Event:" .. resetData.name,
    string.format("RNG: %x", RNG_Monitor.RNG),
    "X: Continue",
    "O: Reset",
    "Sq: Was Load State",
    "Up: Increase RNG Value",
    "Down: Decrease RNG Value"
  }, opts)
end

function Menu:run()
  if Buttons.Cross:pressed() then
    RNG_Monitor.StartingRNG = RNG_Monitor.RNG
    RNG_Monitor.RNGIndex = 0
    memory.write_u32_le(Address.RNG, RNG_Monitor.RNG)
    RNG_Monitor:createNewRNGTable()
    -- handled = true
  elseif Buttons.Square:pressed() then
    RNG_Monitor.StartingRNG = RNG_Monitor.RNG
    RNG_Monitor.RNGIndex = 0
    RNG_Monitor.RNG_RESET_INCOMING = true
    RNG_Monitor:createNewRNGTable()
    -- handled = true
  elseif Buttons.Circle:pressed() then
    RNG_Monitor.RNG = self.resetData.rng
  elseif Buttons.Up:pressed() then
    RNG_Monitor.RNG = RNG_Monitor.RNG + 1
  elseif Buttons.Down:pressed() then
    RNG_Monitor.RNG = RNG_Monitor.RNG - 1
  end
end

return Menu
