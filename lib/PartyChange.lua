-- Party add/remove for Suikoden 1 without opening the Gregminster "Admit/Eject" menu.
-- See notes/Party_Change.md. Standalone runner: scripts/PartyChange.lua. Toolbox UI:
-- modules/Toolbox/Tools/PartyMembers.lua.
--
-- BizHawk's PSX core has no emu.setregister, so Lua can't call game functions directly. Instead
-- this installs a tiny MIPS stub in free RAM as the game's main-loop scene handler
-- (DAT_8017da90, called once per frame from main() at 0x800c2868). The stub checks a mailbox;
-- if a call is pending it runs fn(a0..a3) from inside the game's own frame, stores v0, then
-- tail-jumps to the original handler. The slot is data, not code, so no icache issue.
--
-- The primitives are in main.exe (resident in every room - no overlay required):
--   0x800c48d4(charId)  claim a slot, start CD read of the character's data -> slot (or -1)
--   0x800c2fa4()        CD read sync; returns 0 when the read is done
--   0x800c49b8(slot)    append slot to FORMATION_POSITIONS, PARTY_SIZE++, fix stats pointer
--   0x800c4afc(slot)    remove slot from formation, PARTY_SIZE--, PARTY_IDS[slot] = 0xff
--
-- Two ways to drive it:
--   * blocking  - PartyChange.addToParty(id) / removeFromParty(id) emu.frameadvance() while they
--                 wait, so only call them from a script's top level (not from a menu: menus run
--                 while the emulator is paused and no frame would ever advance).
--   * queued    - queueAdd / queueRemove, then call PartyChange.tick() once per frame. Never
--                 blocks; progress only happens while the emulator is actually running.
local Address = require "lib.Address"
local Functions = require "lib.AddressFunctions"

local PartyChange = {}

-- The main-loop scene handler pointer is Address.SCENE_HANDLER_MAIN_LOOP (DAT_8017da90 in v1.1).
-- Candidate homes for the stub (+0x100 mailbox). Each must be all zero, or already hold our stub.
local CANDIDATES = { 0x181000, 0x181400, 0x1fb000, 0x1a3800, 0x19e500 }
local BLOCK = 0x140
local M = { FLAG = 0, FN = 4, A0 = 8, A1 = 0xc, A2 = 0x10, A3 = 0x14, RESULT = 0x18, ORIG = 0x1c, BEAT = 0x20, DONE = 0x24 }
local STUB_HEX = "d8ffbd272000bfaf1880083c0011083520000a8d0000098d01004a250f00201120000aad000000ad1c00a8af0400198d0800048d0c00058d1000068d09f820031400078d1c00a88f00000000180002ad0000093c01002935240009ad1880083c001108351c00198d2000bf8f2800bd270800200325200000"

local MAX_PARTY = 6
local CALL_TIMEOUT_TICKS = 60
local CD_SYNC_TICKS = 600

local stubAddr, mail -- chosen at install()

local function k(addr) return 0x80000000 | addr end

-- Stub bytes with the mailbox address (lui/ori pairs at +0x08/+0x0c and +0x5c/+0x60) patched in.
local function stubBytes(mailAddr)
  local b = {}
  for i = 1, #STUB_HEX, 2 do b[#b + 1] = tonumber(STUB_HEX:sub(i, i + 1), 16) end
  local full = k(mailAddr)
  local hi, lo = (full >> 16) & 0xffff, full & 0xffff
  for _, off in ipairs({ 0x08, 0x5c }) do b[off + 1] = hi & 0xff; b[off + 2] = hi >> 8 end
  for _, off in ipairs({ 0x0c, 0x60 }) do b[off + 1] = lo & 0xff; b[off + 2] = lo >> 8 end
  return b
end

local function matches(base, want)
  local got = memory.read_bytes_as_array(base, #want)
  for i = 1, #want do if got[i] ~= want[i] then return false end end
  return true
end

local function allZero(base, len)
  for _, v in ipairs(memory.read_bytes_as_array(base, len)) do if v ~= 0 then return false end end
  return true
end

-- main.exe function addresses for PartyChange.call; resolved on each read (lib/AddressFunctions.lua has the per-build values).
local FN_KEYS = {
  claimSlot = "PARTY_CLAIM_SLOT",
  cdSync = "PARTY_CD_SYNC",
  appendToFormation = "PARTY_APPEND_TO_FORMATION",
  removeSlot = "PARTY_REMOVE_SLOT",
}
PartyChange.FN = setmetatable({}, { __index = function(_, name) return Functions[FN_KEYS[name]] end })

local function validHandler(p) return p >= 0x80010000 and p < 0x80200000 and (p & 3) == 0 end

-- Make the main-loop handler point at our stub. Returns true, or false + reason. Never points the
-- main loop at memory it hasn't verified. Safe to call every frame: it's a no-op once installed.
function PartyChange.install()
  local cur = memory.read_u32_le(Address.SCENE_HANDLER_MAIN_LOOP)
  if stubAddr and cur == k(stubAddr) then return true end
  if not validHandler(cur) then return false, string.format("scene handler %08x not valid (game not running yet?)", cur) end
  -- Our stub already sitting in RAM (earlier run, or a savestate taken while installed)? Reuse it.
  for _, base in ipairs(CANDIDATES) do
    if matches(base, stubBytes(base + 0x100)) then
      stubAddr, mail = base, base + 0x100
      if cur ~= k(base) then
        memory.write_u32_le(mail + M.ORIG, cur)
        memory.write_u32_le(Address.SCENE_HANDLER_MAIN_LOOP, k(base))
      end
      return true
    end
  end
  for _, base in ipairs(CANDIDATES) do
    if allZero(base, BLOCK) then
      stubAddr, mail = base, base + 0x100
      memory.write_bytes_as_array(stubAddr, stubBytes(mail))
      memory.write_u32_le(mail + M.ORIG, cur)
      memory.write_u32_le(Address.SCENE_HANDLER_MAIN_LOOP, k(stubAddr))
      return true
    end
  end
  return false, "no free RAM block for the stub"
end

function PartyChange.heartbeat() return stubAddr and memory.read_u32_le(mail + M.BEAT) or 0 end

-- Non-blocking primitives: post() a call, then poll() on later frames.
local function post(fn, a0, a1, a2, a3)
  local ok, why = PartyChange.install()
  if not ok then return false, why end
  memory.write_u32_le(mail + M.FN, fn)
  memory.write_u32_le(mail + M.A0, a0 or 0)
  memory.write_u32_le(mail + M.A1, a1 or 0)
  memory.write_u32_le(mail + M.A2, a2 or 0)
  memory.write_u32_le(mail + M.A3, a3 or 0)
  memory.write_u32_le(mail + M.DONE, 0)
  memory.write_u32_le(mail + M.FLAG, 1)
  return true
end

local function poll() -- returns done, signed v0
  if memory.read_u32_le(mail + M.DONE) ~= 1 then return false end
  local v = memory.read_u32_le(mail + M.RESULT)
  if v >= 0x80000000 then v = v - 0x100000000 end -- signed (-1 = failure)
  return true, v
end

local function cancelPosted() if mail then memory.write_u32_le(mail + M.FLAG, 0) end end

-- Run fn(a0..a3) inside the game's next frame (blocking); returns v0, or nil + reason on failure.
function PartyChange.call(fn, a0, a1, a2, a3, maxFrames)
  local ok, why = post(fn, a0, a1, a2, a3)
  if not ok then return nil, why end
  for _ = 1, maxFrames or 30 do
    emu.frameadvance()
    PartyChange.install() -- re-wrap if the game swapped the scene handler
    local done, v = poll()
    if done then return v end
  end
  cancelPosted()
  return nil, "call timed out (is the game running its main loop?)"
end

function PartyChange.slotOf(charId)
  for slot = 0, MAX_PARTY - 1 do
    if memory.read_u8(Address.PARTY_IDS + slot) == charId then return slot end
  end
end

function PartyChange.inParty(charId)
  local slot = PartyChange.slotOf(charId)
  if not slot then return false end
  for i = 0, memory.read_u8(Address.PARTY_SIZE) - 1 do
    if memory.read_u8(Address.FORMATION_POSITIONS + i) == slot then return true end
  end
  return false
end

function PartyChange.partySize() return memory.read_u8(Address.PARTY_SIZE) end

-- ----- blocking API -----

-- Returns true on success, or false + reason.
function PartyChange.removeFromParty(charId)
  local slot = PartyChange.slotOf(charId)
  if not slot or not PartyChange.inParty(charId) then return false, "not in party" end
  local r, why = PartyChange.call(PartyChange.FN.removeSlot, slot)
  if r == nil then return false, why end
  return r >= 0, r
end

function PartyChange.addToParty(charId)
  if PartyChange.inParty(charId) then return false, "already in party" end
  if PartyChange.partySize() >= MAX_PARTY then return false, "party full" end
  local slot, why = PartyChange.call(PartyChange.FN.claimSlot, charId)
  if slot == nil then return false, why end
  if slot < 0 then return false, "no free slot / bad id" end
  for _ = 1, CD_SYNC_TICKS do -- CD read of the character's data block
    local pending, why2 = PartyChange.call(PartyChange.FN.cdSync, 0)
    if pending == nil then memory.write_u8(Address.PARTY_IDS + slot, 0xff); return false, why2 end
    if pending == 0 then break end
  end
  local r, why3 = PartyChange.call(PartyChange.FN.appendToFormation, slot)
  if r == nil then memory.write_u8(Address.PARTY_IDS + slot, 0xff); return false, why3 end
  return true, slot
end

-- ----- queued API: queueAdd/queueRemove, then tick() once per frame -----
local queue, job = {}, nil
PartyChange.lastMessage = nil -- most recent result, for the UI
PartyChange.lastMessageFrame = 0
local tickCount = 0
local lastFrame = -1

local function say(msg)
  PartyChange.lastMessage = msg
  PartyChange.lastMessageFrame = tickCount
end

function PartyChange.pendingFor(charId)
  if job and job.id == charId then return job.kind end
  for _, j in ipairs(queue) do if j.id == charId then return j.kind end end
end

-- Ticks (emulated frames with the worker running) since the last result message.
function PartyChange.lastMessageAge() return tickCount - PartyChange.lastMessageFrame end

function PartyChange.queuedCount() return #queue + (job and 1 or 0) end

function PartyChange.clearQueue() queue = {} end

-- Drop a not-yet-started request. Returns true if one was removed.
function PartyChange.cancel(charId)
  for i, j in ipairs(queue) do
    if j.id == charId then table.remove(queue, i); return true end
  end
  return false
end

-- Party size once everything queued (and the job in flight) has been applied.
function PartyChange.projectedSize()
  local n = PartyChange.partySize()
  local function count(j) n = n + (j.kind == "add" and 1 or -1) end
  for _, j in ipairs(queue) do count(j) end
  if job and not job.done then count(job) end
  return n
end

local function enqueue(kind, charId)
  if PartyChange.pendingFor(charId) then return false end
  table.insert(queue, { kind = kind, id = charId })
  return true
end

function PartyChange.queueAdd(charId) return enqueue("add", charId) end
function PartyChange.queueRemove(charId) return enqueue("remove", charId) end

local function finish(msg)
  say(msg)
  job = nil
end

local function fail(msg)
  if job and job.slot and not job.done then memory.write_u8(Address.PARTY_IDS + job.slot, 0xff) end
  cancelPosted()
  finish("FAILED " .. job.kind .. " " .. job.id .. ": " .. msg)
end

local function startJob()
  job = table.remove(queue, 1)
  job.ticks = 0
  local id = job.id
  if job.kind == "remove" then
    local slot = PartyChange.slotOf(id)
    if not slot or not PartyChange.inParty(id) then return finish("remove " .. id .. ": not in party") end
    local ok, why = post(PartyChange.FN.removeSlot, slot)
    if not ok then return fail(why) end
    job.step = "removeWait"
  else
    if PartyChange.inParty(id) then return finish("add " .. id .. ": already in party") end
    if PartyChange.partySize() >= MAX_PARTY then return finish("add " .. id .. ": party full") end
    local ok, why = post(PartyChange.FN.claimSlot, id)
    if not ok then return fail(why) end
    job.step = "claimWait"
  end
end

-- Call once per frame (the Toolbox worker does). Does nothing when the queue is empty.
function PartyChange.tick()
  -- Menus call worker:run() in a tight loop while the emulator is paused; only act when a real
  -- emulated frame has passed, or queued jobs would time out before the game ever ran.
  local frame = emu.framecount()
  if frame == lastFrame then return end
  lastFrame = frame
  tickCount = tickCount + 1
  if not job then
    if #queue == 0 then return end
    startJob()
    if not job then return end
  end
  PartyChange.install() -- the game rewrites the handler on scene changes
  job.ticks = job.ticks + 1
  local done, v = poll()
  if not done then
    if job.ticks > (job.step == "syncWait" and CD_SYNC_TICKS or CALL_TIMEOUT_TICKS) then
      return fail("timed out (is the game running its main loop?)")
    end
    return
  end
  job.ticks = 0
  if job.step == "removeWait" then
    if v < 0 then return fail("game refused (" .. v .. ")") end
    job.done = true
    return finish("removed " .. job.id)
  elseif job.step == "claimWait" then
    if v < 0 then return fail("no free slot / bad id") end
    job.slot = v
    local ok, why = post(PartyChange.FN.cdSync, 0)
    if not ok then return fail(why) end
    job.step = "syncWait"
  elseif job.step == "syncWait" then
    local ok, why
    if v == 0 then
      ok, why = post(PartyChange.FN.appendToFormation, job.slot)
      job.step = "appendWait"
    else
      job.syncs = (job.syncs or 0) + 1
      if job.syncs > CD_SYNC_TICKS then return fail("CD read never finished") end
      ok, why = post(PartyChange.FN.cdSync, 0)
    end
    if not ok then return fail(why) end
  elseif job.step == "appendWait" then
    job.done = true
    return finish("added " .. job.id)
  end
end

return PartyChange
