-- Probes Dragon.State (positioned right before Dragon's move) to figure out his actor id /
-- combatant count, then captures his move twice: once at the savestate's default RNG (should
-- be Lightning per the user), once with RNG advanced exactly one LCG step (should be Fire
-- Breath, AOE, per the user). This is the live-validation step for the structural hypothesis
-- in Battle_Damage_Formula.md's "Dragon's special-move chain" section: that dragon_ai_select_
-- target_and_move's per-candidate accept roll failing entirely (no party member accepted)
-- is what triggers Fire Breath instead of Lightning.

package.path = "/home/alex/Projects/Suikoden-Bizhawk-HUD/?.lua;" .. package.path
local Address = require "lib.Address"
local RNG = require "lib.RNG"

local BASE_SAVE = "/home/alex/Projects/Suikoden-Bizhawk-HUD/Dragon.State"
local OUTPUT_FILE = "/home/alex/Local/BizHawk-2.10-linux-x64/Lua/Output/DragonMoveResults.txt"
local COMBATANT_BASE = 0xb94
local MAX_FRAMES = 600

local lines = {}
local function log(s)
  table.insert(lines, s)
  console.log(s)
end

local function readCombatant(base, slot)
  local addr = base + COMBATANT_BASE + slot * 0x54
  return {
    maxHp = mainmemory.read_u16_le(addr + 0x10),
    curHp = mainmemory.read_u16_le(addr + 0x12),
    formationPos = mainmemory.read_u8(addr + 0x44),
    aliveFlag = mainmemory.read_u8(addr + 0x45),
    aoeFlag46 = mainmemory.read_u8(addr + 0x46),
    actionType = mainmemory.read_u8(addr + 0x47),
    abilitySlot = mainmemory.read_u8(addr + 0x48),
    targetIdx = mainmemory.read_u8(addr + 0x49),
  }
end

-- Probe: figure out party count, current actor, and dump every combatant slot
local function probe()
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))
  local partyCount = mainmemory.read_u32_le(base + 0x1c)
  local currentActor = mainmemory.read_u32_le(base + 0x8)
  log(string.format("base=0x%08x partyCount=%d currentActor=%d", base, partyCount, currentActor))
  for i = 0, partyCount + 2 do
    local ok, c = pcall(readCombatant, base, i)
    if ok then
      log(string.format(
        "  slot=%d maxHp=%d curHp=%d formationPos=%d alive45=%d aoeFlag46=%d actionType=%d abilitySlot=%d targetIdx=%d",
        i, c.maxHp, c.curHp, c.formationPos, c.aliveFlag, c.aoeFlag46, c.actionType, c.abilitySlot, c.targetIdx))
    end
  end
  return base, partyCount, currentActor
end

-- Run one scenario: optionally advance RNG by exactly one LCG step before letting the
-- turn resolve, then capture the resulting move/target/damage/aoeFlag.
local function runOne(label, advanceRngOneStep, enemyActorId, numCombatants)
  savestate.load(BASE_SAVE)
  local base = Address.sanitize(mainmemory.read_u32_le(Address.BATTLE_STATE_PTR))

  if advanceRngOneStep then
    local cur = mainmemory.read_u32_le(Address.RNG)
    local nxt = RNG.nextRNG(cur)
    mainmemory.write_u32_le(Address.RNG, nxt)
    log(string.format("[%s] RNG %08x -> %08x (advanced one step)", label, cur, nxt))
  else
    log(string.format("[%s] RNG left at default %08x", label, mainmemory.read_u32_le(Address.RNG)))
  end

  local baseline = {}
  for i = 0, numCombatants - 1 do
    baseline[i] = readCombatant(base, i).curHp
  end

  local frame = 0
  local decided
  -- wait for the action to resolve (actionTag/type goes nonzero on Dragon's own slot)
  while frame < MAX_FRAMES do
    decided = readCombatant(base, enemyActorId - 1)
    if decided.actionType ~= 0 or decided.abilitySlot ~= 0 then break end
    emu.frameadvance()
    frame = frame + 1
  end
  local aoeFlagAtDecision = decided.aoeFlag46

  while frame < MAX_FRAMES do
    local actor = mainmemory.read_u32_le(base + 0x8)
    if actor ~= enemyActorId then break end
    emu.frameadvance()
    frame = frame + 1
  end

  local damage = {}
  for i = 0, numCombatants - 1 do
    local finalHp = readCombatant(base, i).curHp
    if finalHp ~= baseline[i] then
      damage[#damage + 1] = string.format("slot%d:%d->%d(-%d)", i, baseline[i], finalHp, baseline[i] - finalHp)
    end
  end

  log(string.format(
    "[%s] RESULT actionType=%d abilitySlot=%d targetIdxRaw=%d aoeFlag46@decision=%d damage=[%s] frames=%d hitCount=%d",
    label, decided.actionType, decided.abilitySlot, decided.targetIdx, aoeFlagAtDecision,
    table.concat(damage, ","), frame, #damage))
end

local ok, err = pcall(function()
  local base, partyCount, currentActor = probe()
  local enemyActorId = currentActor
  local numCombatants = partyCount + 1 -- assume 1 enemy; adjust if probe shows otherwise

  runOne("DEFAULT", false, enemyActorId, numCombatants)
  runOne("RNG+1", true, enemyActorId, numCombatants)
end)
if not ok then log("ERROR: " .. tostring(err)) end

local file = io.open(OUTPUT_FILE, "w")
if file then
  file:write(table.concat(lines, "\n") .. "\n")
  file:close()
end

client.exit()
