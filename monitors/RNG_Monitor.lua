local Config = require "Config"
local StateMonitor = require "monitors.State_Monitor"
local Utils = require "lib.Utils"

local Drawer = require "controllers.drawer"

local Address = require "lib.Address"
local RNGTable = require "lib.RNGTable"
local Events = require "lib.Enums.RNG_Events"

-- These are options for text and how this runs, edit as needed
-----------------------------------------------------------
-- These are text labels for data printed on screen
local START_RNG_LABEL = Config.RNG_MONITOR.START_RNG_LABEL
local RNG_INDEX_LABEL = Config.RNG_MONITOR.RNG_INDEX_LABEL
local RNG_VALUE_LABEL = Config.RNG_MONITOR.RNG_VALUE_LABEL

local RNGMonitor = {
  RNGTables = {},
  StartingRNG = nil,
  RNG = nil,
  RNGIndex = nil, -- should this even be a variable? can just get from table. might be more expensive though
  Event = Events.NOT_INITIALIZED,
  State = {
    RNG_RESET_INCOMING = false,
    RNG_RESET_HAPPENED = false,
    START_RNG_CHANGED = false,
  }
}
function RNGMonitor:getTable(startingRNG)
  startingRNG = startingRNG or self.StartingRNG
  return self.RNGTables[startingRNG]
end

function RNGMonitor:setRNG(rng)
  rng = rng or self.RNG
  memory.write_u32_le(Address.RNG, rng)

  local table = self:getTable()
  local index = nil

  if table then
    index = table:getIndex(rng)
  end

  if index then
    self:goToIndex(index)
  else
    self:switchTable(rng)
  end
end

--- @param rng number? RNG Value
--- @return number? Start RNG of best matching table
function RNGMonitor:findTableContainingRNG(rng)
  rng = rng or StateMonitor.RNG.current

  -- Checks all existing tables to see if RNG exists
  -- If multiple tables contain RNG value, returns table where RNG table is at highest index
  local start_rng = nil
  local highest_index = 0
  for current_start_rng, rng_table in pairs(self.RNGTables) do
    local table_index = rng_table:getIndex(rng)
    if table_index then
      if (table_index > highest_index) then
        highest_index = table_index
        start_rng = current_start_rng
      end
    end
  end

  return start_rng
end

function RNGMonitor:switchTable(rng, create_new_table)
  rng = rng or StateMonitor.RNG.current
  create_new_table = create_new_table or false -- Used to force create a start rng table, even if one already exists

  local original_starting_rng = self.StartingRNG

  -- Force create new table, even if there is an existing appropriate table
  if create_new_table and not self.RNGTables[rng] then
    self.RNGTables[rng] = RNGTable(rng)
    self.StartingRNG = rng
    self.RNG = rng
    self.RNGIndex = self:getTable():getIndex(rng)
    self.Event = Events.START_RNG_CHANGED
    self.State.START_RNG_CHANGED = true
  end

  local found_starting_rng = self:findTableContainingRNG(rng)

  if found_starting_rng == nil then
    -- Make new table
    self.RNGTables[rng] = RNGTable(rng)
    self.StartingRNG = rng
    self.RNG = rng
    self.RNGIndex = self:getTable():getIndex(rng)
    self.Event = Events.START_RNG_CHANGED
    self.State.START_RNG_CHANGED = true
  elseif original_starting_rng ~= found_starting_rng then
    self.StartingRNG = found_starting_rng
    self.RNG = rng
    self.RNGIndex = self:getTable():getIndex(rng)
    self.Event = Events.START_RNG_CHANGED
    self.State.START_RNG_CHANGED = true
  end
end

function RNGMonitor:getTableSize(startingRNG)
  return self:getTable(startingRNG):getSize()
end

function RNGMonitor:getIndex(rng)
  rng = rng or self.RNG
  return self:getTable():getIndex(self.RNG)
end

function RNGMonitor:getRNG(index)
  index = index or self.RNGIndex
  return self:getTable():getRNG(index)
end

function RNGMonitor:goToIndex(index)
  if index == self.RNGIndex then return end

  if index < 0 then
    index = 0
  elseif index > #self:getTable().byIndex then
    index = #self:getTable().byIndex
  end

  self.RNGIndex = index
  self.RNG = self:getTable().byIndex[index]
  memory.write_u32_le(Address.RNG, self.RNG)
  self.State.RNG_CHANGED = true
  -- TODO: Should fire event here

  self:getTable():increaseBuffer(self.RNG)
end

function RNGMonitor:adjustIndex(amount)
  self:goToIndex(self.RNGIndex + amount)
  -- TODO: Should I fire an event here?
  -- Since in RNG Menu, probably not relevant.
  -- But probably won't hurt either
end

function RNGMonitor:draw()
  local textToDraw = {
    string.format('%s%x', START_RNG_LABEL, self.StartingRNG),
    string.format('%s%d/%d', RNG_INDEX_LABEL, self.RNGIndex, self:getTableSize()),
    string.format('%s%x', RNG_VALUE_LABEL, self.RNG)
  }
  return Drawer:draw(textToDraw, Drawer.anchors.TOP_LEFT)
end

function RNGMonitor:init()
  local rng = StateMonitor.RNG.current
  self.RNG = rng
  self.StartingRNG = rng
  self.RNGIndex = 0
  self.RNGTables[rng] = RNGTable(rng)
end

function RNGMonitor:run()
  self.RNG = StateMonitor.RNG.current

  if (StateMonitor.IG_CURRENT_GAMESTATE.current == 4 and StateMonitor.IG_CURRENT_GAMESTATE.previous ~= 4) then
    self.State.RNG_RESET_INCOMING = true
  end

  if self.State.RNG_RESET_INCOMING and StateMonitor.RNG.changed then
    self.State.RNG_RESET_INCOMING = false
    self.State.RNG_RESET_HAPPENED = false
    self.State.START_RNG_CHANGED = true
    self.Event = Events.START_RNG_CHANGED
    return self.Event
  elseif not self.State.RNG_RESET_HAPPENED and not self:getTable():getIndex(self.RNG) then
    self:switchTable(self.RNG)
  else
    local prevRNGIndex = self.RNGIndex
    self.RNGIndex = self:getIndex()

    -- Check if RNG Index changed for Event Tracking
    if self.RNGIndex == prevRNGIndex then
      self.Event = Events.NO_CHANGE
    elseif self.RNGIndex < prevRNGIndex then
      self.Event = Events.RNG_DECREMENT
    else
      self.Event = Events.RNG_INCREMENT
    end
  end

  self:getTable():increaseBuffer(self.RNG)
  return nil
end

return RNGMonitor
