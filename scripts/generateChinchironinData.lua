local Chinchironin = require "lib.Chinchironin"
local RNGTable = require "lib.RNGTable"
local json = require "lib.json"
local fs = require "lib.fs"

local rng_table = RNGTable(0x43, 100000)
local player = Chinchironin.PLAYERS.Gaspar
local frames_to_advance = 441

local function generateRolls()
  local rolls_tbl = {};
  for i = 0, 20000, 1 do
    rng_table.pos = i
    local rolls = {}
    local roll = Chinchironin.simulateRollFromGameStart(rng_table, frames_to_advance, player, 0, 0)
    table.insert(rolls, roll.roll)
    local wait = roll.wait;
    local index = i;
    for j = 1, 16, 1 do
      rng_table.pos = i;
      local roll2 = Chinchironin.simulateRollFromGameStart(rng_table, frames_to_advance, player, j*4, 0)
      table.insert(rolls, roll2.roll)
    end
    table.insert(rolls_tbl, {
      index = index,
      wait = wait,
      rolls = rolls,
      rng = rng_table:getRNG(i)
    })
  end
  return rolls_tbl
end


local results = generateRolls()
fs.writeFile('/home/alex/Projects/Suikoden-Bizhawk-HUD/ChinchironinRollsGaspar.json', json.encode(results))
