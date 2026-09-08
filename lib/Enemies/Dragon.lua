-- Not a player spell/enemy-AI-predictor entry - the boss "Dragon" (Id=1, HP 6000,
-- dragon_overlay.bin, AI at 0x80012594; distinct from Zombie Dragon) is seed-exact simulated
-- here, following the same rand()-call-counting convention as lib/Magic.lua's simulate<Spell>
-- functions. See docs/game_mechanics/Battle_Damage_Formula.md's "Dragon's move selection" and
-- "How much RNG does a Lightning attack advance?" sections, and
-- dragon_ai_select_target_and_move / dragon_special_move_real_frame_callback /
-- dragon_lightning_tick_state_machine's own Ghidra plate comments (dragon_overlay.bin), for the
-- full derivation of both functions below.

local RNGLib = require "lib.RNG"
local EnemyElementalAttack = require "lib.EnemyElementalAttack"

local Dragon = {}

-- Move-selection: fully solved and validated (100%, 92/92 live seeds across three independent
-- sweeps - scripts/SweepDragonMove.lua). Two phases, in two DIFFERENT real functions
-- (dragon_ai_select_target_and_move, then dragon_special_move_real_frame_callback, fired later
-- once the windup completes) but modeled here as one seed-exact step since nothing observable
-- happens between them:
--   1. Target-scan-with-retry: walk the eligible front-row candidates (alive + front-row + not
--      busy - already filtered down to `numCandidates`, in formation order) rolling
--      `rand() % 100 > 50` per candidate (first acceptor wins, ~49% per candidate); if NONE of
--      them accept, the whole scan retries fresh with new rolls (not "roll once more" - a real
--      bug this project found and fixed, see project memory). Ineligible members cost 0 rand()
--      calls and never enter `numCandidates` at all - the formation always keeps at least one
--      living front-row member, so this can never stall.
--   2. The move-choice roll: one more rand(), (roll*100)//32767 < 51 -> Lightning (using the
--      locked target); else Fire Breath (AOE, target ignored) - ~51%/49% split.
--
-- simulateMoveSelection(startSeed, numCandidates) -> move, target, seed, calls
--   move: "Lightning" or "FireBreath"
--   target: 1-indexed slot within the eligible-candidate list that accepted (nil for FireBreath)
--   seed: the RNG state after this resolves - i.e. the startSeed to hand to simulateLightning
--   calls: total rand() calls consumed by this step alone
function Dragon.simulateMoveSelection(startSeed, numCandidates)
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

  local moveRoll = rand()
  local quotient = (moveRoll * 100) // 32767
  local move = quotient < 51 and "Lightning" or "FireBreath"
  if move == "FireBreath" then target = nil end

  return move, target, seed, calls
end

-- Lightning attack VFX+damage: fully solved and validated, bit-exact (16/16 live-captured seeds,
-- exact final RNG state AND exact call count, across two independent sweeps).
--
-- 30 independent "spark" line-segment particles, each respawning at a random position/velocity/
-- lifetime (5 rand() calls per respawn, via vfx_spawn_random_arc_particle/main.exe 0x80124040)
-- whenever inactive, across a fixed 128-tick phase. A particle deactivates when either its
-- random lifetime (0-69 ticks) runs out, OR its position (integrated by a random negative
-- Z-velocity every active tick) crosses below a fixed -300 threshold - whichever comes first.
-- This is why the total is a genuine stochastic process, not a fixed count: observed range is
-- roughly 650-760 total rand() calls (including the single final damage-variance roll).
-- After the 128-tick spark phase, a second 124-tick phase runs with no further particle RNG,
-- ending in exactly one calc_rune_element_attack_damage variance roll.
--
-- IMPORTANT: startSeed here is the RNG state the instant BEFORE this VFX sequence's own first
-- rand() call - i.e. the `seed` returned by simulateMoveSelection once it's resolved to
-- Lightning - matching every other simulate<X> function's own convention of starting right at
-- the spell/effect's first rand().
local LightningConstants = {
  SPARK_COUNT = 30,
  SPARK_PHASE_TICKS = 128,
  DAMAGE_PHASE_TICKS = 124,
  LIFETIME_MOD = 0x46,
  VELOCITY_MOD = 5,
  VELOCITY_BASE = 5,
  POS_THRESHOLD = -300,
}

-- simulateLightning(startSeed) -> totalRandCalls
function Dragon.simulateLightning(startSeed)
  local C = LightningConstants
  local seed = startSeed
  local calls = 0

  local function rand()
    seed = RNGLib.nextRNG(seed)
    calls = calls + 1
    return RNGLib.getRNG2(seed)
  end

  local active = {}
  local lifetime = {}
  local posZ = {}
  local velZ = {}
  for i = 1, C.SPARK_COUNT do
    active[i] = false
    lifetime[i] = 0
    posZ[i] = 0
    velZ[i] = 0
  end

  for _ = 1, C.SPARK_PHASE_TICKS do
    for i = 1, C.SPARK_COUNT do
      if not active[i] then
        rand() -- X-offset
        rand() -- Y-offset
        rand() -- point-B Z-offset (unused for deactivation)
        local r4 = rand() -- Z-velocity
        local r5 = rand() -- lifetime
        velZ[i] = -((r4 % C.VELOCITY_MOD) + C.VELOCITY_BASE) * 4096
        lifetime[i] = r5 % C.LIFETIME_MOD
        posZ[i] = posZ[i] & 0xfff -- sub-unit residual preserved, integer part reset to 0
        active[i] = true
      end
    end
    for i = 1, C.SPARK_COUNT do
      if active[i] then
        -- check BEFORE updating, using the currently-stored position (same convention as
        -- Shining Wind's own pools) - note math.floor(/4096), NOT a native >> shift, since
        -- posZ can be negative and Lua's >> is a logical (not arithmetic) shift
        if lifetime[i] < 1 or math.floor(posZ[i] / 4096) < C.POS_THRESHOLD then
          active[i] = false
        else
          lifetime[i] = lifetime[i] - 1
          posZ[i] = posZ[i] + velZ[i]
        end
      end
    end
  end

  rand() -- the single calc_rune_element_attack_damage variance roll at the end of the
          -- 124-tick damage phase (that phase itself has no other RNG)

  return calls
end

-- Damage: fully solved and validated, bit-exact (8/8 Lightning + 5/6 Fire Breath live-captured
-- seeds, the 6th confirming a genuine compiled bug rather than breaking the formula - see
-- below). Both moves call the exact same shared `calc_rune_element_attack_damage`
-- (`main.exe @ 0x800f8174`, `RngCallbackTable` slot 86) Zombie Dragon's own Fire Breath uses
-- (see `lib/EnemyElementalAttack.lua`) - **MGC-based** (`attacker.MGC - target.MGC`), NOT
-- ATK-based, confirmed three ways: the decompile itself reads `wMGC` for both sides; a live
-- memory check of `Dragon.State` shows Dragon's own CombatantRec has genuinely distinct
-- ATK=250/MGC=150 (not aliased); and predicted damage from `attacker.MGC(150) - target.MGC`
-- matches every observed live value exactly, while the ATK-based hypothesis (`250 - target.DEF`,
-- 3-7x too high) does not come close.
--
-- Lightning passes `element=4` (`dragon_lightning_tick_state_machine`'s own inline call, no
-- extra scaling). Fire Breath passes `element=1` (`dragon_special2_damage_call_element1_LIVE`,
-- `0x80012eec`) and ADDITIONALLY halves the result unconditionally afterward (`iVar2/2` in the
-- decompile) - a separate, deliberate AOE-damage-reduction step on top of any elemental halving.
--
-- Fire Breath also carries the SAME compiled "resistance" bug already documented for Zombie
-- Dragon's own Fire Breath (see `calc_rune_element_attack_damage`'s plate comment, main.exe):
-- for any target whose Rune.Id isn't one of the ~12 explicitly-handled runes, the category
-- comparison reads whatever the caller's loop-counter register happened to leave behind instead
-- of a real "no category" value - and since this call's own loop counter starts at 1 (matching
-- `element=1`), **the very first target processed (party slot 1) gets an extra accidental 50%
-- reduction** if their rune isn't explicit, on top of the unconditional AOE halving above.
-- Confirmed live: a 6-target Fire Breath capture matched this formula exactly on 5/6 targets
-- unscaled, and the 6th (slot 1) matched exactly ONLY once this extra halving was included
-- (predicted 31 -> 15 with it, vs. an observed 15).
local LIGHTNING_ELEMENT = 4
local FIREBREATH_ELEMENT = 1

-- calculateElementDamage(attackerMGC, targetMGC, category, element, rand) -> damage
-- category: from EnemyElementalAttack.RUNE_CATEGORY[targetRuneId], or nil if the target's rune
-- isn't one of the explicit cases (halving then only applies if a bug substitutes a colliding
-- value - see callers below).
local function calculateElementDamage(attackerMGC, targetMGC, category, element, rand)
  local halved = category == element or category == 7
  return EnemyElementalAttack.calculateDamage(attackerMGC, targetMGC,
    halved and EnemyElementalAttack.Compat.RESIST or EnemyElementalAttack.Compat.NEUTRAL, rand)
end

-- calculateLightningDamage(attackerMGC, targetMGC, targetRuneCategory, rand) -> damage
function Dragon.calculateLightningDamage(attackerMGC, targetMGC, targetRuneCategory, rand)
  return calculateElementDamage(attackerMGC, targetMGC, targetRuneCategory, LIGHTNING_ELEMENT, rand)
end

-- calculateFireBreathDamage(attackerMGC, targetMGC, targetRuneCategory, targetSlotIndex, rand)
--   -> damage
-- targetSlotIndex: the target's 1-based position in Fire Breath's own hit-loop (== 1-based
-- party slot, since it hits everyone in formation order) - needed only to replicate the real
-- compiled bug described above for whichever target lands in slot 1.
function Dragon.calculateFireBreathDamage(attackerMGC, targetMGC, targetRuneCategory, targetSlotIndex, rand)
  local category = targetRuneCategory
  if category == nil and targetSlotIndex == 1 then
    category = FIREBREATH_ELEMENT -- the bug: leftover loop-counter register substitutes for category
  end
  local damage = calculateElementDamage(attackerMGC, targetMGC, category, FIREBREATH_ELEMENT, rand)
  return damage // 2 -- unconditional AOE halving, on top of any elemental halving above
end

return Dragon
