local Config = require "Config"
local Locations = require "lib.Enums.Location"
local EncounterLib = require "lib.Encounter"
local RNGLib = require "lib.RNG"
local Utils = require "lib.Utils"

-- These affect how far ahead in the RNG the script looks. Don't touch if things are working well.
-- If you set these too small, the script might stop working if RNG advances too quickly.
local INITITAL_BUFFER_SIZE = Config.RNG_MONITOR.INITITAL_BUFFER_SIZE -- Initial look-ahead
local BUFFER_INCREMENT_SIZE = Config.RNG_MONITOR.BUFFER_INCREMENT_SIZE -- Later look-ahead size per frame
local BUFFER_MARGIN_SIZE = Config.RNG_MONITOR.BUFFER_MARGIN_SIZE -- When difference between current length & current RNG Index is greater than this, look ahead again.

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
    [Locations.WORLD_MAP] = {}
  }
  generateRNGBuffer(table, table_size)
  return table
end

local function RNGTable(start_rng, table_size)
  local rngTable = createNewRNGTable(start_rng, table_size)

  function rngTable:getIndex(rng)
    return self.byRNG[rng]
  end

  function rngTable:getSize()
    return self.byRNG[self.last]
  end

  function rngTable:increaseBuffer(rng, size, force)
    if rng == nil then return end
    size = size or BUFFER_INCREMENT_SIZE
    force = force or false
    if (self:getSize() - self:getIndex(rng) < BUFFER_MARGIN_SIZE) or force == true then
      generateRNGBuffer(self, size)
    end
  end

  function rngTable:shouldIncreaseBuffer(rng)
    if self:getSize() - self:getIndex(rng) < BUFFER_MARGIN_SIZE then
      return true
    end
    return false
  end

  return rngTable
end

return RNGTable
