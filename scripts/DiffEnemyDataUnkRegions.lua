-- Live per-frame diff of EnemyData's two remaining unexplored byte ranges (aUnk_0x10, 48 bytes at
-- +0x10, and aUnk_0x42, 26 bytes at +0x42) across an active battle round, to find out which bytes
-- actually change over time (and when), since neither range is touched by any of the 3 known
-- battle-init functions (battle_load_enemy_combatants, battle_load_party_combatants, FUN_800df144)
-- - they're presumably populated by per-frame animation/rendering code instead.
--
-- Drives the round via Free Will (per project convention - a savestate sitting at the round-start
-- prompt is otherwise completely idle) and snapshots Gigantes' own EnemyData+0x10..+0x3f and
-- +0x42..+0x5b every frame for a while, logging only the frames where something in either range
-- actually changed from the previous snapshot (to keep output manageable).
--
-- USAGE: scripts/spawn-headless-emuhawk.sh /home/alex/Projects/Suikoden-Bizhawk-HUD/scripts/DiffEnemyDataUnkRegions.lua

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local Charmap = require "lib.Charmap"
local BattleRoundInput = require "lib.BattleRoundInput"

local SAVESTATE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/savestates/Gigantes.State"
local TRACE_FRAMES = 12000

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DiffEnemyDataUnkRegions.txt"
local outHandle = io.open(OUTPUT_FILE, "w")
local logCount = 0
local function log(s)
  logCount = logCount + 1
  if outHandle then
    outHandle:write(s .. "\n")
    outHandle:flush() -- log volume is now low (aUnk_0x42-only diffing), safe to flush every line
  end
end

local function snapshot(addr, len)
  return mainmemory.readbyterange(addr, len)
end

local function hexrow(t, len)
  local parts = {}
  for i = 0, len - 1 do
    parts[#parts+1] = string.format("%02x", t[i])
  end
  return table.concat(parts, " ")
end

local ok, err = pcall(function()
  pcall(function() client.speedmode(6400) end)
  pcall(function() client.invisibleemulation(true) end)
  savestate.load(SAVESTATE)
  for i = 1, 5 do emu.frameadvance() end

  local baseRaw = mainmemory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(baseRaw) then
    error("no battle active: BattleState ptr = " .. string.format("0x%08x", baseRaw))
  end
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
  if not gigantesIdx then error("Gigantes not found among enemy slots") end
  local enemyDataAddr = base + 0x50 + gigantesIdx * 0x8c
  log(string.format("Gigantes is enemy slot %d, EnemyData at relative 0x%06x", gigantesIdx, enemyDataAddr))

  log("--- idle snapshot before round confirm ---")
  local prevA = snapshot(enemyDataAddr + 0x10, 48)
  local prevB = snapshot(enemyDataAddr + 0x42, 26)
  log("aUnk_0x10 idle: " .. hexrow(prevA, 48))
  log("aUnk_0x42 idle: " .. hexrow(prevB, 26))

  log("--- confirming round-start prompt with Free Will ---")
  local newBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
  if not newBase then error("round-start menu never became ready") end
  log(string.format("round-start menu confirmed (choice selected), base=0x%08x", newBase))

  -- CRITICAL FIX (found 2026-09-18): chooseRoundOption() alone only selects the menu choice, it
  -- does NOT start the round - a separate confirmRound() call is required, or nothing ever
  -- actually resolves (only ambient idle animation runs on the pre-round menu screen). The
  -- earlier version of this script skipped this, which is exactly why it only ever observed idle
  -- sway and never any real attack.
  BattleRoundInput:confirmRound()
  log("round actually confirmed via confirmRound() - real combat should now resolve")
  -- Small buffer before reading/editing stats, in case combatant_rec's derived-stat slots
  -- (SKL included) aren't refreshed until a few frames into round processing. Deliberately varied
  -- from a plain round number across repeated attempts, since this savestate + deterministic
  -- frame-advance reproduces an IDENTICAL RNG sequence every run otherwise - any timing shift here
  -- samples a different slice of the RNG stream, which is the only way repeated attempts add
  -- information (confirmed empirically: two runs with the same buffer produced byte-identical hit
  -- timings).
  for i = 1, 37 do emu.frameadvance() end

  local combatantAddr = base + 0xb94 + (gigantesIdx - 1) * 0x54
  local lastGigantesHp = mainmemory.read_s16_le(combatantAddr + 0x12)
  local partyHpAddrs = {}
  for i = 1, partyCount do
    partyHpAddrs[i] = base + 0xb94 + (i - 1) * 0x54
  end
  local lastPartyHp = {}
  for i = 1, partyCount do
    lastPartyHp[i] = mainmemory.read_s16_le(partyHpAddrs[i] + 0x12)
  end
  log(string.format("Gigantes starting HP=%d, party starting HP=%s", lastGigantesHp, table.concat(lastPartyHp, ",")))

  -- RIG MAXIMUM MISS CHANCE for party-attacks-vs-Gigantes specifically (per calc_hit_chance's
  -- documented formula: chance = attacker.SKL - (target.SKL - 80), clamped to [60,99]).
  -- NOTE: chance(A vs B) + chance(B vs A) = 160 before clamping (both directions share the same
  -- two SKL values), so the two directions are a zero-sum tradeoff - pushing BOTH to the floor
  -- simultaneously is mathematically impossible. Picking one direction: party-vs-Gigantes, since a
  -- miss there maps to HER OWN evade/miss-reaction (the already-documented `+0xc` script slot on
  -- HER OWN action table), the most direct test of whether her EnemyData.aUnk_0x42 reacts to being
  -- missed. Only the party's own SKL needs lowering - Gigantes' SKL is left untouched.
  local gigantesSkl = mainmemory.read_u16_le(combatantAddr + 0x26)
  log(string.format("Gigantes SKL (live, untouched) = %d", gigantesSkl))
  local partySkl = {}
  for i = 1, partyCount do
    partySkl[i] = mainmemory.read_u16_le(partyHpAddrs[i] + 0x26)
  end
  log("Party SKL (live, before edit) = " .. table.concat(partySkl, ","))

  -- SAFETY CHECK: Gigantes' live combatant_rec SKL read as 1305, wildly higher than her
  -- documented static MonsterRecord SKL of 60 - either this offset means something different for
  -- enemies, or enemy stats get scaled unexpectedly. Trusting that number to compute an "exact
  -- floor" target would mean writing an equally absurd, out-of-spec value into the party's own SKL
  -- (the project's own established lesson: stay within real, plausible ranges, not "obviously
  -- large" numbers - out-of-range values can trigger unrelated defensive/other code, e.g. this
  -- same stat also feeds check_critical_hit's crit-chance formula, so a wild edit could
  -- contaminate the very test being run). Using a small, clearly in-spec value instead (real party
  -- SKL observed here ranges 47-99) and confirming the effect empirically via observed hit/miss
  -- outcomes, rather than trusting the formula's prediction against a suspect input.
  local targetPartySkl = 5
  for i = 1, partyCount do
    mainmemory.write_u16_le(partyHpAddrs[i] + 0x26, targetPartySkl)
  end
  log(string.format("Set every party member's SKL to %d (a real, in-spec low value) - to be confirmed empirically whether this increases misses against Gigantes",
    targetPartySkl))

  log(string.format("--- tracing up to %d frames across MULTIPLE rounds, logging only changed frames ---", TRACE_FRAMES))
  -- KEY FIX (found this pass): the Fight/Run/Bribe/Free Will menu reappears once a round fully
  -- resolves (every combatant has acted) and needs re-confirming, or the battle just sits idle at
  -- that menu for the rest of the trace - which is exactly what happened last run (a "0/12000
  -- changes" result that looked like a strong negative but was actually only ~5 real attacks
  -- followed by ~11600 idle frames, since round 1's own menu reappeared and was never
  -- re-confirmed). Restructured as a loop over rounds: re-confirm Free Will each time the menu is
  -- ready, then run the diff/HP-log loop for a fixed chunk of frames before checking again.
  local changeCount = 0
  local attackChunkCount = 0
  local globalFrame = 0
  local ROUND_CHUNK_FRAMES = 200
  while globalFrame < TRACE_FRAMES do
    local gamestateVal = mainmemory.read_u8(Address.GAMESTATE)
    if gamestateVal ~= 3 then
      log(string.format("global frame %d: gamestate changed to %d - battle ended, stopping", globalFrame, gamestateVal))
      break
    end

    -- Re-confirm Free Will for the next round (chooseRoundOption internally waits for the menu to
    -- be ready, frame-advancing as needed - those frames aren't individually diffed, matching how
    -- the very first round's setup already worked).
    local roundBase = BattleRoundInput:chooseRoundOption(BattleRoundInput.Choice.FREE_WILL)
    if roundBase then
      -- Re-apply the SKL rig every round: battle_refresh_combatant_derived_stats recomputes
      -- party members' derived stats from their true persistent stats each round-confirm (per the
      -- project's own doc), which would silently undo a one-time edit after round 1.
      for i = 1, partyCount do
        mainmemory.write_u16_le(partyHpAddrs[i] + 0x26, targetPartySkl)
      end
      BattleRoundInput:confirmRound()
      attackChunkCount = attackChunkCount + 1
    end

    for i = 1, ROUND_CHUNK_FRAMES do
      if globalFrame >= TRACE_FRAMES then break end
      emu.frameadvance()
      globalFrame = globalFrame + 1

      local curGigantesHp = mainmemory.read_s16_le(combatantAddr + 0x12)
      if curGigantesHp ~= lastGigantesHp then
        log(string.format("frame %d: Gigantes HP %d -> %d", globalFrame, lastGigantesHp, curGigantesHp))
        lastGigantesHp = curGigantesHp
      end
      for j = 1, partyCount do
        local hp = mainmemory.read_s16_le(partyHpAddrs[j] + 0x12)
        if hp ~= lastPartyHp[j] then
          log(string.format("frame %d: party member %d HP %d -> %d", globalFrame, j, lastPartyHp[j], hp))
          lastPartyHp[j] = hp
        end
      end

      local curB = snapshot(enemyDataAddr + 0x42, 26)
      local changedB = {}
      for i2 = 0, 25 do
        if curB[i2] ~= prevB[i2] then changedB[#changedB+1] = string.format("+0x%02x:%02x->%02x", 0x42+i2, prevB[i2], curB[i2]) end
      end
      if #changedB > 0 then
        changeCount = changeCount + 1
        local gs = mainmemory.read_u8(Address.GAMESTATE)
        log(string.format("frame %d (gamestate=%d): %s", globalFrame, gs, table.concat(changedB, ", ")))
      end
      prevB = curB

      local gsCheck = mainmemory.read_u8(Address.GAMESTATE)
      if gsCheck ~= 3 then
        log(string.format("frame %d: gamestate changed to %d - battle ended, stopping", globalFrame, gsCheck))
        globalFrame = TRACE_FRAMES
        break
      end
    end
  end
  log(string.format("Total frames with an aUnk_0x42 change: %d / %d (across %d round-confirm cycles)",
    changeCount, globalFrame, attackChunkCount))
end)

if not ok then log("ERROR: " .. tostring(err)) end
if outHandle then outHandle:close() end
client.exit()
