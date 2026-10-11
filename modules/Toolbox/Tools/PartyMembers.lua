local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local Addresses = require "lib.Characters.Addresses"
local CharacterNames = require "lib.Characters.NamesList"
local PartyChange = require "lib.PartyChange"

local HERO_ID = 8
local MAX_PARTY = 6
local VISIBLE_ROWS = 15

-- Every combat character: Id doubles as the PARTY_IDS value. Recruitment state 0 = not recruited.
local Characters = {}
for _, name in ipairs(CharacterNames) do
  local a = Addresses[name]
  if a and a.Id and a.Stats and a.RecruitmentState then
    table.insert(Characters, { name = name, id = a.Id, recruitAddress = a.RecruitmentState })
  end
end

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.tool,
    name = 'Party Members',
  },
  pos = 1,
  top = 1,
  status = "",
  visible = {},
})

-- Characters you can act on: anyone in the party, plus anyone recruited.
function Menu:refresh()
  local visible = {}
  for _, c in ipairs(Characters) do
    c.inParty = PartyChange.inParty(c.id)
    if c.inParty or memory.read_u8(c.recruitAddress) ~= 0 then table.insert(visible, c) end
  end
  self.visible = visible
  if self.pos > #visible then self.pos = math.max(#visible, 1) end
  if self.pos < self.top then self.top = self.pos end
  if self.pos >= self.top + VISIBLE_ROWS then self.top = self.pos - VISIBLE_ROWS + 1 end
end

function Menu:draw()
  local rows = {}
  for i = self.top, math.min(#self.visible, self.top + VISIBLE_ROWS - 1) do
    local c = self.visible[i]
    local pending = PartyChange.pendingFor(c.id)
    local suffix = pending == "add" and "  (will add)" or pending == "remove" and "  (will remove)" or ""
    local row = string.format("[%s] %s%s", c.inParty and "P" or " ", c.name, suffix)
    if i == self.pos then row = "> " .. row end
    table.insert(rows, row)
  end
  Drawer:draw(rows, Drawer.anchors.TOP_LEFT)

  Drawer:draw({
    "Up: Up 1",
    "Do: Down 1",
    "Le: Up 10",
    "Ri: Down 10",
    "X: Queue add / remove",
    "O: Back",
  }, Drawer.anchors.TOP_RIGHT)

  local info = {
    string.format("Party %d/%d  (after queue: %d)", PartyChange.partySize(), MAX_PARTY, PartyChange.projectedSize()),
    "Queued changes apply when you unpause. Use outside battle.",
  }
  if self.status ~= "" then table.insert(info, self.status) end
  Drawer:draw(info, Drawer.anchors.BOTTOM_LEFT)
end

function Menu:adjust(amount)
  local new_pos = self.pos + amount
  if new_pos < 1 then self.pos = 1
  elseif new_pos > #self.visible then self.pos = #self.visible
  else self.pos = new_pos end
end

function Menu:toggle()
  local c = self.visible[self.pos]
  if not c then return end
  if PartyChange.pendingFor(c.id) then
    if PartyChange.cancel(c.id) then self.status = "Cancelled " .. c.name
    else self.status = c.name .. " is already being applied" end
  elseif c.inParty then
    if c.id == HERO_ID then self.status = "The hero can't be removed"
    elseif PartyChange.projectedSize() <= 1 then self.status = "Party can't be empty"
    else PartyChange.queueRemove(c.id); self.status = "Queued remove " .. c.name end
  else
    if PartyChange.projectedSize() >= MAX_PARTY then self.status = "Party is full"
    else PartyChange.queueAdd(c.id); self.status = "Queued add " .. c.name end
  end
end

function Menu:run()
  self:refresh()
  if Buttons.Down:pressed() then self:adjust(1)
  elseif Buttons.Up:pressed() then self:adjust(-1)
  elseif Buttons.Left:pressed() then self:adjust(-10)
  elseif Buttons.Right:pressed() then self:adjust(10)
  elseif Buttons.Cross:pressed() then self:toggle()
  elseif Buttons.Circle:pressed() then
    self.status = ""
    return true
  end
  return false
end

return Menu
