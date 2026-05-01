local fs = require "lib.fs"
local json = require "lib.json"

local OUTPUT_DIR = '/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/'
local OUTPUT_FILE = OUTPUT_DIR .. 'NPCBounds.json'

NPCS_CONSTANTS = {
  { name = "Orange", address = 0x18b210 },
  { name = "Old Man", address = 0x18b228 },
  { name = "Stan", address = 0x18b240 },
  { name = "Mina", address = 0x18b330 },
}

function getNPCPosition(address)
  local x = mainmemory.read_u8(address)
  local y = mainmemory.read_u8(address+1)
  return x, y
end

function initNPCs()
  local npcs = {}
  for index,npc in ipairs(NPCS_CONSTANTS) do
    local x,y = getNPCPosition(npc.address)
    npcs[index] = {
      name = npc.name,
      address = npc.address,
      x = x,
      y = y,
      bounds = {
        left = x,
        right = x,
        up = y,
        down = y
      }
    }
  end
  return npcs
end

NPCS = initNPCs()

function getFrameCount()
  return mainmemory.read_u16_le(0x199f98)
end

function writeToFile()
  if getFrameCount() % (60 * 60) == 0 then
    fs.writeFile(OUTPUT_FILE, json.encode(NPCS))
  end
end

while true do
  writeToFile()
  emu.frameadvance()
  for _,npc in ipairs(NPCS) do
    local x,y = getNPCPosition(npc.address)
    if x ~= npc.x then
      if x < npc.bounds.left then
        print(string.format('Increased left bound for %s to %d', npc.name, x))
        npc.bounds.left = x
      elseif x > npc.bounds.right then
        print(string.format('Increased right bound for %s to %d', npc.name, x))
        npc.bounds.right = x
      end
    elseif y ~= npc.y then
      if y < npc.bounds.up then
        print(string.format('Increased up bound for %s to %d', npc.name, y))
        npc.bounds.up = y
      elseif y > npc.bounds.down then
        print(string.format('Increased down bound for %s to %d', npc.name, y))
        npc.bounds.down = y
      end
    end
    npc.x = x
    npc.y = y
  end
end
