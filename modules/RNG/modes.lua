local Modes = {
  None = 'RNG',
  Stats = 'Stats',
  Chinchironin = 'Chinchironin',
  Combat = 'Combat' -- Live battle-state viewer, cross-checks known addresses against game values
}

local ModesList = {
  Modes.None,
  Modes.Stats,
  Modes.Chinchironin,
  Modes.Combat -- Live battle-state viewer
}

return {
  Table = Modes,
  List = ModesList
}
