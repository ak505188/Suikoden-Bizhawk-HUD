local RoomMonitor = require "monitors.Room_Monitor"
local Address = require "lib.Address"
local Drawer = require "controllers.drawer"
local Utils = require "lib.Utils"

local CHARACTER_STRUCT_SIZE = 0x18

local Worker = {
  RoomData = {}
}

function Worker:run()
  self.RoomData = Worker:getRoomData()
end

function Worker:init() end

function Worker:onChange() end

function Worker:draw()
  local monitorStr1 = string.format(
    "X:%d Y:%d D:%d %08x",
    RoomMonitor.HERO_X.current,
    RoomMonitor.HERO_Y.current,
    RoomMonitor.HERO_DIRECTION.current,
    RoomMonitor.ROOM_ADDRESS.current
  )
  local monitorStr2 = string.format(
    "N:%s O:%s %08x %08x",
    tostring(RoomMonitor.NUM_SLOTS.current),
    tostring(RoomMonitor.NUM_SLOTS_OLD.current),
    RoomMonitor.CANDIDATE_POINTER_1.current,
    RoomMonitor.CANDIDATE_POINTER_2.current
  )
  Drawer:draw({ monitorStr1, monitorStr2 }, Drawer.anchors.TOP_LEFT, nil, true)
  if RoomMonitor.NUM_SLOTS.current == nil then return end
  local textToDraw = {}
  -- table.insert(textToDraw, string.format("A:0x%x N:%d %d %d", RoomMonitor.ROOM_ADDRESS.current, RoomMonitor.NUM_SLOTS.current, RoomMonitor.HERO_X.current, RoomMonitor.HERO_Y.current))

  if RoomMonitor.NUM_SLOTS.current > 0 then
    for i = 1, RoomMonitor.NUM_SLOTS.current do
      local slot = self.RoomData[i]
      -- local str = string.format("%d X:%d Y:%d", slot.Slot, slot.X, slot.Y)
      local str = string.format("%d X:%d Y:%d 0x%x", slot.Slot, slot.X, slot.Y, slot.Address)
      table.insert(textToDraw, str)
    end
  end
  return Drawer:draw(textToDraw, Drawer.anchors.TOP_LEFT)
end

function Worker:getRoomData()
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

return Worker
