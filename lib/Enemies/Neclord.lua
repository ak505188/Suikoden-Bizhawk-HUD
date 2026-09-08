-- Neclord (ve3.bin, the real Castle fight - HP 7500, AI at 0x8001675c; distinct from the
-- ve1.bin forced-loss fight). Seed-exact simulated here, following the same rand()-call-
-- counting convention as lib/Magic.lua's simulate<Spell> functions and lib/Enemies/Dragon.lua.
-- See docs/game_mechanics/Battle_Damage_Formula.md's "Neclord's real Castle fight" section and
-- neclord_special_move_windup / neclord_wind_tick_state_machine / neclord_bats_tick_state_
-- machine's own Ghidra plate comments (ve3.bin) for the full derivation.

local RNGLib = require "lib.RNG"
local EnemyElementalAttack = require "lib.EnemyElementalAttack" -- Wind/Lightning (genuinely elemental)
local DamageVariance = require "lib.DamageVariance" -- Bats (purely physical, no elemental scaling)

local Neclord = {}

-- Move-selection: fully solved and bit-exact validated (target-scan+move-choice math matches
-- Neclord.State's own live-captured total of 9 calls exactly for Lightning; NeclordBats.State's
-- own live-captured total of 86 calls exactly for Bats - see simulateBats below). Target-scan is
-- byte-for-byte identical to Zombie Dragon/Dragon's own formula (front-row scan, roll%100>50
-- accept, retry fresh on total reject) - neclord_ai_select_target_and_move (0x8001675c). Move
-- choice (neclord_special_move_windup, 0x800168dc) is TWO sequential (roll*100)/32767<0x33
-- (~51% each) rolls picking one of THREE outcomes - Wind is picked outright on the first roll's
-- reject branch; only the accept branch spends a second roll to split Bats vs Lightning:
--   roll1 >= 51% (~49.00%):                  Wind
--   roll1 < 51% and roll2 < 51% (~26.01%):    Bats
--   roll1 < 51% and roll2 >= 51% (~24.99%):   Lightning
local MOVE_THRESHOLD = 0x33

-- simulateMoveSelection(startSeed, numCandidates) -> move, target, seed, calls
--   move: "Wind", "Bats", or "Lightning"
--   target: 1-indexed slot within the eligible-candidate list that accepted (nil for Wind/
--     Lightning, which are AOE and ignore the scanned target)
--   seed: the RNG state after this resolves - the startSeed to hand to simulateWind/
--     simulateLightning/simulateBats
--   calls: total rand() calls consumed by this step alone
function Neclord.simulateMoveSelection(startSeed, numCandidates)
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  local target
  repeat
    for slot = 1, numCandidates do
      if rand() % 100 > 50 then
        target = slot
        break
      end
    end
  until target ~= nil

  local roll1 = rand()
  local q1 = (roll1 * 100) // 32767
  local move
  if q1 >= MOVE_THRESHOLD then
    move = "Wind"
  else
    local roll2 = rand()
    local q2 = (roll2 * 100) // 32767
    move = (q2 < MOVE_THRESHOLD) and "Bats" or "Lightning"
  end
  if move ~= "Bats" then target = nil end

  return move, target, seed, calls
end

-- Wind/Lightning: both AOE, both route through the exact same shared calc_rune_element_attack_
-- damage formula every elemental attack in this project uses (see EnemyElementalAttack.lua) -
-- Wind uses element=5 (Wind/Cyclone category), Lightning uses element=4 (Lightning/Thunder
-- category). Each hits every living party member once, no particle/VFX RNG of its own (the
-- position/velocity interpolation opcodes 17/19/20 the tick machines use are driven by rsin,
-- RngCallbackTable slot 0x80 - a fixed-point sine table, NOT RNG).
--
-- simulateAoe(startSeed, numTargets) -> totalRandCalls (one roll per living target)
local function simulateAoe(startSeed, numTargets)
  local seed = startSeed
  local calls = 0
  for _ = 1, numTargets do
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
  end
  return calls
end

function Neclord.simulateWind(startSeed, numTargets)
  return simulateAoe(startSeed, numTargets or 6)
end

function Neclord.simulateLightning(startSeed, numTargets)
  return simulateAoe(startSeed, numTargets or 6)
end

local WIND_ELEMENT = 5
local LIGHTNING_ELEMENT = 4

-- calculateWindDamage/calculateLightningDamage(attackerMGC, targetMGC, targetRuneCategory, rand)
--   -> damage. targetRuneCategory: from EnemyElementalAttack.RUNE_CATEGORY[targetRuneId], or nil
--   if not one of the explicit cases.
local function calculateElementDamage(attackerMGC, targetMGC, category, element, rand)
  local halved = category == element or category == 7
  return EnemyElementalAttack.calculateDamage(attackerMGC, targetMGC,
    halved and EnemyElementalAttack.Compat.RESIST or EnemyElementalAttack.Compat.NEUTRAL, rand)
end

function Neclord.calculateWindDamage(attackerMGC, targetMGC, targetRuneCategory, rand)
  return calculateElementDamage(attackerMGC, targetMGC, targetRuneCategory, WIND_ELEMENT, rand)
end

function Neclord.calculateLightningDamage(attackerMGC, targetMGC, targetRuneCategory, rand)
  return calculateElementDamage(attackerMGC, targetMGC, targetRuneCategory, LIGHTNING_ELEMENT, rand)
end

-- Bats: single-target physical attack, FULLY SOLVED AND BIT-EXACT VALIDATED 2026-09-07
-- (NeclordBats.State's own live-settled total of 86 calls matched exactly: 2 target-scan +
-- 2 move-choice + 60 spawn-position + 20 phase-offset + 1 damage-variance + 1 poison-roll).
--
-- Setup (neclord_bats_tick_state_machine's preceding setup function, 0x80017cd0) spawns 20 bat
-- particles; for EACH bat: 3 rand() calls for a "random point in a sphere" spawn-position
-- (RngCallbackTable slot 0x120, main.exe 0x80123054 - classic rejection-free 3D sampling: random
-- X in [-R,R], random Y in the resulting disc, random Z in the resulting circle), then 1 more
-- rand() call for a random 0-59 animation phase-offset (fast-forwards that bat's own idle
-- animation via repeated calls to a render function that itself makes no further rand() calls).
-- After a 63-tick converge phase, the actual hit: calc_damage's own 1 internal variance roll
-- (RngCallbackTable slot 0xC - the ordinary physical ATK-DEF formula, NOT calc_rune_element_
-- attack_damage), THEN a guaranteed status roll: a second script (0x8009e1b8) calls
-- anim_op_roll_status_effect_chance with status_id=0 (Poison) and chance_arg=100 - a real,
-- code-confirmed GUARANTEED application (the roll still consumes 1 rand() call even though
-- chance_arg=100 can never fail, which is exactly why this attack poisons 100% of the time
-- rather than merely very often).
--
-- simulateBats(startSeed, numBats) -> totalRandCalls
function Neclord.simulateBats(startSeed, numBats)
  numBats = numBats or 20
  local seed = startSeed
  local calls = 0
  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  for _ = 1, numBats do
    rand() -- spawn-position X
    rand() -- spawn-position Y
    rand() -- spawn-position Z
    rand() -- animation phase-offset (0-59)
  end

  rand() -- calc_damage's own variance roll
  rand() -- the guaranteed (chance_arg=100) Poison status roll

  return calls
end

-- calculateBatsDamage(attackerATK, targetDEF, rand) -> damage - the ordinary physical ATK-DEF
-- formula (calc_damage, RngCallbackTable slot 0xC), reusing lib.DamageVariance's shared variance
-- primitive with no elemental scaling (Bats is physical, not elemental).
function Neclord.calculateBatsDamage(attackerATK, targetDEF, rand)
  local base = attackerATK - targetDEF
  local damage = DamageVariance.calcVariance(base, rand)
  if damage < 1 then damage = 1 end
  return damage
end

return Neclord
