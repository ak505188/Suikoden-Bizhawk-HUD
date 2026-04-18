local RNGMonitor = require "monitors.RNG_Monitor"
local StateMonitor = require "monitors.State_Monitor"
local RoomMonitor = require "monitors.Room_Monitor"
local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local Address = require "lib.Address"
local Utils = require "lib.Utils"
local json = require "lib.json"
local fs = require "lib.fs"

-- A:9 S:1 Kraze Room
-- A:9 S:0 Fountain area
-- A:9 S:10 Bridge, RNG advances once the moment this changes. Should be safe to check RNG here
-- A:0 S:0 Gregminster Main, changes way before RNG advances
-- A:0 S:1 Home, safe to stop tracking RNG as soon as this changes

StateMonitor:init()
RNGMonitor:init()
savestate.load('/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/SetInitialRNG.State')
StateMonitor:run()
RNGMonitor:run()

client.unpause()

local function advanceFrames(n)
  if n <= 0 then return end
  for _ = 1, n, 1 do
    StateMonitor:run()
    RNGMonitor:run()
    RoomMonitor:run()
    Drawer:clear()
    RNGMonitor:draw()
    emu.frameadvance()
  end
end

local function moveDirectionTown(direction, steps, wait_time)
  wait_time = wait_time or 4
  Buttons:clear()
	for i = 0, steps, 1 do
    Buttons[direction]:press()
    if i == steps then
      advanceFrames(wait_time)
    else
      advanceFrames(4)
    end
	end
  Buttons:clear()
end

local function advanceDialogue(frames)
  for _ = 0, frames, 1 do
    Buttons.Cross:turbo()
    advanceFrames(1)
  end
  Buttons:clear()
end

local function simulateHolyKrazeMovement(frames_to_wait, extra_steps_x, extra_steps_y)
  savestate.load('/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/HolyBirds.State')
  Buttons.Cross:press()
	advanceFrames(19)
	moveDirectionTown('Left', 13 + extra_steps_x)
	moveDirectionTown('Up', 1 + extra_steps_y, 4)
  advanceFrames(frames_to_wait)
  Buttons.Cross:press()
  advanceFrames(1)
  Buttons:clear()
  advanceDialogue(68)
	moveDirectionTown('Down', 0 + extra_steps_y)
	moveDirectionTown('Right', 13 + extra_steps_x)
  advanceDialogue(90)
end

local function getRoomData()
  local CHARACTER_STRUCT_SIZE = 0x18
  if RoomMonitor.NUM_SLOTS.current == nil then
    return {}
  end

  local room_address = Address.sanitize(RoomMonitor.ROOM_ADDRESS.current)
  local room_data = {}

  for i = 1, RoomMonitor.NUM_SLOTS.current, 1 do
    local address = room_address + ((i - 1) * CHARACTER_STRUCT_SIZE)
    local buffer = mainmemory.read_bytes_as_array(address, 0x18)
    local slot_data = {
      Slot = i,
      Address = address,
      X = buffer[1],
      Y = buffer[2],
      SubpixelX = buffer[3],
      SubpixelY = buffer[4],
      -- Direction = buffer[5], -- This isn't actually direction, has some correlation though
      Moves = buffer[6], -- This seems constant, might actually be flag for movement
      Unknown1 = Utils.readFromByteTable(buffer, 7, 2),
      MemAddress1 = Utils.readFromByteTable(buffer, 9, 4),
      MemAddress2 = Utils.readFromByteTable(buffer, 13, 4),
      MemAddress3 = Utils.readFromByteTable(buffer, 17, 4),
      Unknown2 = Utils.readFromByteTable(buffer, 21, 2),
      Unknown3 = Utils.readFromByteTable(buffer, 23, 2),
    }
    slot_data.Direction = memory.read_u8(Address.sanitize(slot_data.MemAddress2))
    room_data[i] = slot_data
  end

  return room_data
end

local function getPalaceNPCDirections()
  local room_data = getRoomData()
  local npcs = {
    room_data[1].Direction,
    room_data[3].Direction,
    room_data[4].Direction,
    room_data[9].Direction,
    room_data[8].Direction
  }
  return npcs
end

local function getTownNPCPositions()
  local room_data = getRoomData()
  local npcs = {
    ['9'] = {
      x=room_data[2].X,
      y=room_data[2].Y,
      dir=room_data[2].Direction
    },
    ['10'] = {
      x=room_data[3].X,
      y=room_data[3].Y,
      dir=room_data[3].Direction
    },
    ['11'] = {
      x=room_data[6].X,
      y=room_data[6].Y,
      d=room_data[6].Direction
    },
  }

  return npcs
end

local function getBirdDirection(prev_pos, cur_pos, default_dir)
  if cur_pos.x ~= prev_pos.x then
    return cur_pos.x > prev_pos.x and 'Right' or 'Left'
  elseif cur_pos.y ~= prev_pos.y then
    return cur_pos.y > prev_pos.y and 'Down' or 'Up'
  end
  return default_dir
end

local function getInitialBirdsPositions(birds_address)
  local birds = {}
  for i = 0, 4, 1 do
    local addr = birds_address + (16 * i)
    local bird_initial_x = memory.read_u8(addr)
    local bird_initial_y = memory.read_u8(addr+1)
    local bird = {
      bird=i,
      initial={
        x=bird_initial_x,
        y=bird_initial_y,
      },
      movements={}
    }
    table.insert(birds, bird)
  end
  return birds
end

local function getBirdPos(birds_address, bird_slot)
  local addr = birds_address + (16 * bird_slot)
  local bird_current_x = memory.read_u8(addr+2)
  local bird_current_y = memory.read_u8(addr+3)
  return { x=bird_current_x, y=bird_current_y }
end

local function updateBirds(birds_address, birds, hero_pos)
  for i = 0, 4, 1 do
    Utils.tableToStr(birds)
    local bird_pos = getBirdPos(birds_address, i)
    local prev_bird_pos = birds[i+1].initial
    if #birds[i+1].movements > 0 then
      prev_bird_pos = birds[i+1].movements[#birds[i+1].movements].pos
    end
    local move = getBirdDirection(prev_bird_pos, bird_pos)

      if move ~= nil then
      local movement = {
        direction=move,
        pos=bird_pos,
        hero=hero_pos
      }
      table.insert(birds[i+1].movements, movement)
    end
  end
end

local function simulateScreen(rng, text_skip_frames)
  savestate.load('/home/alex/Local/BizHawk-2.10-linux-x64/PSX/State/BridgeScreen.State')
  if rng then
    RNGMonitor:setRNG(rng)
  end

  StateMonitor:run()
  RNGMonitor:run()

  RNGMonitor:run()
  rng = RNGMonitor.RNG
  local rng_index = RNGMonitor:getIndex(rng)
  local hero_pos = { x=RoomMonitor.HERO_X.current, y=RoomMonitor.HERO_Y.current }

  -- This needs to be done on save state load?
  local birds_address = Address.sanitize(memory.read_u32_le(Address.BIRDS_PTR))
  local birds = getInitialBirdsPositions(birds_address)
  local npcs

  -- Do text skip
  for _=0, text_skip_frames, 1 do
    advanceFrames(1)
    updateBirds(birds_address, birds, hero_pos)
  end
  Buttons:clear()
  Buttons.Cross:press()
  advanceFrames(1)
  updateBirds(birds_address, birds, hero_pos)
  Buttons:clear()

  while StateMonitor.SCREEN_ZONE.current == 0 do
    hero_pos = { x=RoomMonitor.HERO_X.current, y=RoomMonitor.HERO_Y.current }
    if (hero_pos.x == 101 and hero_pos.y == 8 and npcs == nil) then
      -- Get NPC Data. Birds are covered by checking every frame.
      -- print()
      npcs = getTownNPCPositions()
    end
    updateBirds(birds_address, birds, hero_pos)
    advanceFrames(1)
  end

  return {
    initial_rng = {
      rng = string.format('0x%08x', rng),
      index = rng_index
    },
    final_rng = {
      rng = string.format('0x%08x', RNGMonitor.RNG),
      index = RNGMonitor.RNGIndex
    },
    npcs = npcs,
    birds = birds
  }
end

local function generateBirdsFile()
  local bridge_starting_points = json.decode(fs.readFile('/home/alex/Projects/Suikoden-Bizhawk-HUD/HolyBridge.json'))

  local path = '/home/alex/Projects/Suikoden-Bizhawk-HUD/bridges'
  for _,start in ipairs(bridge_starting_points) do
    local filename = string.format("%s/Bridge_I%d_X%d_Y%d_F%02d.json", path, start.index, start.x, start.y, start.frames)
    local results = {}
    for i = -1, 38, 1 do
      local birds = simulateScreen(tonumber(start.rng), i)
      table.insert(results, birds)
    end
    fs.writeFile(filename, json.encode(results))
  end
end

local function generateKrazeToBridgeData(kraze_movements, frames_to_wait)
  local results = {}
  for _,kraze_movement in ipairs(kraze_movements) do
    for i = 0, frames_to_wait, 1 do
      print(string.format('Frame:%d X:%d Y:%d', i, kraze_movement.x, kraze_movement.y))
      simulateHolyKrazeMovement(i, kraze_movement.x, kraze_movement.y)
      local npcs = getPalaceNPCDirections()
      -- TODO: get Room 1 NPC Data
      while StateMonitor.SCREEN_ZONE.current ~= 10 do
        advanceFrames(1)
      end
      table.insert(results, { x=kraze_movement.x, y=kraze_movement.y, frames=i, rng=string.format("0x%8x", RNGMonitor.RNG), index=RNGMonitor.RNGIndex, npcs=npcs })
    end
  end

  return results
end

local kraze_movements = {
  { x=0, y=0 },
  { x=1, y=0 },
  { x=2, y=0 },
  { x=2, y=1 }
}

local results = generateKrazeToBridgeData(kraze_movements, 16)
fs.writeFile('/home/alex/Projects/Suikoden-Bizhawk-HUD/HolyBridge2.json', json.encode(results))


-- fs.writeFile('/home/alex/Projects/Suikoden-Bizhawk-HUD/BirdsScreen.json', json.encode(results))
-- 2: NPC 9, 3: NPC 10, 6: NPC by house
-- Screen going from 0 to 1 is perfect end timer
-- NPCs don't move after load, so can just check on end
-- Birds:
-- Slot 1: Top Right - top bird
-- Slot 2: Top Right - middle bird
-- Slot 3: Top Right - bottom bird
-- Slot 4: Bottom Left - top bird
-- Slot 5: Bottom Left - bottom bird
--
-- manual 1st frame: 2306
-- manual 2nd,3rd,4th frame: 2351
-- 5th: 2386
-- auto 2: 2387
-- auto 1: 2387
-- auto 0: 2373
-- auto -1: 2373
