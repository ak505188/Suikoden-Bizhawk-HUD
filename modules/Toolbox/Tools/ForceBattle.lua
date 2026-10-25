local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local ForceBattle = require "lib.ForceBattle"
local ScreenTeleport = require "lib.ScreenTeleport"
local Address = require "lib.Address"

local VISIBLE_ROWS = 15

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.tool,
    name = 'Force Battle',
  },
  pos = 1,
  top = 1,
  status = "",
  battles = nil, -- ForceBattle.list() of the loaded screen, nil until read
  loadedKey = nil,
})

-- Re-reads the battle list whenever the loaded screen changes (or the field or map becomes idle again after a load).
function Menu:refresh()
  local wm, area, screen = ScreenTeleport.current()
  local ready = ForceBattle.ready()
  local key = string.format("%d/%d/%d/%d/%s", wm, area, screen, memory.read_u8(Address.GAMESTATE), tostring(ready))
  if key == self.loadedKey then return end
  self.loadedKey = key
  self.battles = ready and ForceBattle.list() or nil
  self.pos, self.top = 1, 1
end

local function rowText(e)
  local tag = e.kind == "random" and string.format("Random %d", e.group) or string.format("Scripted %d", e.scripted)
  return string.format("%s: %s", tag, e.text ~= "" and e.text or "(no enemies)")
end

function Menu:draw()
  self:refresh()
  local rows = {}
  local entries = self.battles and self.battles.entries or {}
  for i = self.top, math.min(#entries, self.top + VISIBLE_ROWS - 1) do
    table.insert(rows, (i == self.pos and "> " or "  ") .. rowText(entries[i]))
  end
  if #entries == 0 then
    table.insert(rows, self.battles and "No battles on this screen" or "Not on a field screen or the world map")
  end
  Drawer:draw(rows, Drawer.anchors.TOP_LEFT)

  Drawer:draw({
    "Up/Do: Pick battle",
    "L1/R1: -/+ 10",
    "X: Start battle",
    "O: Back",
  }, Drawer.anchors.TOP_RIGHT)

  local wm, area, screen = ScreenTeleport.current()
  local info = { string.format("Current: %d/%d/%d (WM/Area/Screen)", wm, area, screen) }
  local random = self.battles and self.battles.random
  if self.battles and self.battles.worldMap then
    table.insert(info, "World map: this region's random encounter table")
  elseif random then
    table.insert(info, string.format("Random table: rate %d, grace %d steps", random.rate, random.grace))
  elseif self.battles then
    table.insert(info, "No random encounters on this screen")
  end
  table.insert(info, "Forces the game's own encounter path. Unpause to run.")
  if self.status ~= "" then table.insert(info, self.status) end
  Drawer:draw(info, Drawer.anchors.BOTTOM_LEFT)
end

function Menu:move(amount)
  local n = self.battles and #self.battles.entries or 0
  if n == 0 then return end
  self.pos = math.max(1, math.min(n, self.pos + amount))
  if self.pos < self.top then self.top = self.pos end
  if self.pos >= self.top + VISIBLE_ROWS then self.top = self.pos - VISIBLE_ROWS + 1 end
end

function Menu:run()
  self:refresh()
  if Buttons.Down:pressed() then self:move(1)
  elseif Buttons.Up:pressed() then self:move(-1)
  elseif Buttons.R1:pressed() then self:move(10)
  elseif Buttons.L1:pressed() then self:move(-10)
  elseif Buttons.Cross:pressed() then
    local e = self.battles and self.battles.entries[self.pos]
    if e then
      local ok, why = ForceBattle.request({ group = e.group, scripted = e.scripted })
      self.status = ok and "Battle queued" or ("Can't start: " .. why)
    else
      self.status = "No battle selected"
    end
  elseif Buttons.Circle:pressed() then
    self.status = ""
    self.loadedKey = nil
    return true
  end
  return false
end

return Menu
