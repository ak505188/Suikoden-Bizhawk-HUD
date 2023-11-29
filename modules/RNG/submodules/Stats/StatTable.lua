local StatCalculations = require "lib.Characters.StatCalculations"
local RNG = require "lib.RNG"
local Config = require "Config"

local LevelCache = {
  Name = nil,
  Levelup = {},
  Cutoffs = {}
}

function LevelCache:generateKey(rng, level)
  local cutoff = nil
  for _, cutoff_level in ipairs(self.Cutoffs) do
    if level < cutoff_level then
      cutoff = cutoff_level
      break
    end
  end

  if cutoff == nil then
    print("LevelCache: Illegal cutoff level")
    print("Cutoffs", self.Cutoffs)
  end

  return string.format("%x_%d", rng, cutoff)
end

function LevelCache:read(rng, level)
  return self.Levelup[self:generateKey(rng, level)]
end

function LevelCache:write(rng, level, stats, next_rng)
  self.Levelup[self:generateKey(rng, level)] = { Stats = stats, NextRNG = next_rng }
end

function LevelCache:init(character)
  if self.Name == character.Name then return self end

  self.Levelup = {}

  self.Cutoffs = { 20, 60, 100 }
  if character.Growths.PWR == 9 then
    self.Cutoffs = { 15, 20, 60, 100 }
  end

  return self
end

local function StatTable(character, starting_level, levels_gained, RNG_table)
  if levels_gained + starting_level > 99 then
    levels_gained = 99 - starting_level
  end


  local statTable = {
    Character = character,
    StartingLevel = starting_level,
    LevelsGained = levels_gained,
    RNG_table = RNG_table,
    StatsGained = {},
    Size = 0,
    Increment_Size = Config.StatsGenerator.LEVELUPS_PER_FRAME // levels_gained,
    LevelCache = LevelCache:init(character)
  }

  function statTable:generateStatsGained()
    local rng_table_size = self.RNG_table:getSize()
    if rng_table_size == self.Size then return end

    local finish_size = math.min(
      self.Size + self.Increment_Size,
      rng_table_size
    )

    local start_index = self.Size == 0 and 0 or self.Size + 1

    for i = start_index, finish_size, 1 do
      local rng = self.RNG_table:getRNG(i)
      local stats = self:calculateCharacterLevelUps(rng)
      self.StatsGained[i] = stats
    end
    self.Size = finish_size
  end

  function statTable:isGenerating()
    return self.Size ~= self.RNG_table:getSize()
  end

  function statTable:slice(index, size)
    local stats_tbl = {}
    for i = index, index + size, 1 do
      local stats = self.StatsGained[i]
      if stats == nil then return stats_tbl end
      table.insert(stats_tbl, stats)
    end
    return stats_tbl
  end

  function statTable:calculateCharacterLevelUp(level, rng)
    local cached_levelup = self.LevelCache:read(rng, level)
    if cached_levelup then
      return cached_levelup.Stats, cached_levelup.NextRNG
    end

    local original_rng = rng
    local stats = {}
    for _, stat in ipairs(StatCalculations.LevelupStatOrder) do
      rng = RNG.nextRNG(rng)
      stats[stat] = StatCalculations.calculateStatLevelUp(character, level, stat, rng)
    end
    self.LevelCache:write(original_rng, level, stats, rng)
    return stats, rng
  end

  function statTable:calculateCharacterLevelUps(rng)
    local stats = {
      PWR = 0,
      SKL = 0,
      DEF = 0,
      SPD = 0,
      MGC = 0,
      LUK = 0,
      HP  = 0,
    }

    for i = 1, self.LevelsGained, 1 do
      local level = self.StartingLevel + i
      local level_up_stats
      level_up_stats,rng = self:calculateCharacterLevelUp(level, rng)
      for stat, value in pairs(level_up_stats) do
        stats[stat] = stats[stat] + value
      end
    end

    return stats
  end

  return statTable
end

return StatTable
