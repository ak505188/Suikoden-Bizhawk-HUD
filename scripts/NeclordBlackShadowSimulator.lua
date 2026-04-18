local RNGTable = require "lib.RNGTable"
local Buttons = require "lib.Buttons"
local Address = require "lib.Address"
local fs = require "lib.fs"

local NECLORD_HP_ADDR = 0x19796E

local SAVESTATE_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/Suikoden/Simulations/'
local OUTPUT_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/'
local BASE_SAVE = SAVESTATE_DIR .. 'NeclordBS.State'
local OUTPUT_FILE = OUTPUT_DIR .. 'NeclordBS.csv'

local RNG_TABLE = RNGTable(0x42, 200000)

function advanceFrames(n)
  if n <= 0 then return end
  for i = 1, n, 1 do
    emu.frameadvance()
  end
end

function advanceDialogue(frames)
  for i = 0, frames-1, 1 do
    if (i % 4 < 2) then
      Buttons.Cross:press()
    else
      Buttons:clear()
    end
    advanceFrames(1)
  end
end


function confirmDialogue(delay)
  advanceFrames(delay)
  advanceDialogue(1)
end

function waitForCombatToFinish()
  local original_teo_unit_count = mainmemory.read_u16_le(TEO_UNIT_COUNT_ADDR)
  local teo_unit_count = original_teo_unit_count
  while original_teo_unit_count == teo_unit_count do
    advanceFrames(1)
    teo_unit_count = mainmemory.read_u16_le(TEO_UNIT_COUNT_ADDR)
  end
  advanceFrames(10)
  advanceDialogue(1)
  advanceFrames(10)
  return teo_unit_count, original_teo_unit_count
end

function scroll(amount, direction)
  Buttons:clear()
  direction = direction or "Down"
  if (amount == 0) then return end
  for i = 1, amount, 1 do
    for _ = 1, 3, 1 do
      Buttons[direction]:press()
      advanceFrames(1)
    end
    Buttons:clear()
    advanceFrames(5)
  end
end

function selectCharge(index)
  advanceDialogue(4)
  advanceFrames(15)
  scroll(index - 1)
  advanceDialogue(240)
end

function simulateTurn(charge_index)
  selectCharge(charge_index)
  local new_unit_count = waitForCombatToFinish()
  advanceDialogue(8)
  advanceFrames(120)
  return new_unit_count
end

function findFirstPowerMatch(tbl, value)
  for i = 1, #tbl do
    if tbl[i] == value then
      return i
    end
  end
  return nil
end

function simulateBattle(actions, pool)
  local start_frame_count = memory.read_u32_le(Address.SESSION_FRAMECOUNT)
  local action_tbl = {}
  local unit_count = {}
  local success = false

  for i = 1, #pool do action_tbl[i] = pool[i] end

  for i = 1, #actions, 1 do
    local pwr = actions[i]
    if (pwr > 24) then
      pwr = math.ceil(pwr / 1.5)
      activateStrategist()
    end
    local index = findFirstPowerMatch(action_tbl, pwr)
    table.insert(unit_count, simulateTurn(index))
    table.remove(action_tbl, index)
  end
  if unit_count[#unit_count] == 0 then
    advanceDialogue(30)
    success = true
  end

  local end_frame_count = memory.read_u32_le(Address.SESSION_FRAMECOUNT)
  local seconds_elapsed = (end_frame_count - start_frame_count) / 60
  local rng = mainmemory.read_u32_le(Address.RNG)
  return {
    actions = actions,
    success = success,
    rng = rng,
    rng_index = RNG_TABLE:getIndex(rng),
    unit_count = unit_count,
    time_in_seconds = seconds_elapsed
  }
end

function activateStrategist()
  advanceFrames(4)
  scroll(1, "Up")
  advanceFrames(4)
  advanceDialogue(4)
  advanceFrames(10)
  scroll(1, "Up")
  advanceFrames(8)
  advanceDialogue(390)
  advanceFrames(12)
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
  local neclord_hp = mainmemory.read_u16_le(NECLORD_HP_ADDR)
  while neclord_hp == 7500 do
    emu.frameadvance()
    neclord_hp = mainmemory.read_u16_le(NECLORD_HP_ADDR)
  end
  local end_rng = mainmemory.read_u32_le(Address.RNG)
  local end_index = RNG_TABLE:getIndex(end_rng)
  return { start_index, end_index, string.format("0x%x", start_rng), string.format("0x%x", end_rng) }
end

local function main()
  writeFileHeaders(OUTPUT_FILE)
  for i = 68000,168000,1 do
    savestate.load(BASE_SAVE)
    local result = runSimulation(i)
    writeResultToFileCSV(OUTPUT_FILE, result)
  end
end


local function test()
  savestate.load(BASE_SAVE)
  simulateBattle({19,14,14,25,24 }, USABLE_POOL_LEDON)
end

-- test()

main()
