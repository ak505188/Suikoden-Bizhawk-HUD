local Config = {}

--- Plugins On/Off
Config.Plugins = {
  --- If disabled, using features breaks the script
  BATTLES_HUD = true
}

Config.RNG_HUD = {
  START_RNG_LABEL = "S: ",
  RNG_INDEX_LABEL = "I: ",
  RNG_VALUE_LABEL = "R: ",
  GUI_X_POS = 0,
  GUI_Y_POS = 32,
  GUI_GAP = 16,
  -- These affect how far ahead in the RNG the script looks. Don't touch if things are working well.
  -- If you set these too small, the script might stop working if RNG advances too quickly.
  INITITAL_BUFFER_SIZE = 5000, -- Initial look-ahead
  BUFFER_INCREMENT_SIZE = 500, -- Later look-ahead size per frame
  BUFFER_MARGIN_SIZE = 30000, -- When difference between current length & current RNG Index is greater than this, look ahead again.
}

Config.Battle_HUD = {
  REFRESH_RATE = 60, -- Refresh data every X frames
  GUI_GAP = 16,
  GUI_X = 0,
  GUI_Y = 16 * 6,
  NUM_TO_DISPLAY = 15,
}

Config.Controls = {
  GUI_X = 0,
  GUI_Y = 0,
  GUI_GAP = 16,
}

local btns = joypad.get()
local core = "Octoshock"

if btns["P1 X"] ~= nil then
  core = "Nymashock"
end

local OctoshockButtons = {
  Up = "P1 Up",
  Down = "P1 Down",
  Left = "P1 Left",
  Right = "P1 Right",
  Select = "P1 Select",
  Start = "P1 Start",
  Square = "P1 Square",
  Triangle = "P1 Triangle",
  Circle = "P1 Circle",
  Cross = "P1 Cross",
  L1 = "P1 L1",
  L2 = "P1 L2",
  L3 = "P1 L3",
  R1 = "P1 R1",
  R2 = "P1 R2",
  R3 = "P1 R3",
  ["LStick X"] = "P1 LStick X",
  ["LStick Y"] = "P1 LStick Y",
  ["RStick X"] = "P1 RStick X",
  ["RStick Y"] = "P1 RStick Y",
}

local NymashockButtons = {
  Up = "P1 D-Pad Up",
  Down = "P1 D-Pad Down",
  Left = "P1 D-Pad Left",
  Right = "P1 D-Pad Right",
  Select = "P1 Select",
  Start = "P1 Start",
  Square = "P1 □",
  Triangle = "P1 △",
  Circle = "P1 ○",
  Cross = "P1 X",
  L1 = "P1 L1",
  L2 = "P1 L2",
  L3 = "P1 Left Stick, Button",
  R1 = "P1 R1",
  R2 = "P1 R2",
  R3 = "P1 Right Stick, Button",
  ["LStick X"] = "P1 Left Stick Left / Right",
  ["LStick Y"] = "P1 Left Stick Up / Down",
  ["RStick X"] = "P1 Right Stick Left / Right",
  ["RStick Y"] = "P1 Right Stick Up / Down",
}

if core == "Octoshock" then
  Config.ButtonNames = OctoshockButtons
elseif core == "Nymashock" then
  Config.ButtonNames = NymashockButtons
end

return Config
