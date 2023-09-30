local Areas = require "lib.Enums.Areas.Areas_All"

local EncounterTable = {
  [Areas.CAVE_OF_THE_PAST] = {
    name = "Cave of the Past",
    areaType = 2,
    encounterRate = 2,
    champVals = { 61, 123, 184, 66, 132, 198, 127, 189, 255, 250, 312 },
    encounters = { "010000", "101000", "101010", "020000", "202000", "202020", "201000", "101020", "333020", "333010", "333101" },
    enemies = { "Banshee", "Clay Doll", "Red Elemental" }
  },
  [Areas.WORLD_MAP_DRAGON_KNIGHT_FORTRESS] = {
    name = "Dragon Knights WM",
    areaType = 1,
    champVals = { 73, 147, 220, 75, 150, 156, 312, 373 },
    encounters = { "100000", "110000", "111000", "020000", "202000", "303000", "333030", "111203" },
    enemies = { "Ivy", "Shadow Man", "Mirage" }
  },
  [Areas.DRAGONS_DEN] = {
    name = "Dragon's Den",
    areaType = 2,
    encounterRate = 3,
    champVals = { 75, 73, 147, 220, 148, 291, 363 },
    encounters = { "020000", "010000", "101000", "111000", "201000", "333020", "333101" },
    enemies = { "Magic Shield", "Sunshine King", "Black Elemental" }
  },
  [Areas.DWARF_TRAIL] = {
    name = "Dwarves Trail",
    areaType = 2,
    encounterRate = 2,
    champVals = { 160, 33, 66, 99, 31, 63, 94, 25, 51, 76, 109, 108, 142, 141 },
    encounters = { "222101", "010000", "101000", "101010", "020000", "202000", "222000", "030000", "303000", "333000", "333010", "333020", "333101", "333102" },
    enemies = { "Eagle Man", "Dwarf", "Death Boar" }
  },
  [Areas.DWARVES_VAULT] = {
    name = "Dwarves' Vault",
    areaType = 2,
    encounterRate = 2,
    champVals = { 37, 75, 112, 37, 75, 112, 34, 69, 103, 51, 76, 141, 178, 216 },
    encounters = { "010000", "101000", "111000", "040000", "404000", "444000", "020000", "202000", "222000", "303000", "333000", "222010", "222101", "222111" },
    enemies = { "Death Machine R", "Crimson Dwarf", "Death Boar", "Death Machine B" }
  },
  [Areas.GREAT_FOREST] = {
    name = "Great Forest",
    areaType = 2,
    encounterRate = 2,
    champVals = { 30, 90, 180, 60, 46, 69, 117, 45 },
    encounters = { "100000", "111000", "111222", "220000", "344000", "444344", "444333", "444444" },
    enemies = { "Kobold S", "Kobold B", "Holly Spirit", "Holly Boy" }
  },
  [Areas.WORLD_MAP_GREGMINSTER] = {
    name = "Gregminster WM 1",
    areaType = 1,
    champVals = { 7, 22, 36, 12, 10, 12, 24, 30, 22 },
    encounters = { "100000", "111000", "222222", "330000", "400000", "500000", "550000", "222500", "433000" },
    enemies = { "BonBon", "Mosquito", "Crow", "Wild Boar", "Red Solider Ant" }
  },
  [Areas.WORLD_MAP_GREGMINSTER_2] = {
    name = "Gregminster WM 2",
    areaType = 1,
    champVals = { 331, 82, 165, 247, 84, 168, 252, 85, 171, 256, 333, 415, 418 },
    encounters = { "111200", "100000", "110000", "111000", "200000", "220000", "222000", "300000", "330000", "333000", "111300", "111220", "111300" },
    enemies = { "Ninja Master", "Simurgh", "Orc" }
  },
  [Areas.GREGMINSTER_PALACE_2] = {
    name = "Gregminster Palace",
    areaType = 2,
    encounterRate = 3,
    champVals = { 88, 168, 252, 168, 87, 174, 261, 342, 351, 349, 340 },
    encounters = { "400000", "110000", "111000", "220000", "300000", "303000", "333000", "111050", "333050", "333040", "212040" },
    enemies = { "Imperial Guards Sa", "Imperial Guards Sw", "Phantom", "Colossus", "Ekidonna" }
  },
  [Areas.KALEKKA] = {
    name = "Kalekka",
    areaType = 2,
    encounterRate = 4,
    champVals = { 55, 105, 157, 210, 108, 216, 213 },
    encounters = { "030000", "101000", "101100", "101101", "202000", "202202", "101202" },
    enemies = { "Demon Hound", "Hawk Man", "Shadow" }
  },
  [Areas.WORLD_MAP_KIROV] = {
    name = "Kirov WM",
    areaType = 2,
    champVals = { 46, 93, 139, 102, 153, 141, 51, 48, 96 },
    encounters = { "010000", "101000", "101010", "202000", "202020", "101030", "020000", "030000", "303000" },
    enemies = { "Dagon", "Grizzly Bear", "Siren" }
  },
  [Areas.LEPANTS_MANSION] = {
    name = "Lepant's Mansion",
    areaType = 2,
    encounterRate = 2,
    champVals = { 28, 81, 162 },
    encounters = { "300000", "211000", "111222" },
    enemies = { "Robot Soldier B", "Robot Soldier Y", "SlotMan" }
  },
  [Areas.WORLD_MAP_LORIMAR] = {
    name = "Lorimar WM",
    areaType = 1,
    champVals = { 223, 58, 117, 55, 111, 166, 60, 120, 226, 225, 283 },
    encounters = { "333100", "400000", "440000", "300000", "330000", "333000", "200000", "220000", "333200", "333400", "333440" },
    enemies = { "Whip Wolf", "Sorcerer", "Hell Hound", "Grave Master" }
  },
  [Areas.MAGICIANS_ISLAND] = {
    name = "Magician's Island",
    areaType = 2,
    encounterRate = 4,
    champVals = { 18, 27, 25, 12, 18, 27, 25, 12, 18 },
    encounters = { "111100", "111111", "111220", "220000", "111100", "111111", "111220", "220000", "222000" },
    enemies = { "Holly Boy", "FurFur" }
  },
  [Areas.WORLD_MAP_MORAVIA] = {
    name = "Moravia WM",
    areaType = 1,
    champVals = { 76, 153, 229, 78, 156, 234, 79, 159, 309, 313, 388, 393 },
    encounters = { "100000", "110000", "111000", "200000", "220000", "222000", "300000", "303000", "111300", "222300", "111303", "222303" },
    enemies = { "Rabbit Bird", "Mirage", "Earth Golem" }
  },
  [Areas.MORAVIA] = {
    name = "Moravia",
    areaType = 2,
    encounterRate = 3,
    champVals = { 301, 378, 451, 78, 156, 81, 162, 78, 156, 382, 315, 315, 381, 396, 396, 457 },
    encounters = { "222100", "222110", "222122", "300000", "330000", "400000", "440000", "500000", "550000", "222410", "333400", "555400", "222330", "333440", "535440", "222551" },
    enemies = { "Whip Master", "HellHound", "Ninja", "Magus", "EliteSoldier" }
  },
  [Areas.MT_SEIFU] = {
    name = "Mt. Seifu",
    areaType = 2,
    encounterRate = 2,
    champVals = { 36, 15, 25, 21, 15 },
    encounters = { "111111", "220000", "232000", "550000", "440000" },
    enemies = { "Soldier Ant", "Bandit R", "Bandit Y", "Bandit G", "Black Wild Boar" }
  },
  [Areas.MT_TIGERWOLF] = {
    name = "Mt. Tigerwolf",
    areaType = 2,
    encounterRate = 3,
    champVals = { 54, 27, 31, 31, 13 },
    encounters = { "111111", "220000", "333000", "333000", "200000" },
    enemies = { "Slasher Rabbit", "Giant Snail", "Killer Slime" }
  },
  [Areas.NECLORDS_CASTLE] = {
    name = "Neclord's Castle",
    areaType = 2,
    encounterRate = 2,
    champVals = { 69, 70, 138, 67, 135, 202, 271, 273, 342 },
    encounters = { "020000", "010000", "202000", "030000", "303000", "333000", "333020", "333010", "333102" },
    enemies = { "Hell Unicorn", "Demon Sorcerer", "Larvae" }
  },
  [Areas.WORLD_MAP_PANNU_YAKUTA] = {
    name = "Pannu Yakuta WM",
    areaType = 2,
    champVals = { 60, 90, 120, 120, 121, 150, 150, 151 },
    encounters = { "220000", "111000", "111300", "222300", "242300", "111330", "222330", "141330" },
    enemies = { "Kobold S", "Kobold B", "Kobold M", "Strong Arm" }
  },
  [Areas.PANNU_YAKUTA] = {
    name = "Pannu Yakuta",
    areaType = 2,
    encounterRate = 2,
    champVals = { 117, 40, 162, 78, 117, 117, 156, 195, 81, 121 },
    encounters = { "222000", "500000", "444500", "011000", "111000", "333000", "233100", "231330", "440000", "444000" },
    enemies = { "Veteran Soldier Sa", "Veteran Soldier Sp", "Veteran Soldier B", "Devil Shield", "Devil Armor" }
  },
  [Areas.WORLD_MAP_SCARLETICIA] = {
    name = "Scarleticia WM",
    areaType = 1,
    champVals = { 39, 78, 117, 42, 84, 126, 43, 87, 130, 160, 159, 169 },
    encounters = { "100000", "110000", "111000", "200000", "220000", "222000", "300000", "330000", "333000", "111300", "111200", "222300" },
    enemies = { "Holly Fairy", "Mad Ivy", "Creeper" }
  },
  [Areas.SCARLETICIA] = {
    name = "Scarleticia",
    areaType = 2,
    encounterRate = 3,
    champVals = { 84, 87, 130, 261, 48, 178 },
    encounters = { "110000", "220000", "222000", "222222", "300000", "222300" },
    enemies = { "Mad Ivy", "Creeper", "Nightmare" }
  },
  [Areas.SEEK_VALLEY] = {
    name = "Seek Valley",
    areaType = 2,
    encounterRate = 2,
    champVals = { 73, 147, 220, 76, 153, 229, 79, 78, 223, 226, 231, 232 },
    encounters = { "010000", "101000", "101010", "020000", "202000", "202020", "040000", "030000", "101020", "101040", "202030", "202040" },
    enemies = { "Ivy", "Rock Buster", "Queen Ant", "Wyvern" }
  },
  [Areas.WORLD_MAP_SEIKA] = {
    name = "Seika WM",
    areaType = 1,
    champVals = { 69, 33, 99, 21, 90, 42, 64, 99 },
    encounters = { "222300", "202000", "222222", "040000", "111111", "404000", "111300", "222131" },
    enemies = { "Killer Rabbit", "Flying Squirrel", "Beast Commander", "Roc" }
  },
  [Areas.SHASARAZADE] = {
    name = "Shasarazade",
    areaType = 2,
    encounterRate = 3,
    champVals = { 324, 162, 243, 159, 238, 318, 82 },
    encounters = { "111010", "101000", "111000", "202000", "222000", "222020", "030000" },
    enemies = { "Elite Soldier", "Siren", "Kerberos" }
  },
  [Areas.SONIERE_PRISON] = {
    name = "Soniere Prison",
    areaType = 2,
    encounterRate = 2,
    champVals = { 82, 157, 40, 121, 217, 48, 144, 169 },
    encounters = { "120000", "222100", "300000", "333000", "333440", "400000", "444000", "333400" },
    enemies = { "Viperman", "Delf", "Red Slime", "Nightmare" }
  },
  [Areas.TORAN_CASTLE] = {
    name = "Toran Castle",
    areaType = 2,
    encounterRate = 2,
    champVals = { 48, 72, 45, 67, 25, 93, 97 },
    encounters = { "202000", "222000", "330000", "333000", "100000", "333100", "222100" },
    enemies = { "Ghost Armor", "Oannes", "Giant Slug" }
  }
}

return EncounterTable
