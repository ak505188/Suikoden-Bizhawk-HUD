local Modes = {
  None = 'RNG',
  Stats = 'Stats',
  Chinchironin = 'Chinchironin',
  Combat = 'Combat' -- Accuracy & Crit Rolls
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
