local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local MenuProperties = require "menus.Properties"
local ListMenuBuilder = require "menus.Builders.List"
local Worker = require "modules.RNG.submodules.Chinchironin.worker"
local Chinchironin = require "lib.Chinchironin"

local PlayerMenu = ListMenuBuilder:new(Chinchironin.PLAYERS_LIST, {
  type = MenuProperties.MENU_TYPES.module,
  name = 'Chinchironin Settings Menu',
})

local list = {
  'Select Player',
  'Frames To Wait',
  -- 'RNG Modifier',
}

local Menu = ListMenuBuilder:new(list, {
  type = MenuProperties.MENU_TYPES.module,
  name = 'Chinchironin Settings Menu',
})

function Menu:draw()
  local options_draw_table = {
    self.list[1],
    string.format("%s < %d >", self.list[2], Worker.FramesToAdvance)
  }

  local info_table = {
    "X: Select",
    "O: Back",
    "Hold R1: Amount x 10",
    "Hold R2: Amount x 100",
    "Up: Cursor 1 Up",
    "Down: Cursor 1 Down",
    "Left: Adjust by -1",
    "Right: Adjust by 1",
  }

  local frames_info_table = {
    "Frames to wait w/ Buffering Inputs",
    "Tai Ho: 203",
    "Gaspar: 441",
    "Gaspar at Castle: 421",
    "",
    "Auto-changes on player selection."
  }


  options_draw_table[self.pos] = string.format("> %s", options_draw_table[self.pos])
  Drawer:draw(options_draw_table, Drawer.anchors.TOP_RIGHT)
  Drawer:draw(info_table, Drawer.anchors.TOP_RIGHT)
  Drawer:draw(frames_info_table, Drawer.anchors.TOP_RIGHT)
  Worker:draw()
end

function Menu:adjustFramesToAdvance(amount)
  local new_amount = Worker.FramesToAdvance + amount
  if new_amount <= 0 then new_amount = 0 end
  Worker.FramesToAdvance = new_amount
end

function Menu:run()
  local modifier = 1
  if Buttons.R1:held() then modifier = modifier * 10 end
  if Buttons.R2:held() then modifier = modifier * 100 end
  if Buttons.Up:pressed() then
    self:adjust(modifier * -1)
  elseif Buttons.Down:pressed() then
    self:adjust(modifier * 1)
  elseif Buttons.Left:pressed() and self.pos == 2 then
    self:adjustFramesToAdvance(-1 * modifier)
  elseif Buttons.Right:pressed() and self.pos == 2 then
    self:adjustFramesToAdvance(1 * modifier)
  elseif Buttons.Cross:pressed() then
    if self.pos == 1 then
      local player = self:openMenu(PlayerMenu)
      if player then
        local frames_to_advance = 1
        if player == Chinchironin.PLAYERS.Tai_Ho then frames_to_advance = 203
        elseif player == Chinchironin.PLAYERS.Gaspar then frames_to_advance = 441 end
        Worker.Player = player
        Worker.FramesToAdvance = frames_to_advance
      end
    end
  elseif Buttons.Circle:pressed() then
    return true
  end
end

return Menu
