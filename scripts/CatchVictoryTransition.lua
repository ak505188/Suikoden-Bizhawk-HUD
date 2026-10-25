-- Direct dynamic approach to finding the battle-victory/reward code, after static search
-- (BattleState+0x1260 anchor, +0x3c/+0x133c flag tracing, blind "0x3c(" text search - 134 hits, too
-- noisy) failed to find it. Instead of guessing further, force a fast win (drop Gigantes to 1 HP,
-- then Free Will attacks kill her in one hit) and watch the DAT_8017da90/94 per-slot continuation
-- function-pointer arrays every frame for any NEW address appearing right around her death - that
-- address is very likely the actual victory-handling function, found directly instead of guessed.
--
-- Also logs SyncSignals (BattleState+0x30, 32 bytes) and GAMESTATE every frame around the death, in
-- case the transition shows up there first.
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/CatchVictoryTransition.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"
local BattleRoundInput = require "lib.BattleRoundInput"
local Buttons = require "lib.Buttons"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Gigantes.State"
local TRACE_FRAMES = 6000
local NUM_SLOTS = 24 -- DAT_8017da90/94 slot count (init loop uses 0x14=20, pad a bit)

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/CatchVictoryTransition.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local function log(s)
  console.log(s)
  if outHandle then outHandle:write(s .. "\n"); outHandle:flush() end
end

local function readSlots(addr)
  local t = {}
  for i = 0, NUM_SLOTS - 1 do
    t[i] = mainmemory.read_u32_le(addr + i * 4)
  end
  return t
end

local ok, err = pcall(function()
  savestate.load(SAVESTATE)
  for i = 1, 5 do emu.frameadvance() end

  local baseRaw = mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)
  local base = Address.sanitize(baseRaw)
  local partyCount = mainmemory.read_u32_le(base + 0x1c)
  local totalCombatants = mainmemory.read_u32_le(base + 0x24)
  local rowArray = Address.sanitize(mainmemory.read_u32_le(base + 0x1344))

  local gigantesIdx = nil
  for idx = partyCount + 1, totalCombatants do
    local enemyDataAddr = base + 0x50 + idx * 0x8c
    local speciesId = mainmemory.read_u8(enemyDataAddr)
    local recordAddr = Address.sanitize(mainmemory.read_u32_le(rowArray + speciesId * 4))
    local name = Charmap.readStringFromMemory(recordAddr, 16)
    if name:match("^Gigantes") then gigantesIdx = idx end
  end
  if not gigantesIdx then error("Gigantes not found") end

  local combatantAddr = base + 0xb94 + (gigantesIdx - 1) * 0x54
  log(string.format("Gigantes combatant_rec at relative 0x%06x (slot %d)", combatantAddr, gigantesIdx))
  local maxHp = mainmemory.read_u16_le(combatantAddr + 0x10)
  log(string.format("Gigantes max HP = %d", maxHp))

  -- DAT_8017da90 / DAT_8017da94 absolute addresses (established this session: 0x8017da90/0x8017da94)
  local SLOTS90 = Address.sanitize(0x8017da90)
  local SLOTS94 = Address.sanitize(0x8017da94)

  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not newBase then error("round-start menu never became ready") end
  log(string.format("round-start menu confirmed (choice selected), base=0x%08x", newBase))

  -- Drop her to 1 HP (current HP only, +0x12) so the next resolved hit kills her - stays "in spec"
  -- (1 is a valid, reachable HP value, not an out-of-range injection). Done before the REAL confirm
  -- (confirmRound(), below) so Free Will's AI picks actions against her already-critical HP.
  mainmemory.write_u16_le(combatantAddr + 0x12, 1)
  log("Set current HP to 1")

  -- THE MISSING STEP found this pass: chooseRoundOption() only selects Free Will and confirms that
  -- CHOICE - it does NOT start the round. A separate confirmRound() (10-frame settle pad + a second
  -- Cross tap) is required to actually begin executing the round. Every earlier script this session
  -- (DiffEnemyDataUnkRegions.lua, CheckSwayPositionLink.lua) skipped this and only ever observed
  -- ambient idle-sway animation on the pre-round menu screen, never real combat resolution - the
  -- same class of methodological mistake as this project's own documented RNG-hook lesson (mistaking
  -- an idle/ambient signal for genuine round execution).
  BattleRoundInput:confirmRound()
  log("Round actually confirmed via confirmRound() - combat should now resolve")

  local prevGamestate = mainmemory.read_u8(Address.GAMESTATE)
  local deathFrame = nil

  -- Phase 1: cheap polling (HP + gamestate only) until she dies.
  local lastHp = nil
  for frame = 1, TRACE_FRAMES do
    emu.frameadvance()
    local hp = mainmemory.read_s16_le(combatantAddr + 0x12)
    local curGamestate = mainmemory.read_u8(Address.GAMESTATE)
    if curGamestate ~= prevGamestate then
      log(string.format("frame %d: GAMESTATE changed %d -> %d", frame, prevGamestate, curGamestate))
      prevGamestate = curGamestate
    end
    if hp ~= lastHp then
      log(string.format("frame %d: Gigantes HP = %d", frame, hp))
      lastHp = hp
    end
    if frame % 500 == 0 then
      log(string.format("frame %d: still waiting (hp=%d, gamestate=%d)", frame, hp, curGamestate))
    end
    if hp <= 0 then
      log(string.format("frame %d: Gigantes HP now %d (dead)", frame, hp))
      deathFrame = frame
      break
    end
  end

  if not deathFrame then
    log("Gigantes never died within TRACE_FRAMES - aborting")
    return
  end

  -- Phase 2: expensive full scan (state-machine slots + SyncSignals) for the next 600 frames,
  -- which is where the actual victory-handling transition should appear.
  local prev90 = readSlots(SLOTS90)
  local prev94 = readSlots(SLOTS94)
  local prevSync = {}
  for i = 0, 7 do prevSync[i] = mainmemory.read_u32_le(base + 0x30 + i * 4) end

  for frame = 1, 3600 do
    -- Periodically tap Cross, in case a post-victory dialog/fanfare/level-up prompt is waiting on
    -- simulated input the same way the original round-start menu did.
    if frame % 40 == 0 then
      Buttons.Cross:press()
    end
    emu.frameadvance()
    if frame % 40 == 0 then
      Buttons:clear()
    end

    local cur90 = readSlots(SLOTS90)
    local cur94 = readSlots(SLOTS94)
    for i = 0, NUM_SLOTS - 1 do
      if cur90[i] ~= prev90[i] then
        log(string.format("post-death frame %d: DAT_8017da90[%d] changed 0x%08x -> 0x%08x", frame, i, prev90[i], cur90[i]))
      end
      if cur94[i] ~= prev94[i] then
        log(string.format("post-death frame %d: DAT_8017da94[%d] changed 0x%08x -> 0x%08x", frame, i, prev94[i], cur94[i]))
      end
    end
    prev90, prev94 = cur90, cur94

    local curGamestate = mainmemory.read_u8(Address.GAMESTATE)
    if curGamestate ~= prevGamestate then
      log(string.format("post-death frame %d: GAMESTATE changed %d -> %d", frame, prevGamestate, curGamestate))
      prevGamestate = curGamestate
    end

    local curSync = {}
    local syncChanged = false
    for i = 0, 7 do
      curSync[i] = mainmemory.read_u32_le(base + 0x30 + i * 4)
      if curSync[i] ~= prevSync[i] then syncChanged = true end
    end
    if syncChanged then
      local parts = {}
      for i = 0, 7 do parts[#parts+1] = string.format("+0x%x:0x%x->0x%x", i*4, prevSync[i], curSync[i]) end
      log(string.format("post-death frame %d: SyncSignals changed: %s", frame, table.concat(parts, ", ")))
      prevSync = curSync
    end
  end
  log("done scanning post-death window")
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
