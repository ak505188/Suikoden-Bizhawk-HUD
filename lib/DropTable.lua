local Drawer = require "controllers.drawer"
local RNGMonitor = require "monitors.RNG_Monitor"
local Utils = require "lib.Utils"
local Battle = require "lib.Battle"

local DropTable = {}

function DropTable:new(battle)
  local tbl = {}
  setmetatable(tbl, self)
  self.__index = self
  self.battle = battle
  self.drops = {}
  self:generateDrops()
  self.cur_rng_index = RNGMonitor.RNGIndex
  self.cur_table_pos = self:findTablePosition(self.cur_rng_index)
  return tbl
end

function DropTable:draw(pos)
  pos = pos or self:findTablePosition()
  local draw_table = {}
  local draw_table_len = 10
  local count = 0

  repeat
    local drop = self.drops[pos]
    table.insert(draw_table, string.format("%d: %s", drop.rng_index, drop.name))
    count = count + 1
    pos = pos + 1
  until pos > #self.drops or count >= draw_table_len

  Drawer:draw(draw_table, Drawer.anchors.TOP_LEFT)
end

function DropTable:findTablePosition(rng_index)
  rng_index = rng_index or RNGMonitor.RNGIndex
  for index, drop in ipairs(self.drops) do
    if drop.rng_index >= rng_index then return index end
  end
end

function DropTable:run()
  self:generateAdditionalDrops()
  if self.cur_rng_index ~= RNGMonitor.RNGIndex then
    self.cur_rng_index = RNGMonitor.RNGIndex
    self.cur_table_pos = self:findTablePosition(self.cur_rng_index)
  end
end

function DropTable:generateDrops(pos)
  pos = pos or 0
  local table_size = RNGMonitor:getTableSize()
  for i = pos,table_size do
    local drop = Battle.calculateDrop(self.battle, i)
    if drop ~= nil then
      table.insert(self.drops, { rng_index = i, name = drop })
    end
  end
  self.last = table_size
end

function DropTable:generateAdditionalDrops()
  if RNGMonitor:getTableSize() == self.last then return end
  self:generateDrops(self.last + 1)
end

return DropTable
