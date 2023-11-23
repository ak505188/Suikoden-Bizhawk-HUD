local Names = require "lib.Characters.Names"
local Growths = require "lib.Characters.Growths"
local RecruitStatus = "lib.Characters.RecruitStatus"

local characters = {}

for _, name in pairs(Names) do
  local character = {}
  character.growths = Growths[name]
  character.recruit_address = RecruitStatus[name]
  characters[name] = character
end

return characters
