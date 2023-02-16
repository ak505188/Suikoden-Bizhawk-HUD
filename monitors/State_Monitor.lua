local Address = require "lib.Address"
local PartyLib = require "lib.Party"
local Utils = require "lib.Utils"

function table.clone(t)
  return { unpack(t) }
end

local initVarState = {
  current = nil,
  previous = nil,
  changed = nil
}

local StateMonitor = {
  IG_CURRENT_GAMESTATE = table.clone(initVarState),
  IG_PREVIOUS_GAMESTATE = table.clone(initVarState),
  WM_ZONE = table.clone(initVarState),
  AREA_ZONE = table.clone(initVarState),
  SCREEN_ZONE = table.clone(initVarState),
  ENCOUNTER_RATE = table.clone(initVarState),
  CHAMPION_RUNE_EQUIPPED = table.clone(initVarState),
  PARTY_LEVEL = table.clone(initVarState),
  RNG = table.clone(initVarState),
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
  self:updateState("WM_ZONE", buffer[1])
  self:updateState("SCREEN_ZONE", buffer[2])
  self:updateState("AREA_ZONE", buffer[3])
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


-- function BattlesHUD:updateState()
--   if self.Locked then return end

--   local location = EncounterLib.onWorldMapOrOverworld()

--   if location ~= Gamestates.WORLD_MAP and location ~= Gamestates.OVERWORLD then
--     return false
--   end

--   local wm_zone = memory.read_u8(Address.WM_ZONE)
--   local area_zone = memory.read_u8(Address.AREA_ZONE)
--   local inGameEncounterRate = memory.read_u8(Address.ENCOUNTER_RATE)

--   -- Get Champion Rune Info
--   local IsChampion = PartyLib.isChampionsRuneEquipped()
--   local PartyLevel = PartyLib.getPartyLVL()

--   local stateChanged = false

--   -- print("Location:", location, self.State.Location)
--   -- print("WM Zone:", wm_zone, self.State.WM_Zone)
--   -- print("Area Zone:", area_zone, self.State.Area_Zone)
--   -- print("Encounter Rate:", inGameEncounterRate, self.State.EncounterRate)

--   if location ~= self.State.Location then
--     -- print("Location changed")
--     stateChanged = true
--   elseif wm_zone ~= self.State.WM_Zone then
--     -- print("WM Zone changed")
--     stateChanged = true
--   elseif area_zone ~= self.State.Area_Zone then
--     -- print("Area Zone changed")
--     stateChanged = true
--   elseif inGameEncounterRate ~= self.State.EncounterRate then
--     -- print("EncounterRate changed")
--     stateChanged = true
--   elseif IsChampion then
--     if not self.State.IsChampion then
--       stateChanged = true
--     elseif PartyLevel ~= self.State.PartyLevel then
--       stateChanged = true
--     end
--   end

--   -- Check if change, if not do nothing.
--   if not stateChanged then
--     return false
--   end

--   local encounterRate
--   local name
--   local data

--   if location == Gamestates.WORLD_MAP then
--     name = ZoneInfo[wm_zone].name
--     data = EncounterTable[name]
--     if not data then return false end
--     encounterRate = 8
--   elseif location == Gamestates.OVERWORLD then
--     name = ZoneInfo[wm_zone][area_zone]
--     data = EncounterTable[name]
--     if not data then return false end
--     encounterRate = math.min(inGameEncounterRate, data.encounterRate)
--   end


--   self.State = {
--     Location = location,
--     Name = name,
--     EncounterTable = data.encounters,
--     Enemies = data.enemies,
--     EncounterRate = encounterRate,
--     EncounterTableSize = #data.encounters,
--     ChampVals = data.champVals,
--     WM_Zone = wm_zone,
--     Area_Zone = area_zone,
--     IsChampion = IsChampion,
--     PartyLevel = PartyLevel
--   }

--   return true
-- end

return StateMonitor
