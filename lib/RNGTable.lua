local Config = require "Config"
local Locations = require "lib.Enums.Location"
local EncounterLib = require "lib.Encounter"
local RNGLib = require "lib.RNG"

-- These affect how far ahead in the RNG the script looks. Don't touch if things are working well.
-- If you set these too small, the script might stop working if RNG advances too quickly.
local SECRET_BUFFER_SIZE = 2000
local INITITAL_BUFFER_SIZE = Config.RNG_MONITOR.INITITAL_BUFFER_SIZE -- Initial look-ahead
local BUFFER_INCREMENT_SIZE = Config.RNG_MONITOR.BUFFER_INCREMENT_SIZE -- Later look-ahead size per frame
local BUFFER_MARGIN_SIZE = Config.RNG_MONITOR.BUFFER_MARGIN_SIZE + SECRET_BUFFER_SIZE -- When difference between current length & current RNG Index is greater than this, look ahead again.

local function generateRNGBuffer(rngTable, bufferLength)
  -- This handles the base RNG
  bufferLength = bufferLength or INITITAL_BUFFER_SIZE
  local rng = rngTable.last
  local index = rngTable.byRNG[rng]

  local function handleEncounterRNG()
    local isBattleWM = EncounterLib.isPossibleBattle(rng, true)
    local isBattleOW = EncounterLib.isPossibleBattle(rng, false)
    local nextRNG, nextRNG2, isRun
    if isBattleWM then
      local battles = {}
      nextRNG = RNGLib.nextRNG(rng)
      nextRNG2 = RNGLib.getRNG2(nextRNG)
      isRun = RNGLib.isRun(RNGLib.getRNG2(RNGLib.nextRNG(nextRNG)))

      for size,_ in pairs(EncounterLib.TableSizes[Locations.WORLD_MAP]) do
        battles[size] = EncounterLib.getEncounterIndex(nextRNG, size, nextRNG2)
      end
      table.insert(rngTable[Locations.WORLD_MAP], {
        index = index,
        rng = rng,
        value = isBattleWM,
        run = isRun,
        battles = battles,
      })
    end
    if isBattleOW then
      local battles = {}
      nextRNG = nextRNG or RNGLib.nextRNG(rng)
      nextRNG2 = nextRNG2 or RNGLib.getRNG2(nextRNG)
      isRun = isRun or RNGLib.isRun(RNGLib.getRNG2(RNGLib.nextRNG(nextRNG)))

      for size,_ in pairs(EncounterLib.TableSizes[Locations.OVERWORLD]) do
        battles[size] = EncounterLib.getEncounterIndex(nextRNG, size, nextRNG2)
      end
      table.insert(rngTable[Locations.OVERWORLD], {
        index = index,
        rng = rng,
        -- value is the encounter roll. if lower than encounter rate, is battle
        value = isBattleOW,
        run = isRun,
        battles = battles,
      })
    end
  end

  -- Initial call
  handleEncounterRNG()

  local startingTableSize = #rngTable.byIndex
  -- local startingTableSize = #self:getTable().byIndex

  for i = 1, bufferLength do
    rng = RNGLib.nextRNG(rng)
    index = index + 1
    rngTable.byRNG[rng] = index
    rngTable.byIndex[startingTableSize + i] = rng

    handleEncounterRNG()
  end

  rngTable.last = rng
end

-- This checked if the table already existed. Should now be handled by RNG_Monitor
local function createNewRNGTable(rng, table_size)
  table_size = table_size or INITITAL_BUFFER_SIZE
  local table = {
    byRNG = {
      [rng] = 0
    },
    byIndex = {
      [0] = rng
    },
    last = rng,
    [Locations.OVERWORLD] = {},
    [Locations.WORLD_MAP] = {},
    pos = 0,
  }
  generateRNGBuffer(table, table_size)
  return table
end

local function RNGTable(start_rng, table_size)
  local rngTable = createNewRNGTable(start_rng, table_size)

  function rngTable:getIndex(rng)
    return self.byRNG[rng]
  end

  -- Concept Idea: Secret Buffer
  -- Buffer not exposed via size, so tools won't try to calculate for it
  -- But when using tools to calculate stuff, can advance into secret buffer and pull RNG values
  -- So for example, with chinchironin, will still stop at 30000/30000 but will be able to use secret buffer for RNG values past 30000

  function rngTable:getRNG(index)
    index = index or self.pos
    return self.byIndex[index]
  end

  function rngTable:getSize()
    local real_size = self:getRealSize()
    if real_size < INITITAL_BUFFER_SIZE + SECRET_BUFFER_SIZE then return INITITAL_BUFFER_SIZE end
    return real_size - SECRET_BUFFER_SIZE
  end

  function rngTable:getRealSize()
    return self.byRNG[self.last]
  end

  function rngTable:next(iterations)
    iterations = iterations or 1
    local pos = self.pos + iterations
    local real_size = self:getRealSize()
    self.pos = pos <= real_size and pos or real_size
  end

  function rngTable:getShortRNG(rng)
    rng = rng or self:getRNG(self.pos)
    return RNGLib.getRNG2(rng)
  end

  function rngTable:increaseBuffer(rng, size, force)
    rng = rng or self:getRNG()
    size = size or BUFFER_INCREMENT_SIZE
    force = force or false
    if (self:getSize() - self:getIndex(rng) < BUFFER_MARGIN_SIZE - SECRET_BUFFER_SIZE) or force == true then
      generateRNGBuffer(self, size)
    end
  end

  return rngTable
end

return RNGTable
