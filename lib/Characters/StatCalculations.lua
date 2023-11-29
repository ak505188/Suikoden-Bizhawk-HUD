local RNG = require "lib.RNG"

local StatGrowths = {
  [0x0] = { 242, 172, 98 },
  [0x1] = { 336, 224, 124 },
  [0x2] = { 431, 288, 144 },
  [0x3] = { 525, 364, 144 },
  [0x4] = { 646, 435, 144 },
  [0x5] = { 741, 499, 157 },
  [0x6] = { 835, 563, 177 },
  [0x7] = { 970, 614, 216 },
  [0x8] = { 1118, 672, 249 },
  [0x9] = { 1682, 420, 196 },
  [0xA] = { 1050, 352, 164 },
  [0xB] = { 714, 608, 492 },
  [0xC] = { 538, 480, 459 },
  [0xD] = { 646, 128, 689 },
  [0xE] = { 94, 140, 2560 },
  [0xF] = { 714, 608, 492 }
};

local HPGrowths = {
  [0x0] = { 835, 1472, 984 },
  [0x1] = { 1145, 1632, 984 },
  [0x2] = { 1441, 1856, 1115 },
  [0x3] = { 1805, 2048, 1181 },
  [0x4] = { 2021, 2304, 1115 },
  [0x5] = { 2236, 2624, 1115 },
  [0x6] = { 2613, 2816, 1115 },
  [0x7] = { 2991, 3008, 1181 },
  [0x8] = { 3368, 3328, 1247 },
  [0x9] = { 5052, 1280, 1312 },
  [0xA] = { 2667, 1152, 984 },
  [0xB] = { 1913, 2496, 2297 },
  [0xC] = { 1077, 1984, 2100 },
  [0xD] = { 2021, 2304, 1115 },
  [0xE] = { 889, 1491, 4365 },
  [0xF] = { 714, 608, 492 }
};

local LevelupStatOrder = {
  'PWR',
  'SKL',
  'DEF',
  'SPD',
  'MGC',
  'LUK',
  'HP',
}

local function getGrowthValue(growth, stat, level)
  local levelCutoffs = { 20, 60 };

  if (growth == 9) then
    levelCutoffs[1] = 15;
  end

  local levelModifier = 1;
  for _, cutoff in ipairs(levelCutoffs) do
    if level >= cutoff then
      levelModifier = levelModifier + 1
    end
  end

  if (stat == 'HP') then
    return HPGrowths[growth][levelModifier];
  end

  return StatGrowths[growth][levelModifier];
end


local function calculateStatLevelUp(character, level, stat, rng)
  local growth = stat == 'HP' and character.Growths.PWR or character.Growths[stat]
  local growth_value = getGrowthValue(growth, stat, level)
  local is_HP = stat == 'HP'
  local small_RNG = RNG.getRNG2(rng)
  local max_RNG = is_HP and small_RNG & 0x1ff or small_RNG & 0xff;
  return math.floor((growth_value + max_RNG) / 256);
end

return {
  getGrowthValue = getGrowthValue,
  calculateStatLevelUp = calculateStatLevelUp,
  LevelupStatOrder = LevelupStatOrder,
}
