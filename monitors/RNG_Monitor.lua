local Config = require "Config"
local Address = require "lib.Address"
local EncounterLib = require "lib.Encounter"
local RNGLib = require "lib.RNG"
local Buttons = require "lib.Buttons"
local MenuController = require "Menu"
local StateMonitor = require "monitors.State_Monitor"


-- These are options for text and how this runs, edit as needed
-----------------------------------------------------------
-- These are text labels for data printed on screen
local START_RNG_LABEL = Config.RNG_HUD.START_RNG_LABEL
local RNG_INDEX_LABEL = Config.RNG_HUD.RNG_INDEX_LABEL
local RNG_VALUE_LABEL = Config.RNG_HUD.RNG_VALUE_LABEL
local GUI_X_POS = Config.RNG_HUD.GUI_X_POS
local GUI_Y_POS = Config.RNG_HUD.GUI_Y_POS
local GUI_GAP = Config.RNG_HUD.GUI_GAP

-- These affect how far ahead in the RNG the script looks. Don't touch if things are working well.
-- If you set these too small, the script might stop working if RNG advances too quickly.
local INITITAL_BUFFER_SIZE = Config.RNG_HUD.INITITAL_BUFFER_SIZE -- Initial look-ahead
local BUFFER_INCREMENT_SIZE = Config.RNG_HUD.BUFFER_INCREMENT_SIZE -- Later look-ahead size per frame
local BUFFER_MARGIN_SIZE = Config.RNG_HUD.BUFFER_MARGIN_SIZE -- When difference between current length & current RNG Index is greater than this, look ahead again.

local Events = {
  NOT_INITIALIZED=1,
  NO_CHANGE=2,
  RNG_INCREMENT=3,
  RNG_DECREMENT=4,
  START_RNG_CHANGED=5
}

local RNGMonitor = {
  RNGTables = {},
  StartingRNG = nil,
  RNG = nil,
  RNGIndex = nil,
  Event = Events.NOT_INITIALIZED,
  State = {
    RNG_RESET_INCOMING = false,
    RNG_RESET_HAPPENED = false,
    START_RNG_CHANGED = false,
  }
}

function RNGMonitor:generateRNGBuffer(RNGTable, bufferLength)
  -- This handles the base RNG
  bufferLength = bufferLength or INITITAL_BUFFER_SIZE
  RNGTable = RNGTable or self:getRNGTable()
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
        value = isBattleWM,
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
  handleEncounterRNG()

  local startingTableSize = #self:getRNGTable().byIndex

  for i = 1, bufferLength do
    rng = RNGLib.nextRNG(rng)
    index = index + 1
    RNGTable.table[rng] = index
    RNGTable.byIndex[startingTableSize + i] = rng

    handleEncounterRNG()
  end

  RNGTable.last = rng
end

function RNGMonitor:createNewRNGTable(rng)
  rng = rng or self.RNG
  if (not self.RNGTables[rng]) then
    self.RNGTables[rng] = {
      table = {
        [rng] = 0
      },
      byIndex = {
        [0] = rng
      },
      last = rng
    }
    self.RNGTables[rng].WM = {}
    self.RNGTables[rng].OW = {}
    self:generateRNGBuffer(self.RNGTables[rng], INITITAL_BUFFER_SIZE)
  end
end

function RNGMonitor:getRNGTable(startingRNG)
  startingRNG = startingRNG or self.StartingRNG
  return self.RNGTables[startingRNG]
end

function RNGMonitor:getRNGTableSize(startingRNG)
  local currentTable = self:getRNGTable(startingRNG)
  return currentTable.table[currentTable.last]
end

function RNGMonitor:getRNGIndex(startingRNG)
  startingRNG = startingRNG or self.StartingRNG
  local currentTable = self:getRNGTable(startingRNG)
  return currentTable.table[self.RNG]
end

function RNGMonitor:goToRNGIndex(index)
  if index == self.RNGIndex then return end

  if index < 0 then
    index = 0
  elseif index > #self:getRNGTable().byIndex then
    index = #self:getRNGTable().byIndex
  end

  self.RNGIndex = index
  self.RNG = self:getRNGTable().byIndex[index]
  memory.write_u32_le(Address.RNG, self.RNG)
  self.State.RNG_CHANGED = true

  -- Increase buffer size if needed
  if (self:getRNGTableSize() - self.RNGIndex < BUFFER_MARGIN_SIZE) then
    self:generateRNGBuffer(self:getRNGTable(), BUFFER_INCREMENT_SIZE)
  end
end

function RNGMonitor:adjustRNGIndex(amount)
  self:goToRNGIndex(self.RNGIndex + amount)
end

function RNGMonitor:handleRNGOverflow()
  local rng = self.RNG
  self.Event = Events.START_RNG_CHANGED

  local start,index
  for startingRNG, RNGTable in pairs(self.RNGTables) do
    if (RNGTable.table[rng]) then
      local t_index = RNGTable.table[rng]
      if (not index or t_index > index) then
        index = t_index
        start = startingRNG
      end
    end
  end

  if (start) then
    self.StartingRNG = start
    self.RNGIndex = self:getRNGTable().table[rng]
    return
  end

  -- Else, create a new table
  -- No matches, so create new StartingRNG and Buffer
  self.StartingRNG = rng
  self.RNGIndex = 0
  self:createNewRNGTable(rng)
end

function RNGMonitor:handleRNGReset()
  client.pause()

  local handled = false
  local eventID = memory.read_u8(Address.EVENT_ID)
  local resetData = RNGLib.GetResetData(eventID)

  -- Cleanup
  self.State.RNG_RESET_INCOMING = false
  -- TODO: Better handling for start RNG not changing. Currently assuming always changes
  self.Event = Events.START_RNG_CHANGED

  while not handled do
    emu.yield()
    gui.cleartext()
    Buttons:update()
    if Buttons.Cross:pressed() then
      self.StartingRNG = self.RNG
      self.RNGIndex = 0
      memory.write_u32_le(Address.RNG, self.RNG)
      self:createNewRNGTable()
      handled = true
    elseif Buttons.Square:pressed() then
      self.StartingRNG = self.RNG
      self.RNGIndex = 0
      self.RNG_RESET_INCOMING = true
      self:createNewRNGTable()
      handled = true
    elseif Buttons.Circle:pressed() then
      self.RNG = resetData.rng
    elseif Buttons.Up:pressed() then
      self.RNG = self.RNG + 1
    elseif Buttons.Down:pressed() then
      self.RNG = self.RNG - 1
    end
    if not handled then
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 0, "Unknown RNG, assuming RNG Reset")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 1, "Event:" .. resetData.name)
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 2, string.format("RNG: %x", self.RNG))
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 3, "X: Continue")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 4, "O: Reset")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 5, "Sq: Was Load State")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 6, "Up: Increase RNG Value")
      gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 7, "Down: Decrease RNG Value")
    end
  end

  client.unpause()
end
--
function RNGMonitor:draw()
  gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 0, string.format('%s%x', START_RNG_LABEL, self.StartingRNG))
  gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 1, string.format('%s%d/%d', RNG_INDEX_LABEL, self.RNGIndex, self:getRNGTableSize()))
  gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 2, string.format('%s%x', RNG_VALUE_LABEL, self.RNG))
  -- gui.text(GUI_X_POS, GUI_Y_POS + GUI_GAP * 3, string.format('C:%s I:%s H:%s', tostring(self.State.RNG_CHANGED), tostring(self.State.RNG_RESET_INCOMING), tostring(self.State.RNG_RESET_HAPPENED)))
end

function RNGMonitor:init()
  local rng = StateMonitor.RNG.current
  self.RNG = rng
  self.StartingRNG = rng
  self.RNGIndex = 0
  self:createNewRNGTable()
end

function RNGMonitor:run()
  self.RNG = StateMonitor.RNG.current

  if (StateMonitor.IG_CURRENT_GAMESTATE.current == 4 and StateMonitor.IG_CURRENT_GAMESTATE.previous ~= 4) then
    self.State.RNG_RESET_INCOMING = true
  end

  if self.State.RNG_RESET_INCOMING and StateMonitor.RNG.changed then
    self:handleRNGReset()
  -- Handle Natural Overflow or Loadstate
  elseif not self.State.RNG_RESET_HAPPENED and not self:getRNGTable().table[self.RNG] then
    self:handleRNGOverflow()
  else
    local prevRNGIndex = self.RNGIndex
    self.RNGIndex = self:getRNGIndex()

    -- Check if RNG Index changed for Event Tracking
    if self.RNGIndex == prevRNGIndex then
      self.Event = Events.NO_CHANGE
    elseif self.RNGIndex < prevRNGIndex then
      self.Event = Events.RNG_DECREMENT
    else
      self.Event = Events.RNG_INCREMENT
    end
  end

  -- Increase buffer size if needed
  if (self:getRNGTableSize() - self.RNGIndex < BUFFER_MARGIN_SIZE) then
    self:generateRNGBuffer(self:getRNGTable(), BUFFER_INCREMENT_SIZE)
  end
end

return RNGMonitor
