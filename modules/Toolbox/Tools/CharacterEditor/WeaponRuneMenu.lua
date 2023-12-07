
local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local Utils = require "lib.Utils"
local ToolboxUtils = require "modules.Toolbox.Tools.CharacterEditor.Utils"

local writeToTableUsingKeylist = ToolboxUtils.writeToTableUsingKeylist

local function StatsMenu(character)
  local list = {
    { label = "Weapon Class", keys = { "Weapon", "Type" }, max = 255 },
    { label = "Weapon Level", keys = { "Weapon", "Level" }, max = 255 },
    { label = "Equipped Rune Piece Type", keys = { "Weapon", "Rune_Piece_Type" }, max = 255 },
    { label = "Fire Piece Count", keys = { "Weapon", "Fire_Piece_Count" }, max = 255 },
    { label = "Water Piece Count", keys = { "Weapon", "Water_Piece_Count" }, max = 255 },
    { label = "Wind Piece Count", keys = { "Weapon", "Wind_Piece_Count" }, max = 255 },
    { label = "Thunder Piece Count", keys = { "Weapon", "Thunder_Piece_Count" }, max = 255 },
    { label = "Earth Piece Count", keys = { "Weapon", "Earth_Piece_Count" }, max = 255 },
    { label = "Rune ID", keys = { "Rune", "Id" }, max = 255 },
    { label = "Rune Lock", keys = { "Rune", "Locked" }, max = 255 },
  }
  local Menu = BaseMenu:new({
    properties = {
      type = MenuProperties.MENU_TYPES.module,
      name = 'Character Stat Editor',
      control = MenuProperties.CONTROL_TYPES.cursor,
    },
    pos = 1,
    list = list,
    character = character
  })

  function Menu:draw()
    local character_label = string.format("%s 0x%x", self.character.Name, self.character.Address.Stats)
    Drawer:draw({ character_label }, Drawer.anchors.TOP_LEFT, nil, true)

    local draw_table = {}
    for _, entry in ipairs(self.list) do
      local label = entry.label
      local value = self:readData(entry.keys)
      local str = string.format("%s %d", label, value)
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
    local max = target.max or 255
    local value = self:readData(target.keys) + amount
    if value < 0 then
      value = 0
    elseif value > max then
      value = max
    end
    writeToTableUsingKeylist(self.character.Data, Utils.cloneTableDeep(target.keys), value)
    self.character:write()
  end

  function Menu:readData(keys)
    local data = self.character.Data
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
    elseif Buttons.Circle:pressed() then
      return true
    end
    return false
  end

  return Menu
end

return StatsMenu
