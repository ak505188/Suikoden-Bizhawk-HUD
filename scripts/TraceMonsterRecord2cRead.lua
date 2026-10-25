-- Live read-breakpoint on Gigantes' own MonsterRecord+0x2c resolved address (0x80048cb4, already
-- statically computed this session from vc3.bin's Bestiary.json actionScriptTableAddress+0x2c
-- delta - see docs/game_mechanics/Battle_Damage_Formula.md's "Monster record layout" section) to
-- find the actual consuming code, since static disassembly search turned out too noisy (offset
-- +0x2c collides with many unrelated structs, e.g. CombatantRec+0x2c is the MGC stat).
--
-- Uses event.onmemoryread (the modern BizHawk API - memory.registerread doesn't exist in this
-- build, confirmed via scripts/CheckMemoryHookAPI.lua). Registers BOTH the sanitized
-- MainRAM-relative address and the raw KSEG0 address, since it's not confirmed which domain
-- event.onmemoryread defaults to.
--
-- Drives the round-start Fight/Run/Bribe/Free Will prompt via lib/BattleRoundInput.lua (same fix
-- as scripts/TraceWhipMasterHellHoundCommand.lua needed) so Gigantes actually gets a turn and
-- plays a real attack, instead of sitting idle forever with nothing to read this address.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/TraceMonsterRecord2cRead.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local BattleRoundInput = require "lib.BattleRoundInput"
local Buttons = require "lib.Buttons"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Gigantes.State"
local TARGET_ADDR = 0x80048cb4 -- Gigantes' own MonsterRecord+0x2c value (vc3.bin)
local TRACE_FRAMES = 3600

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/TraceMonsterRecord2cRead.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  console.log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 5 do emu.frameadvance() end

  local relAddr = Address.sanitize(TARGET_ADDR)
  log(string.format("Target absolute=0x%08x relative=0x%06x", TARGET_ADDR, relAddr))

  local hitcount = 0
  local seenPCs = {}
  local function onRead(tag, ...)
    hitcount = hitcount + 1
    local pcOk, pc = pcall(function() return emu.getregister("pc") end)
    local pcStr = pcOk and string.format("0x%08x", pc) or tostring(pc)
    seenPCs[pcStr] = (seenPCs[pcStr] or 0) + 1
    if hitcount <= 30 then
      local extra = {...}
      local extraStr = {}
      for i, v in ipairs(extra) do extraStr[i] = tostring(v) end
      log(string.format("READ #%d (%s) pc=%s frame=%d args=[%s]", hitcount, tag, pcStr,
        emu.framecount(), table.concat(extraStr, ",")))
    end
  end

  -- event.onmemoryread is confirmed BROKEN for PSX cores in this BizHawk build (user-reported) -
  -- use the lower-level event.on_bus_read instead, which hooks the actual system bus rather than
  -- going through the (PSX-unsupported) higher-level memory-domain callback path.
  local ok1, err1 = pcall(function()
    event.on_bus_read(function(...) onRead("relative", ...) end, relAddr, "TraceMonsterRecord2cRead_rel")
  end)
  log(string.format("registered on_bus_read relative-addr hook ok=%s err=%s", tostring(ok1), tostring(err1)))

  local ok2, err2 = pcall(function()
    event.on_bus_read(function(...) onRead("absolute", ...) end, TARGET_ADDR, "TraceMonsterRecord2cRead_abs")
  end)
  log(string.format("registered on_bus_read absolute-addr hook ok=%s err=%s", tostring(ok2), tostring(err2)))

  log("--- confirming round-start prompt with Free Will (AI controls every combatant) ---")
  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not newBase then
    error("round-start menu never became ready")
  end
  log(string.format("round-start menu confirmed, base=0x%08x", newBase))

  for i = 1, 10 do emu.frameadvance() end
  Buttons.Cross:press()
  emu.frameadvance()
  Buttons.Cross:press()
  emu.frameadvance()
  Buttons:clear()

  log("--- round confirmed, tracing for reads ---")
  for frame = 1, TRACE_FRAMES do
    emu.frameadvance()
    if frame % 30 == 0 then
      local gamestateVal = mainmemory.read_u8(Address.GAMESTATE)
      if gamestateVal ~= 3 then
        log(string.format("frame %d: gamestate changed to %d - battle ended, stopping", frame, gamestateVal))
        break
      end
    end
  end

  log(string.format("Total reads observed: %d", hitcount))
  log("Distinct PCs:")
  for pc, count in pairs(seenPCs) do
    log(string.format("  %s x%d", pc, count))
  end
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
