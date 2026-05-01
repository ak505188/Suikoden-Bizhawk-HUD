local RNGTable = require "lib.RNGTable"
local Address = require "lib.Address"
local fs = require "lib.fs"

local SAVESTATE_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/Suikoden/Simulations/'
local OUTPUT_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/'
local BASE_SAVE = SAVESTATE_DIR .. 'QueenAnt.State'
local OUTPUT_FILE = OUTPUT_DIR .. 'QueenAnt.csv'

local RNG_TABLE = RNGTable(0x19, 40000)
local START_INDEX = 7490
local END_INDEX = 10000
local WAIT_TIME = 9.5 * 60

function advanceFrames(n)
  if n <= 0 then return end
  for i = 1, n, 1 do
    emu.frameadvance()
  end
end

function writeFileHeaders(file_name)
  fs.writeFile(file_name, "Start Index,End Index,Start RNG,End RNG\n")
end


function writeResultToFileCSV(file_name, result)
  local str = table.concat(result, ',')
  fs.appendToFile(file_name, string.format("%s\n", str))
end

local function runSimulation(start_index)
  local start_rng = RNG_TABLE:getRNG(start_index)
  savestate.load(BASE_SAVE)
  mainmemory.write_u32_le(Address.RNG, start_rng)
  advanceFrames(WAIT_TIME)

  local end_rng = mainmemory.read_u32_le(Address.RNG)
  local end_index = RNG_TABLE:getIndex(end_rng)
  return { start_index, end_index, string.format("0x%x", start_rng), string.format("0x%x", end_rng) }
end

local function main()
  -- writeFileHeaders(OUTPUT_FILE)
  for i = START_INDEX,END_INDEX,1 do
    savestate.load(BASE_SAVE)
    local result = runSimulation(i)
    writeResultToFileCSV(OUTPUT_FILE, result)
  end
end

main()
