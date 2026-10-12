local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local ScreenTeleport = require "lib.ScreenTeleport"
local ScreenList = require "lib.ScreenList"

local FIELDS = { "WM", "Area", "Screen", "Entry" }

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do table.insert(keys, k) end
  table.sort(keys)
  return keys
end

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.tool,
    name = 'Screen Teleport',
  },
  pos = 1,
  sel = nil, -- { wm, area, screen, entryIndex }
  status = "",
})

local function areasOf(wm) return ScreenList[wm].areas end
local function screensOf(wm, area) return ScreenList[wm].areas[area].screens end
local function entriesOf(s) return screensOf(s[1], s[2])[s[3]][2] end

-- Start on the current screen when it is a known one, else the first entry.
function Menu:reset()
  local wm, area, screen = ScreenTeleport.current()
  local ok = ScreenList[wm] and areasOf(wm)[area] and screensOf(wm, area)[screen]
  if ok then
    self.sel = { wm, area, screen, 1 }
  else
    wm = sortedKeys(ScreenList)[1]
    area = sortedKeys(areasOf(wm))[1]
    self.sel = { wm, area, sortedKeys(screensOf(wm, area))[1], 1 }
  end
end

-- Move field `pos` by `amount` entries within the valid values, then fix up the fields below it.
function Menu:adjust(amount)
  local s = self.sel
  if self.pos == 4 then
    local n = #entriesOf(s)
    if n > 0 then s[4] = math.max(1, math.min(n, s[4] + amount)) end
    return
  end
  local keys
  if self.pos == 1 then keys = sortedKeys(ScreenList)
  elseif self.pos == 2 then keys = sortedKeys(areasOf(s[1]))
  else keys = sortedKeys(screensOf(s[1], s[2])) end
  local idx = 1
  for i, k in ipairs(keys) do if k == s[self.pos] then idx = i end end
  s[self.pos] = keys[math.max(1, math.min(#keys, idx + amount))]
  if self.pos == 1 then
    s[2] = sortedKeys(areasOf(s[1]))[1]
    s[3] = sortedKeys(screensOf(s[1], s[2]))[1]
  elseif self.pos == 2 then
    s[3] = sortedKeys(screensOf(s[1], s[2]))[1]
  end
  s[4] = 1
end

local function label(text) return (text and text ~= "") and (" - " .. text) or "" end

function Menu:draw()
  if not self.sel then self:reset() end
  local s = self.sel
  local w, a = ScreenList[s[1]], areasOf(s[1])[s[2]]
  local texts = { label(w.name), label(a.name), label(a.screens[s[3]][1]), "" }
  local rows = {}
  for i, name in ipairs(FIELDS) do
    local cursor = i == self.pos and "> " or "  "
    if i < 4 then
      table.insert(rows, string.format("%s%s %d%s", cursor, name, s[i], texts[i]))
    else
      local entries = entriesOf(s)
      local e = entries[s[4]]
      if e then
        table.insert(rows, string.format("%sEntry %d/%d: tile %d,%d (from %s)", cursor, s[4], #entries, e[1], e[2], e[3]))
      else
        table.insert(rows, cursor .. "Entry: none known (can't teleport here)")
      end
    end
  end
  Drawer:draw(rows, Drawer.anchors.TOP_LEFT)

  Drawer:draw({
    "Up/Do: Pick field",
    "Le/Ri: -/+ 1",
    "L1/R1: -/+ 10",
    "X: Teleport",
    "O: Back",
  }, Drawer.anchors.TOP_RIGHT)

  local cw, ca, cs = ScreenTeleport.current()
  local info = { string.format("Current: %d/%d/%d (WM/Area/Screen)", cw, ca, cs) }
  if not ScreenTeleport.ready() then table.insert(info, "Not in a field screen") end
  table.insert(info, "Loads through the game's own screen change. Unpause to run.")
  if self.status ~= "" then table.insert(info, self.status) end
  Drawer:draw(info, Drawer.anchors.BOTTOM_LEFT)
end

function Menu:run()
  if not self.sel then self:reset() end
  if Buttons.Down:pressed() then self.pos = math.min(self.pos + 1, #FIELDS)
  elseif Buttons.Up:pressed() then self.pos = math.max(self.pos - 1, 1)
  elseif Buttons.Right:pressed() then self:adjust(1)
  elseif Buttons.Left:pressed() then self:adjust(-1)
  elseif Buttons.R1:pressed() then self:adjust(10)
  elseif Buttons.L1:pressed() then self:adjust(-10)
  elseif Buttons.Cross:pressed() then
    local e = entriesOf(self.sel)[self.sel[4]]
    local ok, why
    if e then ok, why = ScreenTeleport.request(self.sel[1], self.sel[2], self.sel[3], e[1], e[2])
    else ok, why = false, "no known entry tile for this screen" end
    self.status = ok and "Teleport queued" or ("Can't teleport: " .. why)
  elseif Buttons.Circle:pressed() then
    self.status = ""
    self.sel = nil
    return true
  end
  return false
end

return Menu
