local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local Config = require "Config"
local MenuProperties = require "menus.Properties"
local ListSelectionMenuBuilder = require "menus.Builders.List"
local CharacterJSON = require "lib.CharacterJSON"
local fs = require "lib.fs"

local EXPORT = "Export party to JSON"
local IMPORT = "Import party from JSON"

local MAX_STATUS_WIDTH = 60

local Menu = ListSelectionMenuBuilder:new({ EXPORT, IMPORT }, {
  type = MenuProperties.MENU_TYPES.tool,
  name = 'Party JSON',
})

Menu.status = {}

-- Errors from CharacterJSON can be long (they carry a file path), so wrap them to the screen
local function wrap(text)
  local lines = {}
  while #text > MAX_STATUS_WIDTH do
    table.insert(lines, text:sub(1, MAX_STATUS_WIDTH))
    text = text:sub(MAX_STATUS_WIDTH + 1)
  end
  table.insert(lines, text)
  return lines
end

local function exportPath()
  return Config.PartyJSON.DIRECTORY .. "/" .. Config.PartyJSON.EXPORT_NAME
end

local function export()
  fs.mkdir(Config.PartyJSON.DIRECTORY)
  local characters = CharacterJSON.exportParty(exportPath())
  local names = {}
  for _, c in ipairs(characters) do table.insert(names, c.key) end
  return string.format("Exported %d to %s: %s", #characters, Config.PartyJSON.EXPORT_NAME, table.concat(names, ", "))
end

local function importFrom(name)
  local keys = CharacterJSON.importFile(Config.PartyJSON.DIRECTORY .. "/" .. name)
  return string.format("Imported %d from %s: %s", #keys, name, table.concat(keys, ", "))
end

-- Sorted .json file names in the party directory
local function listParties()
  local files = fs.readdir(Config.PartyJSON.DIRECTORY) or {}
  local parties = {}
  for _, f in ipairs(files) do
    if f:lower():match("%.json$") then table.insert(parties, f) end
  end
  table.sort(parties)
  return parties
end

-- Import picker state; nil while on the action list
Menu.parties = nil
Menu.partyPos = 1

local function adjustParty(self, amount)
  self.partyPos = math.max(1, math.min(#self.parties, self.partyPos + amount))
end

local function openImport(self)
  self.parties = listParties()
  self.partyPos = 1
  if #self.parties == 0 then
    self.parties = nil
    return "No .json files in " .. Config.PartyJSON.DIRECTORY
  end
  return nil
end

local baseDraw = Menu.draw

function Menu:draw()
  if self.parties then
    local list = {}
    for i, name in ipairs(self.parties) do
      table.insert(list, (i == self.partyPos and "> " or "") .. name)
    end
    Drawer:draw(list, Drawer.anchors.TOP_LEFT)
    Drawer:draw({ "Up: Up 1", "Do: Down 1", "Le: Up 10", "Ri: Down 10", "X: Import", "O: Back" }, Drawer.anchors.TOP_RIGHT)
    Drawer:draw({ "Dir: " .. Config.PartyJSON.DIRECTORY, "Import outside battle (it edits the saved stats)." },
      Drawer.anchors.BOTTOM_LEFT)
    return
  end
  baseDraw(self)
  local lines = { "Dir: " .. Config.PartyJSON.DIRECTORY, "Import outside battle (it edits the saved stats)." }
  for _, line in ipairs(self.status) do table.insert(lines, line) end
  Drawer:draw(lines, Drawer.anchors.BOTTOM_LEFT)
end

local function report(ok, result)
  -- drop Lua's "file.lua:123: " location prefix from errors, it only eats screen width
  return wrap(ok and result or ("Failed: " .. tostring(result):gsub("^.-%.lua:%d+: ", "")))
end

function Menu:runPicker()
  if Buttons.Down:pressed() then adjustParty(self, 1)
  elseif Buttons.Up:pressed() then adjustParty(self, -1)
  elseif Buttons.Left:pressed() then adjustParty(self, -10)
  elseif Buttons.Right:pressed() then adjustParty(self, 10)
  elseif Buttons.Cross:pressed() then
    local name = self.parties[self.partyPos]
    self.status = report(pcall(importFrom, name))
    self.parties = nil
  elseif Buttons.Circle:pressed() then
    self.parties = nil
  end
  return false
end

function Menu:run()
  if self.parties then return self:runPicker() end
  self:adjustHandler()
  if Buttons.Cross:pressed() then
    local choice = self.list[self.pos]
    if choice == IMPORT then
      local err = openImport(self)
      self.status = err and wrap(err) or {}
    else
      self.status = report(pcall(export))
    end
  elseif Buttons.Circle:pressed() then
    self.status = {}
    return true
  end
  return false
end

return Menu
