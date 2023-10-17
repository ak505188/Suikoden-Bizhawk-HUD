local Drawer = require "controllers.drawer"
local RNGMonitor = require "monitors.RNG_Monitor"
local Battle = require "lib.Battle"

local DropTable = {}

function DropTable:new(battle)
  local tbl = {}
  setmetatable(tbl, self)
  self.__index = self
  self.battle = battle
  self.drops = {}
  self:generateDrops()
  self:generateDropsListForFilters()
  self.locked_pos = -1
  self.cur_rng_index = RNGMonitor.RNGIndex
  self.cur_table_pos = self:findTablePosition(self.cur_rng_index)
  return tbl
end

function DropTable:generateDropsListForFilters()
  local drops_list_for_filters = {}
  for _, enemy in ipairs(self.battle.Enemies) do
    for _, drop in ipairs(enemy.Drops) do
      if drops_list_for_filters[drop.id] == nil then
        drops_list_for_filters[drop.id] = {
          chance = drop.chance,
          id = drop.id,
          name = drop.name,
          show = true,
        }
      end
    end
  end
  self.drops_list_for_filters = drops_list_for_filters
end

function DropTable:draw(pos)
  pos = pos or self:findTablePosition()
  if self.locked_pos > -1 then
    pos = self.locked_pos
  end
  local draw_table = {}
  local draw_table_len = 15
  local count = 0

  repeat
    local drop = self.drops[pos]
    if self.drops_list_for_filters[drop.id].show then
      table.insert(draw_table, string.format("%d: %s", drop.rng_index, drop.name))
      count = count + 1
    end
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
  self:generateDrops()
  if self.cur_rng_index ~= RNGMonitor.RNGIndex then
    self.cur_rng_index = RNGMonitor.RNGIndex
    self.cur_table_pos = self:findTablePosition(self.cur_rng_index)
  end
end

function DropTable:generateDrops()
  local table_size = RNGMonitor:getTableSize()
  local pos

  if self.last == nil then
    pos = 0
  elseif self.last == table_size then
    return
  else
    pos = self.last
  end

  for i = pos,table_size do
    local drop_data = Battle.calculateDrop(self.battle, i)
    if drop_data ~= nil then
      table.insert(self.drops, { rng_index = i, name = drop_data.name, id = drop_data.id })
    end
  end
  self.last = table_size
end

return DropTable
