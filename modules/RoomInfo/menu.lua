local Buttons = require "lib.Buttons"
local Directions = require "lib.Enums.Directions"
local Worker = require "modules.RoomInfo.worker"
local Drawer = require "controllers.drawer"
local MenuProperties = require "menus.Properties"
local BaseMenu = require "menus.Base"
local RoomMonitor = require "monitors.Room_Monitor"
local MemoryViewer = require "lib.MemoryViewer"

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'ROOM_INFO_MENU'
  },
})

function Menu:draw()
  Worker:draw()
  if self.slot == nil then return end
  local draw_table = {
    string.format("CURRENT SLOT: %d/%d", self.slot, RoomMonitor.NUM_SLOTS.current),
    "Sq: Move in front of Hero",
    "Up: Up 1 Slot",
    "Do: Down 1 Slot",
    "Le: Up 10 Slots",
    "Ri: Down 10 Slots",
  }
  Drawer:draw(draw_table, Drawer.anchors.TOP_RIGHT)
  Drawer:draw(self:generateSlotDrawTable(self.slot), Drawer.anchors.TOP_RIGHT)
  -- Drawer:draw(MemoryViewer.memoryToStrTbl(Worker.RoomData[self.slot].MemAddress1, 8), Drawer.anchors.BOTTOM_RIGHT, true)
end

function Menu:init()
  self.slot = nil
  if RoomMonitor.NUM_SLOTS.current ~= nil and RoomMonitor.NUM_SLOTS.current > 0 then
    self.slot = 1
  end
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif self.slot == nil then
    return false
  elseif Buttons.Cross:pressed() then
  elseif Buttons.Square:pressed() then
    self:moveNPCInFrontOfHero()
  elseif Buttons.Up:pressed() then
    self:adjustSlot(-1)
  elseif Buttons.Down:pressed() then
    self:adjustSlot(1)
  elseif Buttons.Left:pressed() then
    self:adjustSlot(-10)
  elseif Buttons.Right:pressed() then
    self:adjustSlot(10)
  end
  return false
end

function Menu:generateSlotDrawTable(pos)
  pos = pos or self.slot
  local slot = Worker.RoomData[pos]

  local draw_tbl = {}
  table.insert(draw_tbl, string.format("X:%03d Y:%03d M:%03d", slot.X, slot.Y, slot.Moves))
  table.insert(draw_tbl, string.format("sX:%03d sY:%03d D:%03d", slot.SubpixelX, slot.SubpixelY, slot.Direction))
  table.insert(draw_tbl, string.format("M1:0x%08x", slot.MemAddress1))
  table.insert(draw_tbl, string.format("M2:0x%08x", slot.MemAddress2))
  table.insert(draw_tbl, string.format("M3:0x%08x", slot.MemAddress3))
  table.insert(draw_tbl, string.format("U1:%04x U2:%04x U3:%04x", slot.Unknown1, slot.Unknown2, slot.Unknown3))
  return draw_tbl
end

function Menu:moveNPCInFrontOfHero(pos)
  pos = pos or self.slot
  local direction = RoomMonitor.HERO_DIRECTION.current
  local x = RoomMonitor.HERO_X.current
  local y = RoomMonitor.HERO_Y.current

  if direction == Directions.DOWN then
    y = y + 2
  elseif direction == Directions.UP then
    y = y - 1
  elseif direction == Directions.LEFT then
    x = x - 2
  elseif direction == Directions.RIGHT then
    x = x + 2
  end

  local slot = Worker.RoomData[pos]
  local base_address = slot.Address

  memory.write_u8(base_address, x)
  memory.write_u8(base_address + 1, y)
end

function Menu:adjustSlot(amount)
  self.slot = self.slot + amount
  if self.slot < 1 then
    self.slot = 1
  elseif self.slot > RoomMonitor.NUM_SLOTS.current then
    self.slot = RoomMonitor.NUM_SLOTS.current
  end
end

return Menu
