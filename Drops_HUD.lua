function DropsHUD:drawHUD(locked)
end

function DropsHUD:init(RNG_HUD)
  self.RNG_HUD = RNG_HUD
  self.Tables = { WM = RNG_HUD:getRNGTable().WM, OW = RNG_HUD:getRNGTable().OW }
  self.pos = 1
  self.cur = 1
  self:updateState()
end

function DropsHUD:run()
end

return DropsHUD
