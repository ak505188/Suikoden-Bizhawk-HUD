local Names = require "Names"
local Config = require "Config"

local GUI_X = Config.Controls.GUI_X
local GUI_GAP = Config.Controls.GUI_GAP
local GUI_Y = Config.Controls.GUI_Y

local Modes = {
  ENCOUNTER_MODE = 1,
  RNG_MODE = 2,
  AREAS_MODE = 3
}
local ModesList = {
  "Encounters",
  "RNG",
  "Areas"
}

local Controls = {
  Mode = Modes.ENCOUNTER_MODE,
  State = {
    PAUSED_BY_CONTROLS = false,
    LIST_POS = 1,
  },
  Buttons = {
    MENU_BUTTON = { btn = "P1 R2", cooldown = -1 },
    NEXT_MODE = { btn = "P1 R1", cooldown = 0, default_cd = 10 },
    PREV_MODE = { btn = "P1 L1", cooldown = 0, default_cd = 10 },
    TOGGLE_LOCK = { btn = "P1 Triangle", cooldown = 0, default_cd = 10 },
    CONFIRM = { btn = "P1 Cross", cooldown = 0, default_cd = 10 },
    POS_INCREMENT = { btn = "P1 Down", cooldown = 0 },
    POS_DECREMENT = { btn = "P1 Up", cooldown = 0 },
    POS_INCREASE = { btn = "P1 Right", cooldown = 0 },
    POS_DECREASE = { btn = "P1 Left", cooldown = 0 },
  },
}

local function buttonIsPressed(button)
  local pressed = joypad.get()[button.btn]
  if pressed and button.cooldown <= 0 then
    if button.cooldown == 0 then
      local cooldown = button.default_cd or Config.Controls.BUTTON_COOLDOWN
      button.cooldown = cooldown
    end
    return true
  end
  return false
end

function Controls:reduceCooldowns()
  for _, button in pairs(self.Buttons) do
    if button.cooldown > 0 then
      button.cooldown = button.cooldown - 1
    end
  end
end

function Controls:buttonIsOffCooldown(buttonKey)
  return self.Cooldowns[buttonKey] == 0
end

function Controls:init(RNG_HUD, Battles_HUD)
  self.RNG_HUD = RNG_HUD
  self.Battles_HUD = Battles_HUD
end

local function drawTable(strs, X, Y, Gap)
  local x = X or GUI_X
  local y = Y or GUI_Y
  local gap = Gap or GUI_GAP
  for _,row in ipairs(strs) do
    gui.text(x, y, row)
    y = y + gap
  end
end

function Controls:drawHUD()
  if self.State.PAUSED_BY_CONTROLS then
    local lock = "Lock"
    if self.Battles_HUD.Locked then lock = "Unlock" end

    local strs = {
      string.format("%s Mode", self:getModeName()),
      "L1: Next mode",
      "R1: Prev mode",
      "Tr: " .. lock .. " area",
    }

    if self.Mode == Modes.ENCOUNTER_MODE then
      table.insert(strs, "X: Go to Battle")
      table.insert(strs, "Up: Up 1")
      table.insert(strs, "Do: Down 1")
      table.insert(strs, "Le: Up 10")
      table.insert(strs, "Ri: Down 10")
    elseif self.Mode == Modes.RNG_MODE then
      table.insert(strs, "Up: RNGIndex -1")
      table.insert(strs, "Dn: RNGIndex +1")
      table.insert(strs, "Le: RNGIndex -25")
      table.insert(strs, "Ri: RNGIndex +25")
    elseif self.Mode == Modes.AREAS_MODE then
      table.insert(strs, "X: Go to Battle")
      table.insert(strs, "Up: Up 1")
      table.insert(strs, "Do: Down 1")
    end
    drawTable(strs, GUI_X, GUI_Y, GUI_GAP)
  else
    gui.text(GUI_X, GUI_Y, "Hold R2: Controls")
  end
end

function Controls:adjustListPos(amount)
  local pos = self.State.LIST_POS + amount
  if pos < 1 then pos = 1 end
  self.State.LIST_POS = pos
end

function Controls:getModeName(mode)
  mode = mode or self.Mode
  mode = mode % #ModesList
  if mode == 0 then return ModesList[#ModesList] end
  return ModesList[mode]
end

function Controls:switchMode(amount)
  local newMode = (self.Mode + amount) % #ModesList
  if newMode == 0 then newMode = #ModesList end
  self.Mode = newMode
end

function Controls:run()
  if buttonIsPressed(self.Buttons.MENU_BUTTON) then
    if not client.ispaused() then
      client.pause()
      self.State.PAUSED_BY_CONTROLS = true
    end

    while buttonIsPressed(self.Buttons.MENU_BUTTON) do
      emu.yield()

      if buttonIsPressed(self.Buttons.NEXT_MODE) then
        self:switchMode(1)
      elseif buttonIsPressed(self.Buttons.PREV_MODE) then
        self:switchMode(-1)
      end

      if buttonIsPressed(self.Buttons.TOGGLE_LOCK) then
        self.Battles_HUD:toggleLock()
      end

      if self.Mode == Modes.RNG_MODE then
        if buttonIsPressed(self.Buttons.POS_DECREMENT) then
          self.RNG_HUD:adjustRNGIndex(-1)
        elseif buttonIsPressed(self.Buttons.POS_INCREMENT) then
          self.RNG_HUD:adjustRNGIndex(1)
        elseif buttonIsPressed(self.Buttons.POS_DECREASE) then
          self.RNG_HUD:adjustRNGIndex(-25)
        elseif buttonIsPressed(self.Buttons.POS_INCREASE) then
          self.RNG_HUD:adjustRNGIndex(25)
        end
      end

      if self.Mode == Modes.AREAS_MODE then
        if buttonIsPressed(self.Buttons.POS_DECREMENT) then
          self:adjustListPos(-1)
        elseif buttonIsPressed(self.Buttons.POS_INCREMENT) then
          self:adjustListPos(1)
        elseif buttonIsPressed(self.Buttons.CONFIRM) then
          local areaName = Names.AreasList[self.State.LIST_POS]
          if areaName then
            self.Battles_HUD:switchArea(areaName)
            self.Mode = Modes.ENCOUNTER_MODE
          end
        end
      end

      if self.Mode == Modes.ENCOUNTER_MODE then
        if buttonIsPressed(self.Buttons.POS_DECREMENT) then
          self.Battles_HUD:adjustPos(-1)
        elseif buttonIsPressed(self.Buttons.POS_INCREMENT) then
          self.Battles_HUD:adjustPos(1)
        elseif buttonIsPressed(self.Buttons.POS_DECREASE) then
          self.Battles_HUD:adjustPos(-10)
        elseif buttonIsPressed(self.Buttons.POS_INCREASE) then
          self.Battles_HUD:adjustPos(10)
        elseif buttonIsPressed(self.Buttons.CONFIRM) then
          self.Battles_HUD:jumpToBattle()
        end
      end

      self:drawMenu()
      self:drawHUD()
      self:reduceCooldowns()
    end

    if client.ispaused() and self.State.PAUSED_BY_CONTROLS then
      client.unpause()
      self.State.PAUSED_BY_CONTROLS = false
    end
  end
end

function Controls:drawAreaSelection()
  local x = Config.Battle_HUD.GUI_X
  local y = Config.Battle_HUD.GUI_Y
  local gap = Config.Battle_HUD.GUI_GAP
  local numToDisplay = Config.Battle_HUD.NUM_TO_DISPLAY

  if self.State.LIST_POS < 1 then
    self.State.LIST_POS = 1
  elseif self.State.LIST_POS > #Names.AreasList then
    self.State.LIST_POS = #Names.AreasList
  end

  local i,d = 0,0
  local s = ">> "
  repeat
    s = s .. Names.AreasList[self.State.LIST_POS + i]
    gui.text(x, y, s)
    y = y + gap
    i = i + 1
    d = d + 1
    s = ""
  until d >= numToDisplay or (self.State.LIST_POS + i) > #Names.AreasList
end

function Controls:drawMenu()
  gui.cleartext()
  self.RNG_HUD:drawHUD()
  if self.Mode == Modes.AREAS_MODE then
    self:drawAreaSelection()
  else
    self.Battles_HUD:drawHUD(true)
  end
  -- self:drawHUD()
end

return Controls
