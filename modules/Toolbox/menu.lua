local Buttons = require "lib.Buttons"
local ListSelectionMenuBuilder = require "menus.Builders.List"
local RecruimentEditor = require "modules.Toolbox.Tools.RecruitmentEditor"
local CharacterEditor = require "modules.Toolbox.Tools.CharacterEditor.CharacterSelection"
local PartyJson = require "modules.Toolbox.Tools.PartyJson"
local PartyMembers = require "modules.Toolbox.Tools.PartyMembers"
local ScreenTeleport = require "modules.Toolbox.Tools.ScreenTeleport"
local ForceBattle = require "modules.Toolbox.Tools.ForceBattle"

local ToolsList = {
  "Recruitment Editor",
  "Character Editor",
  "Party JSON",
  "Party Members",
  "Screen Teleport",
  "Force Battle",
}

local ToolsMenus = {
  [ToolsList[1]] = RecruimentEditor,
  [ToolsList[2]] = CharacterEditor,
  [ToolsList[3]] = PartyJson,
  [ToolsList[4]] = PartyMembers,
  [ToolsList[5]] = ScreenTeleport,
  [ToolsList[6]] = ForceBattle,
}

local Menu = ListSelectionMenuBuilder:new(ToolsList, { name = "Tool Selection Menu" })

function Menu:run()
  self:adjustHandler()
  if Buttons.Cross:pressed() then
    local toolName = self.list[self.pos]
    local tool = ToolsMenus[toolName]
    if tool then
      self:openMenu(tool)
    end
  elseif Buttons.Circle:pressed() then
    return true
  end
  return false
end

return Menu
