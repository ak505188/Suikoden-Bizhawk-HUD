-- Verifies whether BizHawk's event.* callback system actually fires at all in this build/core,
-- before trusting any "zero hits" result from a targeted hook as meaningful (per direct user
-- suspicion that event functionality may be broken wholesale, not just onmemoryread).
--
-- Three independent checks, each against something that MUST fire if the underlying mechanism
-- works at all:
--   1. event.onframeend - should fire exactly once per emu.frameadvance() call, no memory-domain
--      complexity involved at all. If this doesn't fire N times after N frame advances, the
--      event system itself is broken, full stop.
--   2. event.onmemorywrite on Address.RNG (0x9010) - RNG is written on essentially every rand()
--      call; a live battle should produce many hits within a couple hundred frames.
--   3. memory.registerwrite on the same RNG address, as an independent comparison API (used
--      successfully in this project's own scripts/TraceRNGWrite.lua history) - if this fires but
--      event.onmemorywrite doesn't, that specifically isolates the "event.*" family as broken
--      while confirming memory.* still works.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/verify/VerifyEventAPI.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local Buttons = require "lib.Buttons"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Gigantes.State"
local FRAMES = 1200

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/VerifyEventAPI.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  console.log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

local ok, err = pcall(function()
  savestate.load(SAVESTATE)

  -- Check 1: onframeend
  local frameEndCount = 0
  local ok1, err1 = pcall(function()
    event.onframeend(function() frameEndCount = frameEndCount + 1 end, "VerifyEventAPI_frameend")
  end)
  log(string.format("event.onframeend registration ok=%s err=%s", tostring(ok1), tostring(err1)))

  -- Check 2: event.onmemorywrite on RNG
  local eventWriteCount = 0
  local ok2, err2 = pcall(function()
    event.onmemorywrite(function() eventWriteCount = eventWriteCount + 1 end, Address.RNG, "VerifyEventAPI_evwrite")
  end)
  log(string.format("event.onmemorywrite registration ok=%s err=%s", tostring(ok2), tostring(err2)))

  -- Check 3: memory.registerwrite on RNG (independent API family)
  local memWriteCount = 0
  local ok3, err3 = pcall(function()
    memory.registerwrite(Address.RNG, function() memWriteCount = memWriteCount + 1 end)
  end)
  log(string.format("memory.registerwrite registration ok=%s err=%s", tostring(ok3), tostring(err3)))

  -- CRITICAL FIX (per direct user catch): confirm the round-start Fight/Run/Bribe/Free Will
  -- prompt with Free Will BEFORE advancing frames, otherwise the battle sits idle at the menu
  -- with NO game logic (including RNG calls) executing at all - which would produce a false
  -- "zero hits" result indistinguishable from a genuinely broken hook.
  log("--- confirming round-start prompt with Free Will so RNG actually gets called ---")
  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not newBase then
    error("round-start menu never became ready - can't confirm RNG would even run")
  end
  log(string.format("round-start menu confirmed, base=0x%08x", newBase))
  for i = 1, 10 do emu.frameadvance() end
  Buttons.Cross:press()
  emu.frameadvance()
  Buttons.Cross:press()
  emu.frameadvance()
  Buttons:clear()

  log(string.format("Advancing %d more frames now (round should actively execute)...", FRAMES))
  local rngBefore = mainmemory.read_u32_le(Address.RNG)
  for i = 1, FRAMES do
    emu.frameadvance()
  end
  local rngAfter = mainmemory.read_u32_le(Address.RNG)
  log(string.format("RNG seed before=0x%08x after=0x%08x changed=%s", rngBefore, rngAfter,
    tostring(rngBefore ~= rngAfter)))

  log(string.format("RESULT event.onframeend fired: %d / %d expected", frameEndCount, FRAMES))
  log(string.format("RESULT event.onmemorywrite(RNG) fired: %d times", eventWriteCount))
  log(string.format("RESULT memory.registerwrite(RNG) fired: %d times", memWriteCount))

  if frameEndCount == 0 then
    log("CONCLUSION: event.* callback system does not fire at all in this build - confirmed broken wholesale.")
  elseif eventWriteCount == 0 and memWriteCount > 0 then
    log("CONCLUSION: event.* callbacks fire for frame-boundary events but NOT for memory writes specifically - memory.* family still works, event.onmemory* family is broken.")
  elseif eventWriteCount == 0 and memWriteCount == 0 then
    log("CONCLUSION: neither RNG write hook fired despite frames advancing - either RNG wasn't touched this window, or BOTH write-hook families are broken.")
  else
    log("CONCLUSION: event.onmemorywrite DOES fire - the event system works for writes; the earlier zero-hit read result may be a real finding (or reads specifically are broken while writes work).")
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
