local RNGMonitor = require "monitors.RNG_Monitor"
local Drawer = require "controllers.drawer"
local Chinchironin = require "lib.Chinchironin"
local ChinchironinTableBuilder = require "modules.RNG.submodules.Chinchironin.ChinchironinTable"

local Worker = {
  Player = Chinchironin.PLAYERS.Tai_Ho,
  FramesToAdvance = 203,
  ChinchironinTables = {},
  ChinchironinTableKey = '',
  RNG_Modifier = 0,
}

function Worker:run()
  self.ChinchironinTableKey = self:generateChinchironinTableKey()
  local chinchironin_table = self:getChinchironinTable()
  if chinchironin_table == nil then
    chinchironin_table = ChinchironinTableBuilder(self.Player, RNGMonitor:getTable(), self.RNG_Modifier, self.FramesToAdvance)
    self.ChinchironinTables[self.ChinchironinTableKey] = chinchironin_table
  end
  chinchironin_table:generateRolls()
end

function Worker:getChinchironinTable()
  local chinchironin_table = self.ChinchironinTables[self.ChinchironinTableKey]
  return chinchironin_table
end

function Worker:draw()
  local chinchironin_table = self:getChinchironinTable()
  if not chinchironin_table then return end
  local info_str = string.format(
    "%s %d/%d",
    self.Player,
    chinchironin_table.Size,
    chinchironin_table.RNG_table:getSize())
  Drawer:draw({ info_str }, Drawer.anchors.TOP_LEFT, nil, true)

  if chinchironin_table.Size == 0 then return end

  local labels = " Index Roll Wait"
  local rng_index = RNGMonitor:getIndex()
  local rolls_table = self:rollsToStringTable(rng_index, 15)

  Drawer:draw({ labels }, Drawer.anchors.TOP_LEFT, nil, true)
  Drawer:draw(rolls_table, Drawer.anchors.TOP_LEFT)
end

function Worker:rollsToStringTable(rng_index, length)
  local str_table = {}
  local rolls_slice = self:getChinchironinTable():slice(rng_index, length)
  for index,roll in ipairs(rolls_slice) do
    local chinchironin_str = string.format("%6d  %s %4d", rng_index + index - 1, roll.roll, roll.wait)
    table.insert(str_table, chinchironin_str)
  end
  return str_table
end

function Worker:generateChinchironinTableKey()
  return string.format(
    "%s_%x_%x_%d",
    self.Player,
    RNGMonitor.StartingRNG,
    self.RNG_Modifier,
    self.FramesToAdvance)
end

return Worker
