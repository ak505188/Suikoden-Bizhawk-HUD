local GUI_X = 350
local GUI_GAP = 16
local GUI_Y = GUI_GAP * 2

local Controls = {
  State = {
    PAUSED_BY_CONTROLS = false,
  },
  Buttons = {
    MENU_BUTTON = "P1 R2",
    RNG_HUD_BUTTON = "P1 L2",
    TOGGLE_LOCK = "P1 Triangle",
    POS_INCREMENT = "P1 Down",
    POS_DECREMENT = "P1 Up",
    POS_INCREASE = "P1 Right",
    POS_DECREASE = "P1 Left",
  },
}

local function buttonIsPressed(button)
  return joypad.get()[button]
end

function Controls:init(RNG_HUD, Battles_HUD)
  self.RNG_HUD = RNG_HUD
  self.Battles_HUD = Battles_HUD
end

function Controls:drawHUD()
  gui.text(GUI_X, GUI_Y, "Controls Menu")
end

function Controls:run()
  if buttonIsPressed(self.Buttons.MENU_BUTTON) then
    if not client.ispaused() then
      client.pause()
      self.State.PAUSED_BY_CONTROLS = true
    end

    while buttonIsPressed(self.Buttons.MENU_BUTTON) do
      emu.yield()

      if buttonIsPressed(self.Buttons.RNG_HUD_BUTTON) then
        if buttonIsPressed(self.Buttons.POS_DECREMENT) then
          self.RNG_HUD:adjustRNGIndex(-1)
        elseif buttonIsPressed(self.Buttons.POS_INCREMENT) then
          self.RNG_HUD:adjustRNGIndex(1)
        elseif buttonIsPressed(self.Buttons.POS_DECREASE) then
          self.RNG_HUD:adjustRNGIndex(-25)
        elseif buttonIsPressed(self.Buttons.POS_INCREASE) then
          self.RNG_HUD:adjustRNGIndex(25)
        end

      elseif buttonIsPressed(self.Buttons.POS_DECREMENT) then
        self.Battles_HUD:adjustPos(-1)
      elseif buttonIsPressed(self.Buttons.POS_INCREMENT) then
        self.Battles_HUD:adjustPos(1)
      elseif buttonIsPressed(self.Buttons.POS_DECREASE) then
        self.Battles_HUD:adjustPos(-10)
      elseif buttonIsPressed(self.Buttons.POS_INCREASE) then
        self.Battles_HUD:adjustPos(10)
      elseif buttonIsPressed(self.Buttons.TOGGLE_LOCK) then
        self.Battles_HUD:toggleLock()
      elseif buttonIsPressed(self.Buttons.JUMP_TO_BATTLE) then
        -- Jump to Battle
      end
      gui.cleartext()
      self.RNG_HUD:drawHUD()
      self.Battles_HUD:drawHUD(true)
      self:drawHUD()
    end

    if client.ispaused() and self.State.PAUSED_BY_CONTROLS then
      client.unpause()
      self.State.PAUSED_BY_CONTROLS = false
    end
  end
end

return Controls
