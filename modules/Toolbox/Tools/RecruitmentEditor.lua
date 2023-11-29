local Address = require "lib.Address"
local Buttons = require "lib.Buttons"
local Drawer = require "controllers.drawer"
local BaseMenu = require "menus.Base"
local MenuProperties = require "menus.Properties"
local Characters = require "lib.Characters.Characters"
local CharacterNames = require "lib.Characters.NamesList"

local Recruit_First_Slot_Address = Address.RECRUIT_FIRST_SLOT

local RecruitableCharacters = {}

for _,name in ipairs(CharacterNames) do
  local character = Characters[name]
  if character.Address.Recruited then
    table.insert(RecruitableCharacters, character)
  end
end

local Menu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.tool,
    name = 'Recruitment State Editor',
  },
  pos = 1,
})

function Menu:draw()
  local characters_draw_table = {}
  local endpoint = math.min(#RecruitableCharacters, self.pos + 16)

  for i = self.pos, endpoint, 1 do
    local character = RecruitableCharacters[i]
    local name = character.Name
    local recruitment_state = self.recruits[i]
    local str = string.format("%s %x", name, recruitment_state)
    table.insert(characters_draw_table, str)
  end

  characters_draw_table[1] = "> " .. characters_draw_table[1]

  Drawer:draw(characters_draw_table, Drawer.anchors.TOP_LEFT)

  local controls_draw_table = {
    "Hold R1: Amount * 16",
    "O: Back",
    "Up: Up 1",
    "Do: Down 1",
    "Le: Recruitment State -1",
    "Ri: Recruitment State +1",
  }

  Drawer:draw(controls_draw_table, Drawer.anchors.TOP_RIGHT)
end

function Menu:updateRecruitmentData()
  local recruitment_values = memory.read_bytes_as_array(Recruit_First_Slot_Address, 108)
  local recruits = {}
  for _,character in ipairs(RecruitableCharacters) do
    local recruit_value_position = character.Address.Recruited - Recruit_First_Slot_Address + 1
    local recruit_value = recruitment_values[recruit_value_position]
    table.insert(recruits, recruit_value)
  end
  self.recruits = recruits
end

function Menu:adjust(amount)
  local new_pos = self.pos + amount
  if new_pos < 1 then self.pos = 1
  elseif new_pos > #self.recruits then self.pos = #self.recruits
  else self.pos = new_pos end
end

function Menu:changeRecruitValue(amount)
  local character = RecruitableCharacters[self.pos]
  local current_recruit_value = self.recruits[self.pos]
  local new_recruit_value = current_recruit_value + amount % 256
  memory.write_u8(character.Address.Recruited, new_recruit_value)
end

function Menu:run()
  self:updateRecruitmentData()
  local modifier = Buttons.R1:held() and 16 or 1

  if Buttons.Up:pressed() then
    self:adjust(modifier * -1)
  elseif Buttons.Down:pressed() then
    self:adjust(modifier * 1)
  elseif Buttons.Left:pressed() then
    self:changeRecruitValue(modifier * -1)
  elseif Buttons.Right:pressed() then
    self:changeRecruitValue(modifier * 1)
  elseif Buttons.Circle:pressed() then
    return true
  end
  return false
end

return Menu
