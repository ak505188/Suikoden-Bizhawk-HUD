local RoomMonitor = require "monitors.Room_Monitor"
local Address = require "lib.Address"
local Drawer = require "controllers.drawer"
local Utils = require "lib.Utils"
local Charmap = require "lib.Charmap"

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
  local textToDraw = {}
  table.insert(textToDraw, string.format("A:0x%x N:%d %d %d", RoomMonitor.ROOM_ADDRESS.current, RoomMonitor.NUM_SLOTS.current, RoomMonitor.HERO_X.current, RoomMonitor.HERO_Y.current))
  for i = 0, RoomMonitor.NUM_SLOTS.current do
    local slot = self.RoomData[i]
    local str = string.format("%d X:%d Y:%d", slot.Slot, slot.X, slot.Y)
    table.insert(textToDraw, str)
  end
  return Drawer:draw(textToDraw, Drawer.anchors.TOP_LEFT)
end

function Worker:getRoomData(room_address, num_slots)
  room_address = room_address or RoomMonitor.ROOM_ADDRESS.current
  num_slots = num_slots or RoomMonitor.NUM_SLOTS.current
  local room_data = {}
  for i = 0, num_slots, 1 do
    local address = room_address + (i * CHARACTER_STRUCT_SIZE)
    local buffer = mainmemory.read_bytes_as_array(address, 0x18)
    local slot_data = {
      Slot = i,
      Address = address,
      X = buffer[1],
      Y = buffer[2],
      SubpixelX = buffer[3],
      SubpixelY = buffer[4],
      Direction = buffer[5],
      MovementSpeed = buffer[6],
      Unknown1 = Utils.readFromByteTable(buffer, 7, 2),
      MemAddress1 = Utils.readFromByteTable(buffer, 9, 4),
      MemAddress2 = Utils.readFromByteTable(buffer, 13, 4),
      MemAddress3 = Utils.readFromByteTable(buffer, 17, 4),
      Unknown2 = Utils.readFromByteTable(buffer, 21, 2),
      Unknown3 = Utils.readFromByteTable(buffer, 23, 2),
    }
    room_data[i] = slot_data
  end
  return room_data
end

return Worker
