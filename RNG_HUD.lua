-- Performance notes: Seems to be about the same as event-driven one.
local RNGLib = require "RNGLib"
local Address = require "Address"
local EncounterLib = require "EncounterLib"
local Battles_HUD = require "Battles_HUD"

-- These are options for text and this runs, edit as needed
-----------------------------------------------------------
-- These are text labels for data printed on screen
local START_RNG_LABEL = "S: "
local RNG_INDEX_LABEL = "I: "
local RNG_VALUE_LABEL = "R: "
local GUI_X_POS = 0
local GUI_Y_POS = 32
local GUI_PX_BETWEEN_LINES = 16

-- These affect how far ahead in the RNG the script looks. Don't touch if things are working well.
-- If you set these too small, the script might stop working if RNG advances too quickly.
local INITITAL_BUFFER_SIZE = 5000 -- Initial look-ahead
local BUFFER_INCREMENT_SIZE = 500 -- Later look-ahead size per frame
local BUFFER_MARGIN_SIZE = 30000 -- When difference between current length & current RNG Index is greater than this, look ahead again.

--- Plugins On/Off
local ENCOUNTER_GENERATOR = true

-----------------------------------------------------------

console.clear()

-- Script Start --

local RNG_HUD = {
  RNGTables = {},

  State = {
    RNG_CHANGED = false,
    RNG_RESET_INCOMING = false,
    RNG_RESET_HAPPENED = false,
    START_RNG_CHANGED = false,
  }
}

function RNG_HUD:generateRNGBuffer(RNGTable, bufferLength)
  -- This handles the base RNG
  bufferLength = bufferLength or INITITAL_BUFFER_SIZE
  local rng = RNGTable.last
  local index = RNGTable.table[rng]

  local function handleEncounterRNG()
    local isBattleWM = EncounterLib.isPossibleBattle(rng, true)
    local isBattleOW = EncounterLib.isPossibleBattle(rng, false)
    local nextRNG, nextRNG2, isRun
    if isBattleWM then
      local battles = {}
      nextRNG = RNGLib.nextRNG(rng)
      nextRNG2 = RNGLib.getRNG2(nextRNG)
      isRun = RNGLib.isRun(RNGLib.getRNG2(RNGLib.nextRNG(nextRNG)))

      for size,_ in pairs(EncounterLib.TableSizes.WM) do
        battles[size] = EncounterLib.getEncounterIndex(nextRNG, size, nextRNG2)
      end
      table.insert(RNGTable.WM, {
        index = index,
        rng = rng,
        run = isRun,
        battles = battles,
      })
    end
    if isBattleOW then
      local battles = {}
      nextRNG = nextRNG or RNGLib.nextRNG(rng)
      nextRNG2 = nextRNG2 or RNGLib.getRNG2(nextRNG)
      isRun = isRun or RNGLib.isRun(RNGLib.getRNG2(RNGLib.nextRNG(nextRNG)))

      for size,_ in pairs(EncounterLib.TableSizes.OW) do
        battles[size] = EncounterLib.getEncounterIndex(nextRNG, size, nextRNG2)
      end
      table.insert(RNGTable.OW, {
        index = index,
        rng = rng,
        value = isBattleOW,
        run = isRun,
        battles = battles,
      })
    end
  end

  -- Initial call
  if ENCOUNTER_GENERATOR then handleEncounterRNG() end

  for _ = 1, bufferLength do
    rng = RNGLib.nextRNG(rng)
    index = index + 1
    RNGTable.table[rng] = index

    if ENCOUNTER_GENERATOR then handleEncounterRNG() end
  end

  RNGTable.last = rng
end

function RNG_HUD:createNewRNGTable(rng)
  rng = rng or self.RNG
  if (not self.RNGTables[rng]) then
    self.RNGTables[rng] = {
      table = {
        [rng] = 0
      },
      last = rng
    }
    if ENCOUNTER_GENERATOR then
      self.RNGTables[rng].WM = {}
      self.RNGTables[rng].OW = {}
    end
    self:generateRNGBuffer(self.RNGTables[rng], INITITAL_BUFFER_SIZE)
  end
end

function RNG_HUD:getRNGTable(startingRNG)
  startingRNG = startingRNG or self.StartingRNG
  return self.RNGTables[startingRNG]
end

function RNG_HUD:getRNGTableSize(startingRNG)
  local currentTable = self:getRNGTable(startingRNG)
  return currentTable.table[currentTable.last]
end

function RNG_HUD:getRNGIndex(startingRNG)
  local currentTable = self:getRNGTable(startingRNG)
  return currentTable.table[self.RNG]
end

function RNG_HUD:handleRNGOverflow()
  RNG = memory.read_u32_le(Address.RNG)
  self.State.START_RNG_CHANGED = true
  local start,index
  for startingRNG, RNGTable in pairs(self.RNGTables) do
    if (RNGTable.table[RNG]) then
      local t_index = RNGTable.table[RNG]
      if (not index or t_index > index) then
        index = t_index
        start = startingRNG
      end
    end
  end

  if (start) then
    self.StartingRNG = start
    self.RNGIndex = self:getRNGTable().table[RNG]
    return
  end

  -- Else, create a new table
  -- No matches, so create new StartingRNG and Buffer
  self.StartingRNG = RNG
  self.RNGIndex = 0
  self:createNewRNGTable(RNG)
  print("Created new table")
end

function RNG_HUD:handleRNGReset()
  client.pause()

  local handled = false
  local eventID = memory.read_u8(Address.EVENT_ID)
  local resetData = RNGLib.GetResetData(eventID)

  -- Cleanup
  self.State.RNG_RESET_INCOMING = false
  self.State.RNG_RESET_HAPPENED = false

  while not handled do
    emu.yield()
    gui.cleartext()
    local buttons = joypad.get()
    if (buttons["P1 Cross"]) then
      self.StartingRNG = self.RNG
      self.RNGIndex = 0
      memory.write_u32_le(Address.RNG, self.RNG)
      self:createNewRNGTable()
      handled = true
    elseif buttons["P1 Square"] then
      self.StartingRNG = self.RNG
      self.RNGIndex = 0
      self.RNG_RESET_INCOMING = true
      self:createNewRNGTable()
      handled = true
    elseif buttons["P1 Circle"] then
      self.RNG = resetData.rng
    elseif buttons["P1 Up"] then
      self.RNG = self.RNG + 1
    elseif buttons["P1 Down"] then
      self.RNG = self.RNG - 1
    end
    if not handled then
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 0, "Unknown RNG, assuming RNG Reset")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 1, "Event:" .. resetData.name)
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 2, string.format("RNG: %x", self.RNG))
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 3, "X: Continue")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 4, "O: Reset")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 5, "Sq: Was Load State")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 6, "Up: Increase RNG Value")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 7, "Down: Decrease RNG Value")
    end
  end

  client.unpause()
end

-- TODO: Better loadState during RNGReset handling
function RNG_HUD:onFrameStart()
  local newGameState = memory.read_u8(Address.GAMESTATE)
  if (newGameState == 4 and self.GameState ~= 4) then
    self.State.RNG_RESET_INCOMING = true
  end
  self.GameState = newGameState

  local newRNG = memory.read_u32_le(Address.RNG)
  if (newRNG ~= self.RNG) then
    self.State.RNG_CHANGED = true
  end
  self.RNG = newRNG

  if self.State.RNG_RESET_INCOMING and self.State.RNG_CHANGED then
    self.State.RNG_RESET_HAPPENED = true
  end

  -- Handle Natural Overflow or Loadstate
  if not self.State.RNG_RESET_HAPPENED and not self:getRNGTable().table[self.RNG] then
    self:handleRNGOverflow()
  end
end

function RNG_HUD:drawGUI()
  gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 0, string.format('%s%x', START_RNG_LABEL, self.StartingRNG))
  gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 1, string.format('%s%d/%d', RNG_INDEX_LABEL, self.RNGIndex, self:getRNGTableSize()))
  gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 2, string.format('%s%x', RNG_VALUE_LABEL, self.RNG))
  -- gui.text(GUI_X_POS, GUI_Y_POS + GUI_PX_BETWEEN_LINES * 3, string.format('C:%s I:%s H:%s', tostring(self.State.RNG_CHANGED), tostring(self.State.RNG_RESET_INCOMING), tostring(self.State.RNG_RESET_HAPPENED)))
end

function RNG_HUD:init()
  local rng = memory.read_u32_le(Address.RNG)
  self.GameState = memory.read_u8(Address.GAMESTATE)
  self.RNG = rng
  self.StartingRNG = rng
  self.RNGIndex = 0
  self:createNewRNGTable()
end

function RNG_HUD:run()
  self:onFrameStart()
  if self.State.RNG_RESET_HAPPENED then
    self:handleRNGReset()
  end
  emu.frameadvance()

  self.RNGIndex = self:getRNGIndex()

  -- Increase buffer size if needed
  if (self:getRNGTableSize() - self.RNGIndex < BUFFER_MARGIN_SIZE) then
    self:generateRNGBuffer(self:getRNGTable(), BUFFER_INCREMENT_SIZE)
  end

  self:drawGUI()

  --Cleanup before next loop
  self.State.RNG_CHANGED = false
end

RNG_HUD:init()
if ENCOUNTER_GENERATOR then
  Battles_HUD:init({ WM = RNG_HUD:getRNGTable().WM, OW = RNG_HUD:getRNGTable().OW })
end

while true do
  RNG_HUD:run()
  if ENCOUNTER_GENERATOR then
    if RNG_HUD.State.START_RNG_CHANGED then
      Battles_HUD:init({ WM = RNG_HUD:getRNGTable().WM, OW = RNG_HUD:getRNGTable().OW })
    end
    Battles_HUD:run(RNG_HUD.RNGIndex)
  end
  RNG_HUD.State.START_RNG_CHANGED = false
end

-- while true do
--   emu.frameadvance()
--   EncounterLib.doStuff({ WM = getCurrentRNGTable().WM, OW = getCurrentRNGTable().OW })
-- end
