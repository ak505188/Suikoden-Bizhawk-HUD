local Drawer = require "controllers.drawer"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"

-- Edits the character's persistent status byte (PersistentStats+0x16, Data.Status). Battle load
-- copies it straight into the in-battle status flags (combatant_rec+0x4a), so its bits are the
-- battle status bits. Only the statuses that persist outside battle are exposed; every other bit
-- is left as it is. Names match the game's own text ("Dilute poison" / "Recovers balloon").
local POISON = 0x01
-- Balloon's escalating stages 1-3 (stage 3 = removed from party). Cumulative: stage N always has
-- every earlier stage's bit set too (stage 3 = 0x0E), never a later stage without the earlier ones.
local BALLOON_STAGES = { 0x02, 0x04, 0x08 }
local BALLOON_MASK = 0x0E

-- The highest stage whose bit is set (0 = no balloon)
local function balloonStage(status)
  for stage = #BALLOON_STAGES, 1, -1 do
    if status & BALLOON_STAGES[stage] ~= 0 then return stage end
  end
  return 0
end

local function StatusMenu(character)
  local list = {
    { label = "Poison" },
    { label = "Balloon" },
  }
  local Menu = BaseMenu:new({
    properties = {
      type = MenuProperties.MENU_TYPES.module,
      name = 'Character Status Editor',
      control = MenuProperties.CONTROL_TYPES.cursor,
    },
    pos = 1,
    list = list,
    character = character
  })

  function Menu:draw()
    local status = self.character.Data.Status
    local character_label = string.format("%s 0x%x  Status 0x%02x", self.character.Name,
      self.character.Address.Stats, status)
    Drawer:draw({ character_label }, Drawer.anchors.TOP_LEFT, nil, true)

    local stage = balloonStage(status)
    local draw_table = {
      string.format("[%s] Poison", status & POISON ~= 0 and "X" or " "),
      string.format("Balloon %s", stage == 0 and "Off" or ("Stage " .. stage)),
    }
    draw_table[self.pos] = "> " .. draw_table[self.pos]
    Drawer:draw(draw_table, Drawer.anchors.TOP_LEFT)

    local controls_draw_table = {
      "Up: Up 1",
      "Down: Down 1",
      "Left / Right / X: Change",
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

  -- Poison toggles; Balloon steps through Off / Stage 1-3 (clamped), setting every stage bit up to
  -- the chosen stage
  function Menu:edit(amount)
    local status = self.character.Data.Status
    if self.pos == 1 then
      status = status ~ POISON
    else
      local stage = balloonStage(status)
      if amount == 0 then
        stage = (stage + 1) % (#BALLOON_STAGES + 1)
      else
        stage = math.max(0, math.min(#BALLOON_STAGES, stage + amount))
      end
      status = status & ~BALLOON_MASK & 0xFF
      for s = 1, stage do status = status | BALLOON_STAGES[s] end
    end
    self.character.Data.Status = status
    self.character:write()
  end

  function Menu:run()
    self.character:read()
    if Buttons.Up:pressed() then
      self:adjust(-1)
    elseif Buttons.Down:pressed() then
      self:adjust(1)
    elseif Buttons.Left:pressed() then
      self:edit(-1)
    elseif Buttons.Right:pressed() then
      self:edit(1)
    elseif Buttons.Cross:pressed() then
      self:edit(0)
    elseif Buttons.Circle:pressed() then
      return true
    end
    return false
  end

  return Menu
end

return StatusMenu
