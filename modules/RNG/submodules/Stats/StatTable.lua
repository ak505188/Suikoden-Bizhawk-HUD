local StatCalculations = require "lib.Characters.StatCalculations"

local function StatTable(character, starting_level, levels_gained, RNG_table)
  local statTable = {
    Character = character,
    StartingLevel = starting_level,
    LevelsGained = levels_gained,
    RNG_table = RNG_table,
    StatsGained = {},
    Size = 0,
  }

  function statTable:generateStatsGained()
    local rng_table_size = self.RNG_table:getSize()
    if rng_table_size == self.Size then return end
    for i = self.Size, self.RNG_table:getSize(), 1 do
      local rng = self.RNG_table:getRNG(i)
      local stats = StatCalculations.calculateCharacterLevelUps(
        self.Character,
        self.StartingLevel,
        self.LevelsGained,
        rng)
      self.StatsGained[i] = stats
    end
    self.Size = rng_table_size
  end

  return statTable
end

return StatTable
