local RNGTable = require "lib.RNGTable"
local Address = require "lib.Address"
local fs = require "lib.fs"

local SAVESTATE_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/Suikoden/Simulations/'
local OUTPUT_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/'
local BASE_SAVE = SAVESTATE_DIR .. 'NeclordT1Sims.State'
local OUTPUT_FILE = OUTPUT_DIR .. 'NeclordT1.csv'

local RNG_TABLE = RNGTable(0x42, 200000)
local START_INDEX = 65601
local END_INDEX = 80000

function writeFileHeaders(file_name)
  fs.writeFile(file_name, "Start Index,End Index,Start RNG,End RNG,Move,Target\n")
end

local CHARACTER_MAX_HPS = {
  Hix = 448,
  Viktor = 537,
  Flik = 505,
  Cleo = 453,
}

function writeResultToFileCSV(file_name, result)
  local str = table.concat(result, ',')
  fs.appendToFile(file_name, string.format("%s\n", str))
end

-- Wind and Lightning can go next as soon as HP drops
-- Bats add 1 to index after it drops

function getCharactersHP()
  local hix_current_hp = mainmemory.read_u16_le(0x197776)
  local viktor_current_hp = mainmemory.read_u16_le(0x1977CA)
  local flik_current_hp = mainmemory.read_u16_le(0x19781E)
  local cleo_current_hp = mainmemory.read_u16_le(0x197872)

  local damage_taken =
    hix_current_hp < CHARACTER_MAX_HPS.Hix or
    viktor_current_hp < CHARACTER_MAX_HPS.Viktor or
    flik_current_hp < CHARACTER_MAX_HPS.Flik

  return {
    Hix = {
      HP = hix_current_hp,
      Changed = hix_current_hp < CHARACTER_MAX_HPS.Hix
    },
    Viktor = {
      HP = viktor_current_hp,
      Changed = viktor_current_hp < CHARACTER_MAX_HPS.Viktor
    },
    Flik = {
      HP = flik_current_hp,
      Changed = flik_current_hp < CHARACTER_MAX_HPS.Flik
    },
    Cleo = {
      HP = cleo_current_hp,
      Changed = cleo_current_hp < CHARACTER_MAX_HPS.Cleo
    },
    damage_taken = damage_taken
  }
end

function determineMove(HPs)
  if HPs.Cleo.Changed then
    local cleo_damage = CHARACTER_MAX_HPS.Cleo - HPs.Cleo.HP
    if cleo_damage > 100 then
      return { type = "Wind", target = "All" }
    else
      return { type = "Lightning", target = "All" } end
  end

  local target = "Hix"
  if HPs.Viktor.Changed then target = "Viktor" end
  if HPs.Flik.Changed then target = "Flik" end
  return { type = "Bats", target = target }
end

local function runSimulation(start_index)
  local start_rng = RNG_TABLE:getRNG(start_index)
  savestate.load(BASE_SAVE)
  mainmemory.write_u32_le(Address.RNG, start_rng)

  local character_hps = getCharactersHP()
  repeat
    character_hps = getCharactersHP()
    emu.frameadvance()
  until character_hps.damage_taken

  local move = determineMove(character_hps)
  local end_rng = mainmemory.read_u32_le(Address.RNG)
  local end_index = RNG_TABLE:getIndex(end_rng)
  return { start_index, end_index, string.format("0x%x", start_rng), string.format("0x%x", end_rng), move.type, move.target }
end

local function main()
  -- writeFileHeaders(OUTPUT_FILE)
  for i = START_INDEX,END_INDEX,1 do
    savestate.load(BASE_SAVE)
    local result = runSimulation(i)
    writeResultToFileCSV(OUTPUT_FILE, result)
  end
end


local function test()
  local result = runSimulation(69047)
  writeResultToFileCSV(OUTPUT_FILE, result)
end

-- test()
main()
