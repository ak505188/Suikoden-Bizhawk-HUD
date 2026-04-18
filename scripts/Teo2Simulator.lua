local RNGTable = require "lib.RNGTable"
local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local Address = require "lib.Address"
local Utils = require "lib.Utils"
local json = require "lib.json"
local fs = require "lib.fs"

local TEO_UNIT_COUNT_ADDR = 0x0A89D2
local MY_SELECTION_INDEX_ADDR = 0x0A8728 -- Can edit this instead of going through list manually

local USABLE_POOL_LEDON = { 24, 19, 17, 17, 14, 14 }
local USABLE_POOL_LEDON_STRATEGISTS = {
  -- { 25, 24, 19, 14, 14 }, -- This one never works, ~500 left
  { 25, 24, 19, 17, 14 }, -- This one rarely works? ~100 left
  { 28, 24, 17, 14, 14 },
  { 28, 24, 17, 17, 14 },
  { 36, 17, 17, 14, 14 },
  { 36, 19, 17, 14, 14 },
  { 36, 19, 17, 17, 14 },
}

local USABLE_POOL_KESSLER = { 24, 21, 19, 17, 14, 14 }
local KESSLER_POOLS = {
  { 24, 21, 19, 17, 14, 14 },
  { 36, 21, 19, 17, 14 },
  { 36, 21, 19, 14, 14 },
  { 36, 21, 17, 14, 14 },
  { 36, 19, 17, 14, 14 },
  { 31, 24, 19, 17, 14 },
  { 31, 24, 19, 14, 14 },
  { 31, 24, 17, 14, 14 },
  { 28, 24, 21, 17, 14 },
  { 28, 24, 21, 14, 14 },
  { 28, 24, 17, 14, 14 },
  { 25, 24, 21, 19, 14 }
}

local USABLE_BLACKMAN_POOL = { 24, 19, 17, 17, 15, 14, 14 }
local BLACKMAN_POOLS = {
  { 24, 19, 17, 17, 15, 14 },
  { 36, 19, 17, 17, 15 },
  { 36, 19, 17, 15, 14 },
  -- About 200 left { 36, 17, 17, 15, 14 },
  { 28, 24, 17, 17, 15 },
  -- About 300 left { 28, 24, 17, 15, 14 },
  { 25, 24, 19, 17, 15 },
  -- About 200 left { 25, 24, 19, 15, 14 },
}

-- A:9 S:1 Kraze Room
-- A:9 S:0 Fountain area
-- A:9 S:10 Bridge, RNG advances once the moment this changes. Should be safe to check RNG here
-- A:0 S:0 Gregminster Main, changes way before RNG advances
-- A:0 S:1 Home, safe to stop tracking RNG as soon as this changes

local SAVESTATE_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/Suikoden/Simulations/WB_Teo_2/'
local OUTPUT_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/Teo2Sims/'
local BASE_SAVE = SAVESTATE_DIR .. 'TeoSimBlackmanBase.State'
local OUTPUT_FILE = OUTPUT_DIR .. 'Blackman.csv'

local RNG_TABLE = RNGTable(0x42, 100000)

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

local function permute_unique_iter(arr)
    -- Make a copy so we don't mutate the original
    local a = {}
    for i = 1, #arr do a[i] = arr[i] end

    local function generate(start)
        if start == #a then
            -- Yield a copy of the current permutation
            local perm = {}
            for i = 1, #a do perm[i] = a[i] end
            coroutine.yield(perm)
        else
            local used = {}
            for i = start, #a do
                if not used[a[i]] then
                    used[a[i]] = true

                    -- Swap
                    a[start], a[i] = a[i], a[start]

                    generate(start + 1)

                    -- Backtrack
                    a[start], a[i] = a[i], a[start]
                end
            end
        end
    end

    return coroutine.wrap(function()
        generate(1)
    end)
end

function writeFileHeaders(file_name)
  fs.writeFile(file_name, "Actions,Win,Time (s),Index,RNG,Unit Counts\n")
end

function writeResultToFileCSV(file_name, result)
  local action_str = table.concat(result.actions, ' ')
  local unit_count_str = table.concat(result.unit_count, ' ')
  local output_csv_str = string.format("%s,%s,%.3f,%d,0x%x,%s\n", action_str, result.success, result.time_in_seconds, result.rng_index, result.rng, unit_count_str)
  fs.appendToFile(OUTPUT_FILE, output_csv_str)
end

local function main()
  writeFileHeaders(OUTPUT_FILE)
  for _,pool in ipairs(BLACKMAN_POOLS) do
    for perm in permute_unique_iter(pool) do
      -- Load Savestate
      savestate.load(BASE_SAVE)
      local result = simulateBattle(perm, USABLE_BLACKMAN_POOL)
      writeResultToFileCSV(OUTPUT_FILE, result)
      -- Store result
    end
  end
end

local function test()
  savestate.load(BASE_SAVE)
  simulateBattle({19,14,14,25,24 }, USABLE_POOL_LEDON)
end

-- test()

main()
