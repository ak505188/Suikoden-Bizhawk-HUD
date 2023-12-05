local Chinchironin = require "lib.Chinchironin"
local RNGLib = require "lib.RNG"
local Config = require "Config"

local function ChinchironinTable(player, rng_table, rng_modifier)
  local chinchironinTable = {
    Player = player,
    Increment_Size = Config.ChinchironinGenerator.GENERATIONS_PER_FRAME or 100,
    RNG_table = rng_table,
    RNG_modifier = rng_modifier,
    Rolls = {},
    Size = 0,
  }

  function chinchironinTable:generateRolls()
    local rng_table_size = self.RNG_table:getSize()
    if rng_table_size == self.Size then return end

    local finish_size = math.min(
      self.Size + self.Increment_Size,
      rng_table_size
    )

    local start_index = self.Size == 0 and 0 or self.Size + 1

    for i = start_index, finish_size, 1 do
      local rng = RNGLib.RNGBuilder(self.RNG_table:getRNG(i))
      local roll = Chinchironin.simulateRollFromGameStart(rng, nil, self.player, self.RNG_modifier)
      self.Rolls[i] = roll
    end
    self.Size = finish_size
  end

  function chinchironinTable:isGenerating()
    return self.Size ~= self.RNG_table:getSize()
  end

  function chinchironinTable:slice(index, size)
    local rolls_tbl = {}
    for i = index, index + size, 1 do
      local roll = self.Rolls[i]
      if roll == nil then return rolls_tbl end
      table.insert(rolls_tbl, roll)
    end
    return rolls_tbl
  end

  return chinchironinTable
end

return ChinchironinTable
