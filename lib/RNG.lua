local eventNames = {
  "Pannu Yakuta Battle",
  "Fortress of Garan Battle",
  "Scarletia Battle #1",
  "Scarletia Battle #2",
  "Battle with Teo #1",
  "Battle with Teo #2",
  "Battle at Northern Checkpoint",
  "Battle at Floating Fortress Shazarazade",
  "The Last Battle",
  "Dragon Flight",
  "0x0A Unknown",
  "Marco",
  "Window",
  "Melodye",
  "Kasios",
  "Georges"
}

local eventRNGValues = {
	{ 0x43 },
	{ 0x43 },
	{ 0x43 },
	{ 0x43 },
	{ 0x42 },
	{ 0x42 },
	{ 0x43 },
	{ 0x43, 0x43, 0x43, 0x44, 0x45, 0x46, 0x46, 0x47, 0x47,
	  0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F,
	  0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58,
	  0x59, 0x5A, 0x5B, 0x5C, 0x5D, 0x5E, 0x5F },
	{ 0x42 },
	{},
	{},
	{ 0x12 },
	{ 0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xBD },
	{ 0x168, 0x169, 0x16A, 0x16B, 0x16C, 0x16D, 0x16E, 0x16F, 0x170 },
	{ 0x1E6, 0x1E7, 0x1E8, 0x1ED },
	{ 0x4E }
};

local dragonRideRNGValues = {
	{ 0x17, 0x18 },
	{ 0x19 },
	{ 0xAD, 0xAE }
}

local function getRandomResetValue(possibleValues)
	local length = #possibleValues;
	return possibleValues[math.random(1, length)];
end

local function getDragonRideData()
	local dragonRideID = mainmemory.read_u8(0x1b9af6);
  local eventName
	if (dragonRideID == 0) then
		eventName = "Dragon Ride to Magician's Island";
	elseif (dragonRideID ==  1) then
		eventName = "Dragon Ride from Magician's Island";
	elseif (dragonRideID ==  2) then
		eventName = "Dragon Ride to Flying Garden";
	else
		eventName = "Unknown Dragon Ride?"
	end

  local RNGResetValues = dragonRideRNGValues[dragonRideID + 1]
	return { RNGResetValues = RNGResetValues; name = eventName }
end

local function nextRNG(rng)
	local a = rng % 4294967296
	local b = 0x41c64e6d % 4294967296
	local ah, al = math.floor(a / 65536), a % 65536
	local bh, bl = math.floor(b / 65536), b % 65536
	local high = ((ah * bl) + (al * bh)) % 65536
	return ((high * 65536) + (al * bl)) % 4294967296 + 0x3039
end

local function getRNG2(rng)
  return (rng >> 16) & 0x7fff
end

local function isRun(rng2)
  return rng2 % 100 > 50
end

local function GetResetData(eventID)
  local ResetData = {}
	if (eventID == 9) then
    ResetData = getDragonRideData()
	else
		-- rngResetVal = getRandomResetValue(eventRNGValues[eventID + 1]);
		ResetData.RNGResetValues = eventRNGValues[eventID + 1]
    ResetData.name = eventNames[eventID + 1]
	end

  function ResetData:getRandomRNG() return self.RNGResetValues[math.random(1, #self.RNGResetValues)] end

  return ResetData
end

return {
  nextRNG = nextRNG,
  getRNG2 = getRNG2,
  isRun = isRun,
  GetResetData = GetResetData
}
