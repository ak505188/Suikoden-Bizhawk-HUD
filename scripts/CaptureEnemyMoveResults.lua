-- Captures (move used, target(s), damage dealt) for an enemy's turn across a list of
-- candidate RNG seeds, from a savestate positioned right at/before that enemy's turn begins.
-- Built for Zombie Dragon's turn 2 (ZombieDragonT2.State) as the first case, but the
-- combatant-array offsets here are general (see docs/game_mechanics/Battle_Damage_Formula.md's
-- combatant-array section) - only ENEMY_ACTOR_ID (this enemy's 1-indexed actor number, see
-- below) and the combatant slot count are specific to this battle's roster.
--
-- INDEXING NOTE (confirmed live 2026-09-06): both the battle-state's "current actor" field
-- (base+0x8) and each combatant's own TargetIdx field (combatant_rec+0x49) are 1-INDEXED
-- relative to the 0-indexed combatant_rec array (slot N in the array = actor/target number
-- N+1). This script stores raw 1-indexed actor/target numbers as read, and separately reports
-- the 0-indexed array slot each corresponds to, to avoid confusing the two.
--
-- USAGE: edit BASE_SAVE/SEEDS/ENEMY_ACTOR_ID/NUM_COMBATANTS/MULTI_TARGET_MOVE_NAME below, run
-- via scripts/spawn-headless-emuhawk.sh. Prints results directly (no separate offline-
-- calculate step needed - unlike the Soul Eater workflow, there's no per-seed live-capture-
-- then-offline-simulate split here: this script directly reads what the game itself decided
-- and applied for each seed, it doesn't predict via a pure-code formula. lib/EnemyElementalAttack.lua
-- has a validated damage formula for the multi-target case (see
-- docs/game_mechanics/Battle_Damage_Formula.md's "Enemy elemental attacks" section) but this
-- script doesn't call it yet - a natural next step if predictive, not just observational,
-- results are needed.
--
-- A move that hits more than one combatant (ActionType==0/Attack, #damage>1) is reported as
-- MULTI_TARGET_MOVE_NAME rather than plain "Attack" - see that constant's own comment below.
-- This is a per-enemy label you set, not something read from game data (the game itself
-- doesn't distinguish "Attack" from "Fire Breath" via any field this script can read - it's
-- the same code path invoked repeatedly, see battle_execute_enemy_attack's plate comment).

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path

local Address = require "lib.Address"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/ZombieDragonT2.State"

-- This enemy's 1-indexed actor number in THIS savestate's roster (6 party members + this
-- enemy as the 7th combatant = actor number 7). Re-derive this per savestate/battle by
-- watching base+0x8 the way this investigation did - it's roster-size-dependent, not a
-- universal constant.
local ENEMY_ACTOR_ID = 7
local NUM_COMBATANTS = 7 -- total real combatant_rec slots (party + enemies) in this battle

-- ActionType==0/Attack hitting more than one combatant means this enemy's multi-target
-- attack fired (see battle_execute_enemy_attack's plate comment / Battle_Damage_Formula.md's
-- "Enemy elemental attacks" section - it's the ordinary single-target attack path, re-invoked
-- once per living target, not a distinct ActionType/AbilitySlot value you can read directly).
-- Name it here per enemy/battle - there's no field to read this from.
local MULTI_TARGET_MOVE_NAME = "Fire Breath"

local SEEDS = {
  0x00000001,
  0x12345678,
  0xdeadbeef,
  0xcafebabe,
  0x5eed1234,
  0x99999999,
  0x33333333,
  0x0000ffff,
  0x11111111,
  0x22222222,
}

local COMBATANT_BASE = 0xb94
local MAX_FRAMES = 600 -- generous per seed; this turn resolved in ~130 frames in the sample trace

local ACTION_TYPE_NAMES = { [0] = "Attack", [1] = "Defend", [2] = "Rune", [3] = "Item", [4] = "Unite" }

local function readCombatant(base, slot)
  local addr = base + COMBATANT_BASE + slot * 0x54
  return {
    maxHp = mainmemory.read_u16_le(addr + 0x10),
    curHp = mainmemory.read_u16_le(addr + 0x12),
    actionTag = mainmemory.read_u8(addr + 0x46),
    actionType = mainmemory.read_u8(addr + 0x47),
    abilitySlot = mainmemory.read_u8(addr + 0x48),
    targetIdx = mainmemory.read_u8(addr + 0x49),
  }
end

-- Runs one seed: loads BASE_SAVE, injects the seed, fast-forwards until ENEMY_ACTOR_ID
-- becomes the active actor and its action fields resolve (actionTag goes nonzero), records
-- baseline HP at that instant, then keeps advancing until the active actor moves on,
-- recording final HP to compute damage per combatant slot.
local function runOne(seed)
  savestate.load(BASE_SAVE)
  mainmemory.write_u32_le(Address.RNG, seed)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  local frame = 0
  -- phase 1: wait for the enemy's turn to begin
  while frame < MAX_FRAMES do
    local actor = mainmemory.read_u32_le(base + 0x8)
    if actor == ENEMY_ACTOR_ID then break end
    emu.frameadvance()
    frame = frame + 1
  end
  if frame >= MAX_FRAMES then
    return nil, "timeout waiting for enemy's turn to begin"
  end

  -- phase 2: wait for its action fields to resolve (actionTag goes nonzero)
  local decided
  while frame < MAX_FRAMES do
    decided = readCombatant(base, ENEMY_ACTOR_ID - 1)
    if decided.actionTag ~= 0 then break end
    emu.frameadvance()
    frame = frame + 1
  end
  if frame >= MAX_FRAMES then
    return nil, "timeout waiting for action to resolve"
  end

  local baseline = {}
  for i = 0, NUM_COMBATANTS - 1 do
    baseline[i] = readCombatant(base, i).curHp
  end

  -- phase 3: wait for the enemy's turn to end (actor moves on), then read final HP
  while frame < MAX_FRAMES do
    local actor = mainmemory.read_u32_le(base + 0x8)
    if actor ~= ENEMY_ACTOR_ID then break end
    emu.frameadvance()
    frame = frame + 1
  end
  if frame >= MAX_FRAMES then
    return nil, "timeout waiting for turn to end"
  end

  local damage = {}
  for i = 0, NUM_COMBATANTS - 1 do
    local finalHp = readCombatant(base, i).curHp
    if finalHp ~= baseline[i] then
      damage[#damage + 1] = string.format("slot%d:%d->%d(-%d)", i, baseline[i], finalHp, baseline[i] - finalHp)
    end
  end

  return {
    actionType = decided.actionType,
    abilitySlot = decided.abilitySlot,
    targetIdxRaw = decided.targetIdx,
    targetSlot = decided.targetIdx - 1,
    damage = damage,
    frameCount = frame,
  }
end

local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/EnemyMoveResults.txt"

local function main()
  local lines = {}
  for _, seed in ipairs(SEEDS) do
    local result, err = runOne(seed)
    local line
    if result then
      local actionName = ACTION_TYPE_NAMES[result.actionType] or ("Unknown(" .. result.actionType .. ")")
      if result.actionType == 0 and #result.damage > 1 then
        actionName = MULTI_TARGET_MOVE_NAME .. " (multi-target Attack)"
      end
      line = string.format(
        "seed=0x%08x move=%s(type=%d) abilitySlot=%d firstTargetSlot=%d(raw=%d) damage=[%s] frames=%d",
        seed, actionName, result.actionType, result.abilitySlot, result.targetSlot, result.targetIdxRaw,
        table.concat(result.damage, ","), result.frameCount)
    else
      line = string.format("seed=0x%08x FAILED: %s", seed, err)
    end
    -- console.log output is invisible through stdout redirection when spawned headlessly
    -- (see feedback-emuhawk-cli-lua-scripts) - the output FILE is the real record; console.log
    -- here is just a harmless bonus for anyone watching the GUI Lua console directly.
    console.log(line)
    table.insert(lines, line)
  end

  local file, writeErr = io.open(OUTPUT_FILE, "w")
  if file then
    file:write(table.concat(lines, "\n") .. "\n")
    file:close()
  else
    console.log("Failed to write output file: " .. tostring(writeErr))
  end
end

main()
client.exit()
