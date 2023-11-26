local Modes = {
  None = 'RNG',
  Stats = 'STATS',
  Chinchironin = 'CHINCHIRONIN',
  Combat = 'COMBAT' -- Accuracy & Crit Rolls
}

local ModesList = {
  Modes.None,
  Modes.Stats,
  Modes.Chinchironin,
  Modes.Combat -- Accuracy & Crit Rolls
}

return {
  Table = Modes,
  List = ModesList
}
