local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"

RNGMonitor:init(StateMonitor)

while true do
  -- Controls:run()
  StateMonitor:run()
  RNGMonitor:runPreFrame()
  emu.frameadvance()
  RNGMonitor:runPostFrame()
  RNGMonitor:draw()
end
