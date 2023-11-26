local StatCalculations = require "lib.Characters.StatCalculations"

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
    Increment_Size = math.min((100 - levels_gained), 500),
  }

  function statTable:generateStatsGained()
    local rng_table_size = self.RNG_table:getSize()
    if rng_table_size == self.Size then return end

    local finish_size = math.min(
      self.Size + self.Increment_Size,
      rng_table_size
    )

    for i = self.Size, finish_size, 1 do
      local rng = self.RNG_table:getRNG(i)
      local stats = StatCalculations.calculateCharacterLevelUps(
        self.Character,
        self.StartingLevel,
        self.LevelsGained,
        rng)
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

  return statTable
end

return StatTable
