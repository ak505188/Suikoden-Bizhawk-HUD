local M = {}

local Gamestates = {
  ["TITLE"] = 0,
  ["WORLD_MAP"] = 1,
  ["OVERWORLD"] = 2,
  ["BATTLE"] = 3,
  ["EVENT"] = 4,
  ["GAME_OVER"] = 99,
}

M.Gamestates = Gamestates

return M
