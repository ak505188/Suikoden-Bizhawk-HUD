local Names = require "lib.Characters.NamesList"
local Growths = require "lib.Characters.Growths"
local Addresses = require "lib.Characters.Addresses"

local characters = {}

for _, name in ipairs(Names) do
  local character = {}
  character.name = name
  character.growths = Growths[name]
  character.recruit_address = Addresses[name].RecruitmentState
  character.stats_address = Addresses[name].Stats
  characters[name] = character
end

return characters
