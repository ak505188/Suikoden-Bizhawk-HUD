local Drawer = require "controllers.drawer"
local BaseMenu = require "menus.Base"
local Buttons = require "lib.Buttons"
local MenuProperties = require "menus.Properties"
local Worker = require "modules.RNG.submodules.Combat.worker"

-- Flattened (party slot x field) row list, following the same pattern as the Character
-- Editor's Stats/Item menus - one row per editable field, Up/Down moves between rows,
-- Left/Right adjusts the selected row's value.
local ABILITY_SLOT_MAX = 8 -- widest real case is the 9-slot (0-indexed) inventory array

local FIELDS = {
  { key = "ActionType", label = "Type" },
  { key = "AbilitySlot", label = "Slot" },
  { key = "Target", label = "Target" },
}

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'Combat Action Editor',
    control = MenuProperties.CONTROL_TYPES.cursor,
  },
  pos = 1,
})

local function rowCount()
  local state = Worker.State
  if not state then return 0 end
  return state.PartyCount * #FIELDS
end

-- row is 1-indexed across the whole flattened list; returns the party slot (1-indexed actor
-- number) and the field definition that row edits.
local function rowInfo(row)
  local fieldIdx = ((row - 1) % #FIELDS) + 1
  local partyIdx = math.floor((row - 1) / #FIELDS) + 1
  return partyIdx, FIELDS[fieldIdx]
end

local function fieldMax(state, field)
  if field.key == "ActionType" then return Worker.ActionTypeMax end
  if field.key == "AbilitySlot" then return ABILITY_SLOT_MAX end
  if field.key == "Target" then return state.TotalCombatants end
  return 255
end

function Menu:draw()
  local state = Worker.State
  if not state then
    Drawer:draw({ "Combat Action Editor: not in battle" }, Drawer.anchors.TOP_LEFT, nil, true)
    return
  end

  Drawer:draw({
    string.format("Editing party actions - Actor:%d", state.CurrentActor),
  }, Drawer.anchors.TOP_LEFT, nil, true)

  local count = rowCount()
  local draw_table = {}
  for row = 1, count do
    local partyIdx, field = rowInfo(row)
    local c = state.Combatants[partyIdx]
    local value = c[field.key]
    local display
    if value == Worker.UnsetValue then
      -- Uninitialized/cleared - see Worker.UnsetValue's own comment. Applies to all three
      -- fields, not just ActionType, so check it before the per-field formatting below.
      display = "-- (unset)"
    elseif field.key == "ActionType" then
      display = string.format("%d %s", value, Worker.ActionTypeNames[value] or "?")
    else
      display = tostring(value)
    end
    table.insert(draw_table, string.format("P%d Id%-3d %s: %s", partyIdx, c.Id, field.label, display))
  end

  if count == 0 then
    table.insert(draw_table, "No party members")
  else
    draw_table[self.pos] = "> " .. draw_table[self.pos]
  end
  Drawer:draw(draw_table, Drawer.anchors.TOP_LEFT)

  local controls_draw_table = {
    "Up: Up 1",
    "Down: Down 1",
    "Left: Decrease",
    "Right: Increase",
    "O: Back",
  }
  Drawer:draw(controls_draw_table, Drawer.anchors.TOP_RIGHT)
end

function Menu:adjustCursor(amount)
  local count = rowCount()
  if count == 0 then return end
  local new_pos = self.pos + amount
  if new_pos < 1 then new_pos = 1
  elseif new_pos > count then new_pos = count end
  self.pos = new_pos
end

function Menu:edit(amount)
  local state = Worker.State
  if not state then return end
  local partyIdx, field = rowInfo(self.pos)
  local c = state.Combatants[partyIdx]
  if not c then return end

  local max = fieldMax(state, field)
  -- Unset (255) isn't itself a value in the valid range - treat it as "just below the range"
  -- so the first Left or Right press lands on 0 (the lowest real value) instead of jumping
  -- straight to max the way a literal 255+/-1 clamp would.
  local current = c[field.key]
  if current == Worker.UnsetValue then current = -1 end
  local value = current + amount
  if value < 0 then value = 0
  elseif value > max then value = max end

  Worker:writeCombatantField(partyIdx, field.key, value)
end

function Menu:run()
  if Buttons.Circle:pressed() then
    return true
  end

  if not Worker.State then return false end

  if Buttons.Up:pressed() then
    self:adjustCursor(-1)
  elseif Buttons.Down:pressed() then
    self:adjustCursor(1)
  elseif Buttons.Left:pressed() then
    self:edit(-1)
  elseif Buttons.Right:pressed() then
    self:edit(1)
  end
  return false
end

return Menu
