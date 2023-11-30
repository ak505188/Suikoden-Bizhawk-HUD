local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local ListMenuBuilder = require "menus.Builders.List"
local MenuProperties = require "menus.Properties"
local Utils = require "lib.Utils"
local ToolboxUtils = require "modules.Toolbox.Tools.CharacterEditor.Utils"
local Battle = require "lib.Battle"

local writeToTableUsingKeylist = ToolboxUtils.writeToTableUsingKeylist

local function ItemMenu(character, item_index)
  local list = {
    { label = "Id", keys = { "Id" }, type = MenuProperties.ENTRY_TYPES.edit },
    { label = "Unknown", keys = { "Unknown" }, type = MenuProperties.ENTRY_TYPES.edit },
    { label = "Equipped", keys = { "Equipped" }, type = MenuProperties.ENTRY_TYPES.edit },
    { label = "Quantity", keys = { "Quantity" }, type = MenuProperties.ENTRY_TYPES.edit },
  }

  local Menu = ListMenuBuilder:new(list, {
    type = MenuProperties.MENU_TYPES.module,
    name = 'Character Editor Item Editor',
  })

  Menu.character = character
  Menu.item_index = item_index
  Menu.item = character.Data.Items[item_index]

  function Menu:draw()
    local item_name = Battle.getItemName(self.item.Id) or ""
    Drawer:draw({ item_name }, Drawer.anchors.TOP_LEFT)

    local draw_table = {}

    for _, entry in ipairs(self.list) do
      local value = self:readData(entry.keys)
      local str = string.format("%s: %d", entry.label, value)
      table.insert(draw_table, str)
    end

    draw_table[self.pos] = "> " .. draw_table[self.pos]
    Drawer:draw(draw_table, Drawer.anchors.TOP_LEFT)

    local controls_draw_table = {
      "Hold R1: Amount x 10",
      "Hold R2: Amount x 100",
      "Up: Up 1",
      "Down: Down 1",
      "Left: Decrease by 1",
      "Right: Increase by 1",
      "O: Back"
    }
    Drawer:draw(controls_draw_table, Drawer.anchors.TOP_RIGHT)
  end

  function Menu:adjust(amount)
    local new_pos = self.pos + amount
    if new_pos < 1 then self.pos = 1
    elseif new_pos > #self.list then self.pos = #self.list
    else self.pos = new_pos end
  end

  function Menu:edit(amount)
    local target = self.list[self.pos]
    if target.type ~= MenuProperties.ENTRY_TYPES.edit then return end

    local max = target.max or 255
    local value = self:readData(target.keys) + amount
    if value < 0 then
      value = 0
    elseif value > max then
      value = max
    end
    writeToTableUsingKeylist(self.item, Utils.cloneTableDeep(target.keys), value)
    self.character:write()
  end

  function Menu:readData(keys)
    local data = self.item
    for _, key in ipairs(keys) do
      data = data[key]
    end
    return data
  end

  function Menu:run()
    local modifier = 1
    if Buttons.R1:held() then modifier = modifier * 10 end
    if Buttons.R2:held() then modifier = modifier * 100 end
    if Buttons.Up:pressed() then
      self:adjust(modifier * -1)
    elseif Buttons.Down:pressed() then
      self:adjust(modifier * 1)
    elseif Buttons.Left:pressed() then
      self:edit(modifier * -1)
    elseif Buttons.Right:pressed() then
      self:edit(modifier * 1)
    elseif Buttons.Circle:pressed() then
      return true, self.item
    end
    return false
  end

  return Menu
end

return ItemMenu
