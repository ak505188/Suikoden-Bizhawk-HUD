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
  LStickX = "P1 LStick X",
  LStickY = "P1 LStick Y",
  RStickX = "P1 RStick X",
  RStickY = "P1 RStick Y",
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
  LStickX = "P1 Left Stick Left / Right",
  LStickY = "P1 Left Stick Up / Down",
  RStickX = "P1 Right Stick Left / Right",
  RStickY = "P1 Right Stick Up / Down",
}

local buttonNames = OctoshockButtons
if core == "Nymashock" then
  buttonNames = NymashockButtons
end

local Buttons = {
  _values = btns
}

for btnName,btnKey in pairs(buttonNames) do
  local button = {}
  button.key = btnKey
  button.name = btnName


  if not string.match(btnName, "Stick") then
    function button:value()
      return Buttons._values[self.key]
    end

    function button:prevValue()
      return Buttons._prev_values[self.key]
    end

    function button:pressed()
      return Buttons._values[self.key] and not Buttons._prev_values[self.key]
    end

    function button:held()
      return Buttons._values[self.key]
    end

    function button:released()
      return not Buttons._values[self.key] and Buttons._prev_values[self.key]
    end
  end

  Buttons[btnName] = button
end

function Buttons:update()
  self._prev_values = self._values
  self._values = joypad.get()
end

return Buttons
