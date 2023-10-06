local Config = {}

--- Plugins On/Off
Config.Plugins = {
  --- If disabled, using features breaks the script
  BATTLES_HUD = true
}

Config.RNG_MONITOR = {
  START_RNG_LABEL = "S:",
  RNG_INDEX_LABEL = "I:",
  RNG_VALUE_LABEL = "R:",
  GUI_X_POS = 0,
  GUI_Y_POS = 32,
  GUI_GAP = 16,
  -- These affect how far ahead in the RNG the script looks. Don't touch if things are working well.
  -- If you set these too small, the script might stop working if RNG advances too quickly.
  INITITAL_BUFFER_SIZE = 5000, -- Initial look-ahead
  BUFFER_INCREMENT_SIZE = 500, -- Later look-ahead size per frame
  BUFFER_MARGIN_SIZE = 30000, -- When difference between current length & current RNG Index is greater than this, look ahead again.
}

return Config
