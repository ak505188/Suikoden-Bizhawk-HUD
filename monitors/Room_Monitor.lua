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
  HERO_X = Utils.cloneTable(initVarState),
  HERO_Y = Utils.cloneTable(initVarState),
  HERO_DIRECTION = Utils.cloneTable(initVarState),
}

function RoomMonitor:draw()
  local textToDraw = {
    string.format("X:%d Y:%d D:%d", self.HERO_X.current, self.HERO_Y.current, self.HERO_DIRECTION.current),
  }
  return Drawer:draw(textToDraw, Drawer.anchors.TOP_LEFT)
end

function RoomMonitor:run()
  self:updateState("ROOM_ADDRESS", memory.read_u32_le(Address.ROOM_POINTER))
  self:updateState("CANDIDATE_POINTER_1", memory.read_u32_le(0x199f68))
  self:updateState("CANDIDATE_POINTER_2", memory.read_u32_le(0x199f94))

  local num_slots = nil
  if Address.isValidPointer(RoomMonitor.ROOM_ADDRESS.current) and Address.isValidPointer(RoomMonitor.CANDIDATE_POINTER_1.current) then
    num_slots = (RoomMonitor.CANDIDATE_POINTER_1.current - 0x8 - RoomMonitor.ROOM_ADDRESS.current) / 0x18
  end
  self:updateState("NUM_SLOTS", num_slots)
  self:updateState("HERO_X", memory.read_u8(Address.HERO_X))
  self:updateState("HERO_Y", memory.read_u8(Address.HERO_Y))
  self:updateState("HERO_DIRECTION", memory.read_u8(Address.HERO_DIRECTION))
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
