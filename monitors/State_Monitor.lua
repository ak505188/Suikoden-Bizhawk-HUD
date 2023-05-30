local Address = require "lib.Address"
local PartyLib = require "lib.Party"
local Utils = require "lib.Utils"

local initVarState = {
  current = nil,
  previous = nil,
  changed = nil
}

local StateMonitor = {
  IG_CURRENT_GAMESTATE = Utils.cloneTable(initVarState),
  IG_PREVIOUS_GAMESTATE = Utils.cloneTable(initVarState),
  WM_ZONE = Utils.cloneTable(initVarState),
  AREA_ZONE = Utils.cloneTable(initVarState),
  SCREEN_ZONE = Utils.cloneTable(initVarState),
  ENCOUNTER_RATE = Utils.cloneTable(initVarState),
  CHAMPION_RUNE_EQUIPPED = Utils.cloneTable(initVarState),
  PARTY_LEVEL = Utils.cloneTable(initVarState),
  RNG = Utils.cloneTable(initVarState),
}

function StateMonitor:updateState(key, value)
  local previousValue = self[key].current
  self[key].current = value
  self[key].previous = previousValue
  self[key].changed = value ~= previousValue
end

function StateMonitor:draw(opts)
  local drawOpts = {
    x = opts.x or 0,
    y = opts.y or 96,
    gap = opts.gap or 16
  }
  if opts then
    for k,v in pairs(opts) do
      drawOpts[k] = v
    end
  end
  local textToDraw = {
    string.format("G:%d P:%d", self.IG_CURRENT_GAMESTATE.current, self.IG_PREVIOUS_GAMESTATE.current),
    string.format("W:%d A:%d S:%d", self.WM_ZONE.current, self.AREA_ZONE.current, self.SCREEN_ZONE.current),
    string.format("ER:%d C:%s PL:%d", self.ENCOUNTER_RATE.current, self.CHAMPION_RUNE_EQUIPPED.current and "T" or "F", self.PARTY_LEVEL.current),
  }
  return Utils.drawTable(textToDraw, drawOpts)
end

function StateMonitor:read()
  local buffer = mainmemory.read_bytes_as_array(Address.GAMESTATE_BASE, 16)
  local partySize = buffer[4]
  self:updateState("AREA_ZONE", buffer[1])
  self:updateState("SCREEN_ZONE", buffer[2])
  self:updateState("WM_ZONE", buffer[3])
  self:updateState("RNG", mainmemory.read_u32_le(Address.RNG))

  self:updateState("IG_CURRENT_GAMESTATE", mainmemory.read_u8(Address.GAMESTATE))
  self:updateState("IG_PREVIOUS_GAMESTATE", mainmemory.read_u8(Address.PREV_GAMESTATE))
  self:updateState("ENCOUNTER_RATE", mainmemory.read_u8(Address.ENCOUNTER_RATE))
  self:updateState("CHAMPION_RUNE_EQUIPPED", PartyLib.isChampionsRuneEquipped())
  self:updateState("PARTY_LEVEL", PartyLib.getPartyLVL(partySize))
end

function StateMonitor:run()
  self:read()
end

function StateMonitor:init()
  self:read()
end

return StateMonitor
