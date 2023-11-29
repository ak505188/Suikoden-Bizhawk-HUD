local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local Utils = require "lib.Utils"

local function writeToTableUsingKeylist(tbl, keys, value)
  if #keys == 1 then
    tbl[keys[1]] = value
  else
    local key = table.remove(keys, 1)
    writeToTableUsingKeylist(tbl[key], keys, value)
  end
end

local function StatsMenu(character)
  local list = {
    { label = "Max HP", keys = { "HP_Max" }, max = 65535 },
    { label = "Current HP", keys = { "HP_Current" }, max = 65535 },
    { label = "MP 1", keys = { "MP", 1 } },
    { label = "MP 2", keys = { "MP", 2 } },
    { label = "MP 3", keys = { "MP", 3 } },
    { label = "MP 4", keys = { "MP", 4 } },
    { label = "LVL", keys = { "LVL" } },
    { label = "EXP", keys = { "EXP" }, max = 65535 },
    { label = "PWR", keys = { "PWR" } },
    { label = "SKL", keys = { "SKL" } },
    { label = "DEF", keys = { "DEF" } },
    { label = "SPD", keys = { "SPD" } },
    { label = "MGC", keys = { "MGC" } },
    { label = "LUK", keys = { "LUK" } },
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
    writeToTableUsingKeylist(self.character.Data.Stats, Utils.cloneTableDeep(target.keys), value)
    self.character:write()
  end

  function Menu:readData(keys)
    local data = self.character.Data.Stats
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
