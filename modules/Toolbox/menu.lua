local Buttons = require "lib.Buttons"
local ListSelectionMenuBuilder = require "menus.Builders.List"
local RecruimentEditor = require "modules.Toolbox.Tools.RecruitmentEditor"
local CharacterEditor = require "modules.Toolbox.Tools.CharacterEditor.CharacterSelection"

local ToolsList = {
  "Recruitment Editor",
  "Character Editor",
}

local ToolsMenus = {
  [ToolsList[1]] = RecruimentEditor,
  [ToolsList[2]] = CharacterEditor
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
