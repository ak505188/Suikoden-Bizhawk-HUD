local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local ListMenuBuilder = require "menus.Builders.List"
local MenuProperties = require "menus.Properties"
local Utils = require "lib.Utils"
local ToolboxUtils = require "modules.Toolbox.Tools.CharacterEditor.Utils"
local Battle = require "lib.Battle"
local Address = require "lib.Address"

local writeToTableUsingKeylist = ToolboxUtils.writeToTableUsingKeylist

local MAX_ITEM_ID = 179
local APPRAISED = 0xff

local function readItemDefinition(id)
  if id < 1 or id > MAX_ITEM_ID then return nil end
  local ptr = memory.read_u32_le(Address.ITEM_DEFINITION_TABLE + id * 4)
  if not Address.isValidPointer(ptr) then return nil end
  ptr = Address.sanitize(ptr)
  return {
    Flags = memory.read_u16_le(ptr + 0x1c),
    FullQuantity = memory.read_u8(ptr + 0x1e),
  }
end

local function isEquipment(def) return def and (def.Flags & 0x80) ~= 0 end
local function isAntique(def) return def and (def.Flags & 0x7000) ~= 0 end

-- Resets a slot to what the game itself gives a freshly obtained item: unequipped, antiques
-- appraised, and consumables at full quantity (+0x1e). Equipment and never-consumed items hold 0.
local function applyItemDefaults(item)
  local def = readItemDefinition(item.Id)
  item.Equipped = 0
  item.Quantity = 0
  if not def then return end
  if isAntique(def) then item.Equipped = APPRAISED end
  if not isEquipment(def) then item.Quantity = def.FullQuantity end
end

local function ItemMenu(character, item_index)
  local list = {
    { label = "Id", keys = { "Id" }, type = MenuProperties.ENTRY_TYPES.edit, max = MAX_ITEM_ID },
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

    local antique = isAntique(readItemDefinition(self.item.Id))
    for _, entry in ipairs(self.list) do
      local value = self:readData(entry.keys)
      local str = string.format("%s: %d", entry.label, value)
      if antique and entry.keys[1] == "Equipped" then
        str = string.format("Appraised: %s", value ~= 0 and "Yes" or "No")
      end
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

    local key = target.keys[1]
    local current = self:readData(target.keys)
    local value
    if key == "Equipped" and isAntique(readItemDefinition(self.item.Id)) then
      -- Antiques only use this byte as an appraised flag (0 or 0xff), so any press toggles it.
      value = current ~= 0 and 0 or APPRAISED
    else
      local max = target.max or 255
      value = current + amount
      if value < 0 then
        value = 0
      elseif value > max then
        value = max
      end
    end
    writeToTableUsingKeylist(self.item, Utils.cloneTableDeep(target.keys), value)
    if key == "Id" and value ~= current then
      applyItemDefaults(self.item)
    end
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
