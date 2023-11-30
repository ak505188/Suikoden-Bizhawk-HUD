local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local ListMenuBuilder = require "menus.Builders.List"
local MenuProperties = require "menus.Properties"
local Utils = require "lib.Utils"
local ToolboxUtils = require "modules.Toolbox.Tools.CharacterEditor.Utils"
local ItemMenu = require "modules.Toolbox.Tools.CharacterEditor.ItemMenu"
local Battle = require "lib.Battle"

local writeToTableUsingKeylist = ToolboxUtils.writeToTableUsingKeylist

local function ItemSelectionMenu(character)
  local list = {
    { label = "Count", keys = { "Count" }, type = MenuProperties.ENTRY_TYPES.edit },
    { label = "Item 1", keys = { 1 }, type = MenuProperties.ENTRY_TYPES.select },
    { label = "Item 2", keys = { 2 }, type = MenuProperties.ENTRY_TYPES.select },
    { label = "Item 3", keys = { 3 }, type = MenuProperties.ENTRY_TYPES.select },
    { label = "Item 4", keys = { 4 }, type = MenuProperties.ENTRY_TYPES.select },
    { label = "Item 5", keys = { 5 }, type = MenuProperties.ENTRY_TYPES.select },
    { label = "Item 6", keys = { 6 }, type = MenuProperties.ENTRY_TYPES.select },
    { label = "Item 7", keys = { 7 }, type = MenuProperties.ENTRY_TYPES.select },
    { label = "Item 8", keys = { 8 }, type = MenuProperties.ENTRY_TYPES.select },
    { label = "Item 9", keys = { 9 }, type = MenuProperties.ENTRY_TYPES.select },
  }
  local Menu = ListMenuBuilder:new(list, {
    type = MenuProperties.MENU_TYPES.module,
    name = 'Character Editor Item Selection',
  })

  Menu.character = character
  Menu.pos = 2

  function Menu:draw()
    local character_label = string.format("%s 0x%x", self.character.Name, self.character.Address.Stats)
    Drawer:draw({ character_label }, Drawer.anchors.TOP_LEFT, nil, true)

    local current_entry = self.list[self.pos]

    local draw_table = {
      string.format("%s: %d", self.list[1].label, self:readData(self.list[1].keys))
    }

    for i = 2, 10 do
      local entry = self.list[i]
      local item_id = self:readData(entry.keys).Id
      local item_name = Battle.getItemName(item_id)
      local label = entry.label
      if item_name and #item_name > 0 then
        label = item_name
      end
      local str = string.format("%s", label)
      table.insert(draw_table, str)
    end
    draw_table[self.pos] = "> " .. draw_table[self.pos]
    Drawer:draw(draw_table, Drawer.anchors.TOP_LEFT)

    local controls_draw_table = {
      "Up: Up 1",
      "Down: Down 1",
      "O: Back"
    }
    if current_entry.type == MenuProperties.ENTRY_TYPES.select then
      table.insert(controls_draw_table, "X: Select")
    end
    Drawer:draw(controls_draw_table, Drawer.anchors.TOP_RIGHT)

    if current_entry.type == MenuProperties.ENTRY_TYPES.edit then
      local editable_controls_draw_table = {
        "Hold R1: Amount x 10",
        "Hold R2: Amount x 100",
        "Left: Decrease by 1",
        "Right: Increase by 1",
      }
      Drawer:draw(editable_controls_draw_table, Drawer.anchors.TOP_RIGHT)
    end
  end

  function Menu:select()
    local target = self.list[self.pos]
    if target.type ~= MenuProperties.ENTRY_TYPES.select then return end

    local item_index = target.keys[1]
    local item_menu = ItemMenu(self.character, item_index)
    self:openMenu(item_menu)
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
    writeToTableUsingKeylist(self.character.Data.Items, Utils.cloneTableDeep(target.keys), value)
    self.character:write()
  end

  function Menu:readData(keys)
    local data = self.character.Data.Items
    for _, key in ipairs(keys) do
      data = data[key]
    end
    return data
  end

  function Menu:run()
    self.character:read()
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
    elseif Buttons.Cross:pressed() then
      self:select()
    elseif Buttons.Circle:pressed() then
      return true
    end
    return false
  end

  return Menu
end

return ItemSelectionMenu
