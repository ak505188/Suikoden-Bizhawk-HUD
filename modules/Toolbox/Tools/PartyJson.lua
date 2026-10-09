local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local Config = require "Config"
local MenuProperties = require "menus.Properties"
local ListSelectionMenuBuilder = require "menus.Builders.List"
local CharacterJSON = require "lib.CharacterJSON"

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

local function export()
  local characters = CharacterJSON.exportParty(Config.PartyJSON.FILE)
  local names = {}
  for _, c in ipairs(characters) do table.insert(names, c.key) end
  return string.format("Exported %d: %s", #characters, table.concat(names, ", "))
end

local function import()
  local keys = CharacterJSON.importFile(Config.PartyJSON.FILE)
  return string.format("Imported %d: %s", #keys, table.concat(keys, ", "))
end

local ACTIONS = {
  [EXPORT] = export,
  [IMPORT] = import,
}

local baseDraw = Menu.draw

function Menu:draw()
  baseDraw(self)
  local lines = { "File: " .. Config.PartyJSON.FILE, "Import outside battle (it edits the saved stats)." }
  for _, line in ipairs(self.status) do table.insert(lines, line) end
  Drawer:draw(lines, Drawer.anchors.BOTTOM_LEFT)
end

function Menu:run()
  self:adjustHandler()
  if Buttons.Cross:pressed() then
    local action = ACTIONS[self.list[self.pos]]
    local ok, result = pcall(action)
    -- drop Lua's "file.lua:123: " location prefix from errors, it only eats screen width
    self.status = wrap(ok and result or ("Failed: " .. tostring(result):gsub("^.-%.lua:%d+: ", "")))
  elseif Buttons.Circle:pressed() then
    self.status = {}
    return true
  end
  return false
end

return Menu
