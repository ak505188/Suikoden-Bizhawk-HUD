local RNGLib = require("RNGLib")
local M = {}

local Address = {
  ["GAMESTATE"] = 0x1b9bbc,
  ["PREV_GAMESTATE"] = 0x1b9bb8,
  ["WM_ZONE"] = 0x1b8002,
  ["AREA_ZONE"] = 0x1b8000,
  ["SCREEN_ZONE"] = 0x1b8001,
  ["ENCOUNTER_RATE"] = 0x17159D,
  ["RNG"] = 0x9010,
}

local function onWorldMapOrOverworld(gamestate, prev_gamestate)
  gamestate = gamestate or memory.read_u8(Address.GAMESTATE)
  if gamestate ~= 3 then return gamestate end
  prev_gamestate = prev_gamestate or memory.read_u8(Address.PREV_GAMESTATE)
  return prev_gamestate
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

M.onWorldMapOrOverworld = onWorldMapOrOverworld
M.getEncounterIndex = getEncounterIndex
M.isPossibleBattle = isPossibleBattle

return M
