local RNGTable = require "lib.RNGTable"
local Address = require "lib.Address"
local fs = require "lib.fs"
local json = require "lib.json"

local SAVESTATE_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/Suikoden/Simulations/'
local BASE_SAVE = SAVESTATE_DIR .. 'KakuSim.State'
local OUTPUT_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/'

REGULAR_NPCS = {
  { name = "Orange", address = 0x18b210 },
  { name = "Old Man", address = 0x18b228 },
  { name = "Stan", address = 0x18b240 },
}

MINA = { name = "Mina", address = 0x18b330 }

function getNPCData(address)
  local x = mainmemory.read_u8(address)
  local y = mainmemory.read_u8(address+1)
  local direction = mainmemory.read_u8(address + 4)
  return {
    x = x,
    y = y,
    d = direction
  }
end

function getFrameCount()
  return mainmemory.read_u16_le(0x199f98)
end

function writeToFile(file_name, data)
  local output_file = OUTPUT_DIR .. file_name .. '.json'
  fs.writeFile(output_file, json.encode(data))
end

local sim_length = 10000

local start_rngs = {
  0x3fb703c0,
  0x163ed46a,
  0x56c35961,
  0x27959cc0,
  0x874c7841,
  0x76a2e768,
  0x26a4f8d4,
  0x1e79af9f,
  0x176df5de,
}

for _,start_rng in ipairs(start_rngs) do
  local rng_table = RNGTable(start_rng, 100000)
  local results = {}
  local frame_count = getFrameCount()
  savestate.load(BASE_SAVE)
  mainmemory.write_u32_le(Address.RNG, start_rng)

  repeat
    emu.frameadvance()
    frame_count = getFrameCount()
    local rng = mainmemory.read_u32_le(Address.RNG)
    local data = {
      rng = rng,
      rng_index = rng_table:getIndex(rng),
      -- npcs = {}
    }
    -- for _,npc in ipairs(REGULAR_NPCS) do
    --   data.npcs[npc.name] = getNPCData(npc.address)
    -- end
    table.insert(results, data)
  until frame_count == sim_length

  writeToFile(string.format("Kaku_sim_%d_0x%x", sim_length, start_rng), results)
end
