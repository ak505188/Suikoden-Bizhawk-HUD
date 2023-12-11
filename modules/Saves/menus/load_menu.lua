local fs = require "lib.fs"
local Drawer = require "controllers.drawer"
local MenuProperties = require "menus.Properties"
local Buttons = require "lib.Buttons"
local BaseMenu = require "menus.Base"
local lib = require "modules.Saves.lib"
local Utils = require "lib.Utils"
local Config = require "Config"

local SAVETYPES = {
  SAVE = 0,
  AUTOSAVE = 1,
}

local LoadStateMenu = BaseMenu:new({
  properties = {
    type = MenuProperties.MENU_TYPES.module,
    name = 'LOAD_STATE_MENU',
    control = MenuProperties.CONTROL_TYPES.scrolling_cursor,
  },
})

function LoadStateMenu:init()
  self.save_type = SAVETYPES.SAVE
  self:readSaves()
end

function LoadStateMenu:toggleSaveType()
  if not Config.Saves.AUTOSAVE_ENABLED then return end
  self.save_type = self.save_type == 0 and 1 or 0
  self:readSaves()
end

function LoadStateMenu:draw()
  local controls_draw_tbl = {
    string.format("Sq: Show %ssaves", self.save_type == SAVETYPES.SAVE and "auto" or "normal "),
    "Select: Delete Selected Save",
    "X: Load Selected Save",
    "O: Back",
  }

  if self.slot ~= nil then
    local i = 0
    local save_draw_tbl = {}
    while i < 10 and self.slot - i >= 0 do
      table.insert(save_draw_tbl, self.saves[self.slot - i])
      i = i + 1
    end

    save_draw_tbl[1] = string.format("> %s", save_draw_tbl[1])
    Drawer:draw(Utils.combineTables({ string.format("Slot %d/%d", self.slot, #self.saves) }, save_draw_tbl), Drawer.anchors.TOP_LEFT)
  end

  Drawer:draw(controls_draw_tbl, Drawer.anchors.TOP_RIGHT)
end

function LoadStateMenu:run()
  if Buttons.Circle:pressed() then
    return true
  elseif Buttons.Square:pressed() then
    self:toggleSaveType()
  elseif self.slot == nil then
    return false
  elseif Buttons.Cross:pressed() then
    local save_path = lib.getSavePath(self.saves[self.slot])
    if self.save_type == SAVETYPES.AUTOSAVE then
      save_path = lib.getAutoSavePath(self.saves[self.slot])
    end
    savestate.load(save_path)
  elseif Buttons.Select:pressed() then
    local save_path = lib.getSavePath(self.saves[self.slot])
    if self.save_type == SAVETYPES.AUTOSAVE then
      save_path = lib.getAutoSavePath(self.saves[self.slot])
    end
    fs.rm(save_path)
    self:readSaves(true)
  elseif Buttons.Down:pressed() then
    self:adjustSlot(-1)
  elseif Buttons.Up:pressed() then
    self:adjustSlot(1)
  elseif Buttons.Left:pressed() then
    self:adjustSlot(10)
  elseif Buttons.Right:pressed() then
    self:adjustSlot(-10)
  end
  return false
end

function LoadStateMenu:readSaves(preserve_slot)
  preserve_slot = preserve_slot or false
  local path = self.save_type == SAVETYPES.SAVE and lib.getSavePath() or lib.getAutoSavePath()
  local saves = fs.readdir(path)
  self.saves = saves
  if preserve_slot then
    self:adjustSlot(0)
  else
    self.slot = #self.saves > 0 and #self.saves or nil
  end
end

function LoadStateMenu:adjustSlot(amount)
  local new_slot = self.slot + amount
  if new_slot > #self.saves then
    self.slot = #self.saves
  elseif new_slot <= 1 then
    self.slot = 1
  else
    self.slot = new_slot
  end
end

return LoadStateMenu
