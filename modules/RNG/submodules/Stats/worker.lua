local CombatCharacters = require "lib.Characters.CombatCharacters"
local RNGMonitor = require "monitors.RNG_Monitor"
local StatTable = require "modules.RNG.submodules.Stats.StatTable"
local StatCalculations = require "lib.Characters.StatCalculations"
local Drawer = require "controllers.drawer"

local Names = CombatCharacters.Names
local Characters = CombatCharacters.Characters

local Worker = {
  Character = Characters[Names.HERO],
  StatTables = {},
  StatsToShow = {
    PWR = true,
    SKL = true,
    DEF = true,
    SPD = true,
    MGC = true,
    LUK = true,
    HP  = true
  },
  StartingLevel = 1,
  LevelsGained = 1,
  StatTableKey = ''
}

function Worker:run()
  self.StatTableKey = self:generateStatTableKey()
  local stat_table = self:getStatTable()
  if stat_table == nil then
    stat_table = StatTable(self.Character, self.StartingLevel, self.LevelsGained, RNGMonitor:getTable())
    self.StatTables[self.StatTableKey] = stat_table
  end
  stat_table:generateStatsGained()
end

function Worker:getStatTable()
  local stat_table = self.StatTables[self.StatTableKey]
  return stat_table
end

function Worker:draw()
  local stat_table = self:getStatTable()
  if not stat_table then return end
  local info_str = string.format(
    "%s LVL:%d+%d %d/%d",
    self.Character.Name,
    self.StartingLevel,
    self.LevelsGained,
    stat_table.Size,
    stat_table.RNG_table:getSize())
  Drawer:draw({ info_str }, Drawer.anchors.TOP_LEFT, nil, true)

  if stat_table.Size == 0 then return end

  local labels = string.format("Index %s", self:statsToShowToStr())
  local rng_index = RNGMonitor:getIndex()
  local stats_str_table = self:statsTableToStringTable(rng_index, 15)

  Drawer:draw({ labels }, Drawer.anchors.TOP_LEFT, nil, true)
  Drawer:draw(stats_str_table, Drawer.anchors.TOP_LEFT)
end

function Worker:statsToShowToStr()
  local tbl = {}
  for _, stat in ipairs(StatCalculations.LevelupStatOrder) do
    if self.StatsToShow[stat] then
      table.insert(tbl, string.format("%3s", stat))
    end
  end

  return table.concat(tbl, " ")
end

function Worker:statsTableToStringTable(rng_index, length)
  local str_table = {}
  local stats_table_slice = self:getStatTable():slice(rng_index, length)
  for index,stats_row in ipairs(stats_table_slice) do
    local stats_str_table = { string.format("%5d", rng_index + index - 1) }
    for _,stat in ipairs(StatCalculations.LevelupStatOrder) do
      if self.StatsToShow[stat] then
        table.insert(stats_str_table, string.format("%3d", stats_row[stat]))
      end
    end
    table.insert(str_table, table.concat(stats_str_table, " "))
  end
  return str_table
end

function Worker:generateStatTableKey()
  return string.format(
    "%s_%d_%d_0x%x",
    self.Character.Name,
    self.StartingLevel,
    self.LevelsGained,
    RNGMonitor.StartingRNG)
end

return Worker
