local RNGLib = require "lib.RNG"
local EncounterTable = require "lib.EncounterTable"
local Address = require "lib.Address"
local M = {}

local function onWorldMapOrOverworld(gamestate, prev_gamestate)
  gamestate = gamestate or memory.read_u8(Address.GAMESTATE)
  if gamestate ~= 3 then return gamestate end
  prev_gamestate = prev_gamestate or memory.read_u8(Address.PREV_GAMESTATE)
  return prev_gamestate
end

local function locationIntToKey(gamestate)
  gamestate = gamestate or onWorldMapOrOverworld()
  if gamestate == 1 then return "WM" end
  if gamestate == 2 then return "OW" end
  return "Other"
end

-- rng2 is included as an optional parameter for optimization purposes
local function getEncounterIndex(rng, tableSize, rng2)
  rng2 = rng2 or RNGLib.getRNG2(rng)
  local divisor = math.floor(0x7fff/tableSize)
  local encounterIndex = math.floor(rng2/divisor)
  if (encounterIndex >= tableSize) then return tableSize end
  return encounterIndex + 1
end

local function isPossibleBattle(rng, isWorldmap)
  isWorldmap = isWorldmap or false
  local rng2 = RNGLib.getRNG2(rng)
  local res
  if isWorldmap then
    res = rng2 - bit.lshift(bit.rshift(rng2, 8), 8)
    if res < 8 then return res end
    return false
  end
  res = bit.band(math.floor(rng2/0x7f), 0xff)
  if res < 5 then return res end
  return false
end

local TableSizes = {
  WM = {},
  OW = {},
}

for _,area in pairs(EncounterTable) do
  local encounterTableSize = #area.encounters
  if area.areaType == 1 then
    if not TableSizes.WM[encounterTableSize] then
      TableSizes.WM[encounterTableSize] = true
    end
  end
  if area.areaType == 2 then
    if not TableSizes.OW[encounterTableSize] then
      TableSizes.OW[encounterTableSize] = true
    end
  end
end


M.onWorldMapOrOverworld = onWorldMapOrOverworld
M.getEncounterIndex = getEncounterIndex
M.isPossibleBattle = isPossibleBattle
M.locationIntToKey = locationIntToKey
M.TableSizes = TableSizes

return M
