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
      local str = string.format("%d X:%d Y:%d 0x%x%s", slot.Slot, slot.X, slot.Y, slot.Address, slot.Hidden and " HIDDEN" or "")
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
    -- Layout from room_build_actor_table / FUN_8012ea40 (see docs/game_mechanics/Zones_Areas_and_Rooms.md).
    -- Lua buffer index = memory offset + 1.
    local slot_data = {
      Slot = i,
      Address = address,
      X = buffer[1],
      Y = buffer[2],
      SubpixelX = buffer[3], -- 0 at build, updated while walking
      SubpixelY = buffer[4],
      FacingRow = buffer[5], -- sprite row for the facing (dir 0->0, 1->1, 2->0, 3->2); not the direction itself
      Moves = buffer[6], -- descriptor flag bit 2 copied at build; exact use unverified
      ZoneLayer = buffer[7], -- layer byte of the walk-zone the actor stands in (0 = none)
      ZoneIndex = buffer[8], -- that zone's index - 1
      MemAddress1 = Utils.readFromByteTable(buffer, 9, 4), -- three 2D-sprite objects; first byte of each is the facing direction
      MemAddress2 = Utils.readFromByteTable(buffer, 13, 4),
      MemAddress3 = Utils.readFromByteTable(buffer, 17, 4),
      ActorId = buffer[21], -- slot index; 0xFF = hidden placeholder (NPC whose appearance condition failed)
      ZoneLayerCopy = buffer[22], -- copy of ZoneLayer
      SortPriority = buffer[23], -- draw order; -Y for free-roaming actors
      Unused = buffer[24], -- never written by the builder
    }
    slot_data.Hidden = slot_data.ActorId == 0xff
    -- Hidden slots have null sprite pointers; dereferencing would read address 0 and show garbage
    slot_data.Direction = slot_data.MemAddress2 ~= 0 and memory.read_u8(Address.sanitize(slot_data.MemAddress2)) or -1
    room_data[i] = slot_data
  end
  return room_data
end

return Worker
