local Drawer = require "controllers.drawer"
local Worker = require "modules.Drops.worker"
local MenuProperties = require "menus.Properties"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"

local DropFilterMenu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'DROP_FILTER_MENU',
    control = MenuProperties.CONTROL_TYPES.cursor,
  },
})

function DropFilterMenu:init()
  self.pos = 1
  local pos_to_drop_map = {}
  for id, _ in pairs(Worker.DropTable.drops_list_for_filters) do
    table.insert(pos_to_drop_map, id)
  end

  table.sort(pos_to_drop_map)
  self.pos_to_drop_map = pos_to_drop_map
end

function DropFilterMenu:draw()
  Drawer:draw({
    "X: Toggle Drop",
    "O: Back",
    "",
  }, Drawer.anchors.TOP_RIGHT)

  local draw_table = {}
  for _, drop_id in ipairs(self.pos_to_drop_map) do
    local drop = Worker.DropTable.drops_list_for_filters[drop_id]
    table.insert(draw_table, string.format("%s %s %d", drop.show and "Y" or "N", drop.name, drop.chance))
  end
  draw_table[self.pos] = string.format("> %s", draw_table[self.pos])
  Drawer:draw(draw_table, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function DropFilterMenu:getDrop(pos)
  pos = pos or self.pos
  return Worker.DropTable.drops_list_for_filters[self.pos_to_drop_map[pos]]
end

function DropFilterMenu:toggleDropShow(pos)
  pos = pos or self.pos
  local drop = self:getDrop(pos)
  local should_show = not drop.show
  Worker.DropTable.drops_list_for_filters[drop.id].show = should_show
end

function DropFilterMenu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Cross:pressed() then
    self:toggleDropShow()
  elseif Buttons.Down:pressed() then
    self:adjustCursor(1)
  elseif Buttons.Up:pressed() then
    self:adjustCursor(-1)
  elseif Buttons.Left:pressed() then
    self:adjustCursor(-10)
  elseif Buttons.Right:pressed() then
    self:adjustCursor(10)
  end
  return false
end

function DropFilterMenu:adjustCursor(amount)
  local new_cursor = self.pos + amount
  if new_cursor < 1 then self.pos = 1
  elseif new_cursor > #self.pos_to_drop_map then self.pos = #self.pos_to_drop_map
  else self.pos = new_cursor end
end

return DropFilterMenu
