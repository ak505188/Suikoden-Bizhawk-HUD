-- All non basic functionality should be split into module.
-- Can probably keep Hero data and ROOM_POINTER
local Address = require "lib.Address"
local Drawer = require "controllers.drawer"
local Utils = require "lib.Utils"

local initVarState = {
  current = nil,
  previous = nil,
  changed = nil
}

local RoomMonitor = {
  ROOM_ADDRESS = Utils.cloneTable(initVarState),
  CANDIDATE_POINTER_1 = Utils.cloneTable(initVarState),
  CANDIDATE_POINTER_2 = Utils.cloneTable(initVarState),
  NUM_SLOTS = Utils.cloneTable(initVarState),
  NUM_SLOTS_OLD = Utils.cloneTable(initVarState),
  HERO_X = Utils.cloneTable(initVarState),
  HERO_Y = Utils.cloneTable(initVarState),
  HERO_DIRECTION = Utils.cloneTable(initVarState),
}

function RoomMonitor:draw()
  local textToDraw = {
    string.format("%08x X:%d Y:%d D:%d", self.ROOM_ADDRESS.current, self.HERO_X.current, self.HERO_Y.current, self.HERO_DIRECTION.current),
    -- string.format("RP:%08x C1:%08x C2:%08x", self.ROOM_ADDRESS.current, self.CANDIDATE_POINTER_1.current, self.CANDIDATE_POINTER_2.current),
  }
  return Drawer:draw(textToDraw, Drawer.anchors.TOP_LEFT)
end

function RoomMonitor:run()
  self:updateState("ROOM_ADDRESS", memory.read_u32_le(Address.ROOM_POINTER))
  self:updateState("CANDIDATE_POINTER_1", memory.read_u32_le(0x199f68))
  self:updateState("CANDIDATE_POINTER_2", memory.read_u32_le(0x199f94))

  local num_slots = nil
  local num_slots_old = nil
  if Address.isValidPointer(RoomMonitor.ROOM_ADDRESS.current) then
    -- Exact count, written by room_build_actor_table (Ghidra 0x8012ed84) when the room is built.
    num_slots = memory.read_u8(Address.ROOM_SLOT_COUNT)
    -- Byte at ROOM_ADDRESS - 0x10 is the last record of the (count * 8) slot-index table, i.e. count - 1.
    num_slots_old = memory.read_u8(Address.sanitize(RoomMonitor.ROOM_ADDRESS.current - 0x10))
  end
  self:updateState("NUM_SLOTS", num_slots)
  self:updateState("NUM_SLOTS_OLD", num_slots_old)
  self:updateState("HERO_X", memory.read_u8(Address.HERO_X))
  self:updateState("HERO_Y", memory.read_u8(Address.HERO_Y))
  local hero_dir_address = Address.sanitize(memory.read_u32_le(Address.HERO_DIRECTION_PTR))
  self:updateState("HERO_DIRECTION", memory.read_u8(hero_dir_address))
end

function RoomMonitor:init()
  self:run()
end

function RoomMonitor:updateState(key, value)
  local previousValue = self[key].current
  self[key].current = value
  self[key].previous = previousValue
  self[key].changed = value ~= previousValue
end

return RoomMonitor
