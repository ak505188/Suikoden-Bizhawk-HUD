local should_log = false
local cursor_positions = {
  118,
  120,
  122,
  125,
  128,
  132,
  136,
  141,
  146,
  152,
  158,
  165,
  171,
  177,
  182,
  187,
  191,
  195,
  198,
  201,
  203,
  202,
  200,
  198,
  195,
  192,
  188,
  184,
  179,
  174,
  168,
  162,
  155,
  149,
  143,
  138,
  133,
  129,
  125,
  122,
  119,
  117,
}

local PLAYERS = {
  Tai_Ho = 'Tai Ho',
  Gaspar = 'Gaspar',
  Player = 'Player',
}

local function Cursor()
  local cursor = {
    index = 1,
  }

  function cursor:next()
    local index = self.index + 1
    if cursor_positions[index] == nil then index = 1 end
    self.index = index
  end

  function cursor:getValue()
    return self:getPos() < 160 and 144 - self:getPos() or self:getPos() - 176
  end

  function cursor:getPos()
    return cursor_positions[self.index]
  end

  local mt = {
    __tostring = function(self)
      return string.format("Cursor I:%d, P:%d, V:%d", self.index, self:getPos(), self:getValue())
    end
  }

  setmetatable(cursor, mt)

  return cursor
end

local function getStandardRoll(rng_short, counter, rng_modifier)
  rng_modifier = rng_modifier or 0
  local r2 = (rng_short + rng_modifier) % 100
  counter = (counter + r2) & 0xff
  if (counter < 6) then
    return counter, counter
  end
  return nil, counter
end


local function getStandardRollFull(rng, rng_modifier, roll_count)
  rng_modifier = rng_modifier or 0
  roll_count = roll_count or 3
  local roll,counter = nil,0
  local rolls = {}
  while true do
    roll,counter = getStandardRoll(rng:getShortRNG(), counter, rng_modifier)

    if (roll ~= nil) then
      table.insert(rolls, roll + 1)
      counter = 0
    end
    if (#rolls>= roll_count) then
      table.sort(rolls)
      return table.concat(rolls, '')
    end
    rng:next()
  end
end

local function getStandardRollDie(rng, rng_modifier, can_be_one)
  rng_modifier = rng_modifier or 0
  can_be_one = can_be_one == nil and false or can_be_one

  local counter = 0
  local roll = nil
  while roll == nil do
    roll,counter = getStandardRoll(rng:getShortRNG(), counter, rng_modifier)
    if (roll == 0 and not can_be_one) then
      roll = nil
    end
    if (roll == nil) then
      rng:next()
    end
  end
  return roll + 1, counter
end

local function isValidTaiHoRoll(roll_str)
  if (roll_str == '111' or
    roll_str == '222' or
    roll_str == '333' or
    roll_str == '444' or
    roll_str == '555' or
    roll_str == '666') then
    return false
  end
  if (roll_str == '123' or
    roll_str == '456' or
    roll_str == 'OUT') then
    return false end
  return true
end

local function calculateWait(rng_short)
  local wait = rng_short % 100
  return wait == 0 and 255 or wait - 1
end


local function isTripleWin(cursor, rng_short, rng_modifier)
  rng_modifier = rng_modifier or 0
  local r2 = 0
  local r3 = cursor:getValue()
  local r4 = math.abs(cursor:getValue() // 2^0x1f)
  r3 = r3 + r4
  r3 = r3 // 2
  r3 = (r3 + 0xfffb) & 0xffff
  if ((r3 & 0x8000) > 0) then
    r3 = r3 - 0x10000
  end
  r2 = r2 - r3

  local r5 = (rng_short + rng_modifier) % 100
  if should_log then
    print(string.format("3W r2:%d r5:%d", r2, r5))
  end

  if (r2 <= 0) then return false end

  return r2 >= r5
end

local function isTripleLose(cursor, rng_short, rng_modifier)
  rng_modifier = rng_modifier or 0
  local r2 = cursor:getValue()
  local r3 = math.abs(r2 // 2^0x1f)

  r2 = r2 + r3
  r2 = r2 // 2^1
  r2 = r2 + 5

  local r5 = (rng_short + rng_modifier) % 100
  if should_log then
    print(string.format("3L r2:%d r5:%d", r2, r5))
  end

  if (r2 <= 0) then return false end

  return r2 >= r5
end

local function isDoubleWin(cursor, rng_short, rng_modifier)
  rng_modifier = rng_modifier or 0
  local r3 = cursor:getValue() - 5
  local r2 = -r3
  local r5 = (rng_short + rng_modifier) % 100

  if should_log then
    print(string.format("2W r2:%d r5:%d", r2, r5))
  end

  if (r2 <= 0) then return false end

  return r2 >= r5
end

local function isDoubleLose(cursor, rng_short, rng_modifier)
  rng_modifier = rng_modifier or 0
  local r3 = cursor:getValue() + 5
  local r2 = r3
  local r5 = (rng_short + rng_modifier) % 100

  if should_log then
    print(string.format("2L r2:%d r5:%d", r2, r5))
  end

  if (r2 <= 0) then return false end

  return r2 >= r5
end

local function isPiss(cursor, rng_short, rng_modifier)
  rng_modifier = rng_modifier or 0
  local r3 = rng_short + rng_modifier
  local r4 = r3 % 100
  local r2 = cursor:getPos()
  r2 = r2 - 144

  if (r2 >= 0 and r2 < 0x21) then return false end

  r2 = cursor:getValue() + 5

  if (r2 < r4) then return false end

  return true
end

local function simulateRoll(cursor, rng, rng_modifier)
  rng_modifier = rng_modifier or 0
  rng:next()
  if should_log then
    print(string.format("Simulate Roll Start: %s I:%d", rng, rng:getCount()))
  end
  local is_triple_win = isTripleWin(cursor, rng:getShortRNG(), rng_modifier)
  if is_triple_win then
    if should_log then print(string.format("%s I:%d 3W", rng, rng:getCount())) end
    rng:next()
    local roll = getStandardRollDie(rng, rng_modifier, false)
    if should_log then print(string.format("%s I:%d 3W %d", rng, rng:getCount(), roll)) end
    return string.format("%d%d%d", roll, roll, roll)
  end
  rng:next()
  local is_triple_lose = isTripleLose(cursor, rng:getShortRNG(), rng_modifier)
  if (is_triple_lose) then
    if should_log then print(string.format("%s I:%d 3L", rng, rng:getCount())) end
    return '111'
  end
  rng:next()
  local is_double_win = isDoubleWin(cursor, rng:getShortRNG(), rng_modifier)
  if is_double_win then
    if should_log then print(string.format("%s I:%d 2W", rng, rng:getCount())) end
    return '456'
  end
  rng:next()
  local is_double_lose = isDoubleLose(cursor, rng:getShortRNG(), rng_modifier)
  if is_double_lose then
    if should_log then print(string.format("%s I:%d 2L", rng, rng:getCount())) end
    return '123'
  end
  rng:next()
  local is_piss = isPiss(cursor, rng:getShortRNG(), rng_modifier)
  if is_piss then
    rng:next()
    local rolls = getStandardRollFull(rng, rng_modifier)
    if should_log then print(string.format("%s I:%d Piss %s", rng, rng:getCount(), rolls)) end
    return 'OUT'
  end
  rng:next()
  if should_log then print(string.format("Normal Rolls start %s I:%d", rng, rng:getCount())) end
  local roll = getStandardRollFull(rng, rng_modifier)
  if should_log then print(string.format("Normal Rolls done %s I:%d %s", rng, rng:getCount(), roll)) end
  return roll
end

local function calculateOpponentRoll(rng, wait, player, rng_modifier)
  player = player or PLAYERS.Tai_Ho
  rng_modifier = rng_modifier or 0
  local cursor = Cursor()
  repeat
    cursor:next()
    rng:next()
  until (cursor:getPos() == 203)
  while wait > 0 do
    cursor:next()
    rng:next()
    wait = wait - 1
  end
  while true do
    local roll = simulateRoll(cursor, rng, rng_modifier)
    if player ~= PLAYERS.Tai_Ho then return roll end
    if isValidTaiHoRoll(roll) then return roll end
  end
end

local function simulateRollFromGameStart(rng, frames_before_wait_calculation, player, rng_modifier)
  frames_before_wait_calculation = frames_before_wait_calculation or 203
  player = player or PLAYERS.Tai_Ho
  rng_modifier = rng_modifier or 0

  local initial_rng_str = tostring(rng)
  rng:next(frames_before_wait_calculation)
  local wait = calculateWait(rng:getShortRNG())
  if should_log then print('Wait '.. wait) end
  local roll_rng_str = tostring(rng)
  local roll_rng_index = rng:getCount()
  local roll = calculateOpponentRoll(rng, wait, player, rng_modifier)
  return {
    initial_rng = initial_rng_str,
    roll_rng = roll_rng_str,
    roll_rng_index = roll_rng_index,
    roll = roll,
    wait = wait
  }
end

local function simulateRollsFromGameStart(rng, frames_before_wait_calculation, player, iterations, rng_modifier)
  frames_before_wait_calculation = frames_before_wait_calculation or 203
  player = player or PLAYERS.Tai_Ho
  iterations = iterations or 1
  rng_modifier = rng_modifier or 0
  local rolls_data = {}
  for i=1,iterations,1 do
    local roll_data = simulateRollFromGameStart(rng:clone(), frames_before_wait_calculation, player, rng_modifier)
    roll_data.initial_rng_index = i
    table.insert(rolls_data, roll_data)
    rng:next()
  end
  return rolls_data
end

return {
  calculateWait = calculateWait,
  calculateOpponentRoll = calculateOpponentRoll,
  getStandardRoll = getStandardRoll,
  getStandardRollDie = getStandardRollDie,
  getStandardRollFull = getStandardRollFull,
  isValidTaiHoRoll = isValidTaiHoRoll,
  isTripleWin = isTripleWin,
  isTripleLose = isTripleLose,
  isDoubleWin = isDoubleWin,
  isDoubleLose = isDoubleLose,
  isPiss = isPiss,
  simulateRoll = simulateRoll,
  simulateRollFromGameStart = simulateRollFromGameStart,
  simulateRollsFromGameStart = simulateRollsFromGameStart,
  Cursor = Cursor,
  PLAYERS = PLAYERS,
}
