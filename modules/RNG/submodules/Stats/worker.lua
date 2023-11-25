local Characters = require "lib.Characters.Characters"
local CharacterNames = require "lib.Characters.Names"
local RNGMonitor = require "monitors.RNG_Monitor"
local StatTable = require "modules.RNG.submodules.Stats.StatTable"
local StatCalculations = require "lib.Characters.StatCalculations"
local Drawer = require "controllers.drawer"

local Worker = {
  Character = Characters[CharacterNames.HERO],
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
  LevelsGained = 58,
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
  return self.StatTables[self.StatTableKey]
end

function Worker:draw()
  local stat_table = self:getStatTable()
  if stat_table.Size == 0 then return end

  local labels = string.format("Index %s", self:statsToShowToStr())
  local rng_index = RNGMonitor:getIndex()
  local stats_strs = {}

  for i = rng_index, rng_index + 15 do
    local stats_str = string.format("%5d %s", i, self:statsToStr(self:getStatTable().StatsGained[i]))
    table.insert(stats_strs, stats_str)
  end

  Drawer:draw({ labels }, Drawer.anchors.TOP_LEFT, nil, true)
  Drawer:draw(stats_strs, Drawer.anchors.TOP_LEFT)
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

function Worker:statsToStr(stats)
  local stats_str = {}
  for _, stat in ipairs(StatCalculations.LevelupStatOrder) do
    if self.StatsToShow[stat] then
      table.insert(stats_str, string.format("%3d", stats[stat]))
    end
  end

  return table.concat(stats_str, " ")
end

function Worker:generateStatTableKey()
  return string.format(
    "%s_%d_%d_0x%x",
    self.Character.name,
    self.StartingLevel,
    self.LevelsGained,
    RNGMonitor.StartingRNG)
end

return Worker
