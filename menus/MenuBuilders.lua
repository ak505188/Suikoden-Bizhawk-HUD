local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"

local function ScrollingListSelectionMenuBuilder(list, options)
  options = options or {}

  local Menu = BaseMenu:new({
    properties = {
      type = MenuProperties.MENU_TYPES.module,
      name = options.name or 'List Selection',
      control = MenuProperties.CONTROL_TYPES.scrolling_cursor,
    },
    options = list,
    pos = 1,
  })

  function Menu:draw()
    local option_draw_table = {}
    local count = 0
    while count < 10 and count + self.pos <= #self.options do
      table.insert(option_draw_table, self.options[self.pos + count])
      count = count + 1
    end

    option_draw_table[1] = "> " .. option_draw_table[1]

    Drawer:draw(option_draw_table, Drawer.anchors.TOP_LEFT)
    Drawer:draw({
      "Up: Up 1",
      "Do: Down 1",
      "Le: Up 10",
      "Ri: Down 10",
      "X: Select",
      "O: Back",
    }, Drawer.anchors.TOP_RIGHT)
  end

  function Menu:run()
    if Buttons.Down:pressed() then
      self:adjust(1)
    elseif Buttons.Up:pressed() then
      self:adjust(-1)
    elseif Buttons.Left:pressed() then
      self:adjust(-10)
    elseif Buttons.Right:pressed() then
      self:adjust(10)
    elseif Buttons.Cross:pressed() then
      return true,self.options[self.pos]
    elseif Buttons.Circle:pressed() then
      return true
    end
    return false
  end

  function Menu:adjust(amount)
    local new_pos = self.pos + amount
    if new_pos < 1 then self.pos = 1
    elseif new_pos > #self.options then self.pos = #self.options
    else self.pos = new_pos end
  end

  return Menu
end

local function ListSelectionMenuBuilder(list, options)
  options = options or {}

  local Menu = BaseMenu:new({
    properties = {
      type = options.type or MenuProperties.MENU_TYPES.module,
      name = options.name or 'List Selection',
      control = MenuProperties.CONTROL_TYPES.cursor,
    },
    options = list,
    pos = 1,
  })

  function Menu:draw()
    local option_draw_table = {}

    for _, value in ipairs(self.options) do
      table.insert(option_draw_table, value)
    end

    option_draw_table[self.pos] = "> " .. option_draw_table[self.pos]

    Drawer:draw(option_draw_table, Drawer.anchors.TOP_LEFT)
    Drawer:draw({
      "Up: Up 1",
      "Do: Down 1",
      "Le: Up 10",
      "Ri: Down 10",
      "X: Select",
      "O: Back",
    }, Drawer.anchors.TOP_RIGHT)
  end

  function Menu:run()
    if Buttons.Down:pressed() then
      self:adjust(1)
    elseif Buttons.Up:pressed() then
      self:adjust(-1)
    elseif Buttons.Left:pressed() then
      self:adjust(-10)
    elseif Buttons.Right:pressed() then
      self:adjust(10)
    elseif Buttons.Cross:pressed() then
      return true,self.options[self.pos]
    elseif Buttons.Circle:pressed() then
      return true
    end
    return false
  end

  function Menu:adjust(amount)
    local new_pos = self.pos + amount
    if new_pos < 1 then self.pos = 1
    elseif new_pos > #self.options then self.pos = #self.options
    else self.pos = new_pos end
  end

  return Menu
end

local function ToggleTableMenuBuilder(tbl, keys_list, options)
  options = options or {}

  local Menu = BaseMenu:new({
    properties = {
      type = MenuProperties.MENU_TYPES.module,
      name = options.name or 'Toggle Selection',
      control = MenuProperties.CONTROL_TYPES.cursor,
    },
    pos = 1,
    tbl = tbl,
    keys = keys_list,
  })

  function Menu:draw()
    local tbl_draw_table = {}

    for _, key in ipairs(self.keys) do
      local value = self.tbl[key] and "y" or "n"
      local str = string.format("%s %s", key, value)
      table.insert(tbl_draw_table, str)
    end

    tbl_draw_table[self.pos] = "> " .. tbl_draw_table[self.pos]

    Drawer:draw(tbl_draw_table, Drawer.anchors.TOP_LEFT)
    Drawer:draw({
      "Up: Up 1",
      "Do: Down 1",
      "Le: Up 10",
      "Ri: Down 10",
      "X: Toggle",
      "O: Back",
    }, Drawer.anchors.TOP_RIGHT)
  end

  function Menu:run()
    if Buttons.Down:pressed() then
      self:adjust(1)
    elseif Buttons.Up:pressed() then
      self:adjust(-1)
    elseif Buttons.Left:pressed() then
      self:adjust(-10)
    elseif Buttons.Right:pressed() then
      self:adjust(10)
    elseif Buttons.Cross:pressed() then
      local key = self.keys[self.pos]
      self.tbl[key] = not self.tbl[key]
    elseif Buttons.Circle:pressed() then
      return true,self.tbl
    end
    return false
  end

  function Menu:adjust(amount)
    local new_pos = self.pos + amount
    if new_pos < 1 then self.pos = 1
    elseif new_pos > #self.keys then self.pos = #self.keys
    else self.pos = new_pos end
  end

  return Menu
end

return {
  ListSelectionMenuBuilder = ListSelectionMenuBuilder,
  ScrollingListSelectionMenuBuilder = ScrollingListSelectionMenuBuilder,
  ToggleTableMenuBuilder = ToggleTableMenuBuilder,
}
