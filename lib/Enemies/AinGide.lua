-- Ain Gide (vac.bin, AI at 0x80013b1c in the small overlay - NOT main.exe; lvl60 HP8000, lone
-- enemy of AinGide.State / SpellDuration.State). Seed-exact simulated here, same rand()-call-
-- counting convention as lib/Enemies/ZombieDragon.lua / Dragon.lua. See
-- docs/game_mechanics/Battle_Damage_Formula.md's "Ain Gide" section for the derivation and
-- the 2026-10-07 live validation (scripts/TraceAinGide.lua + scripts/CheckAinGideTrace.py: 80
-- of 80 rounds exact on move, target and rand() count).
--
-- Move selection: the shared front-row template (alive + formation pos < 4 + not busy get a
-- roll, `rand2 % 100 > 50` accepts, a fully rejected scan retries fresh on the next tick), then
-- ONE move roll: `(roll*100)//32767 < 0x33` -> basic Attack (the AI returns -1), else the
-- Special (continuation 0x80013d08). No round-counter gate. 16712/32768 = 51.001% Attack.

local RNGLib = require "lib.RNG"
local EnemyElementalAttack = require "lib.EnemyElementalAttack"

local AinGide = {}

local ATTACK_THRESHOLD = 0x33

-- The Special's fixed RNG cost after the move roll: 24 particles, each activated once by
-- vfx_activate_and_position_particle (2 rand() each, at S+32, S+36 ... S+124), then ONE
-- calc_rune_element_attack_damage roll per living party member, all on S+190. Nothing else rolls
-- until the next turn-order roll (Ain Gide's busy clears at S+204, the roll comes at S+235).
AinGide.SPECIAL_PARTICLE_ROLLS = 48

-- Frame offsets, live-measured 2026-10-07 (43 Specials, 37 Attacks). T0 = first frame Ain Gide is
-- the current actor. A fully rejected scan costs one extra tick per retry, shifting everything.
AinGide.TIMING = {
  ATTACK = {                  -- P = script start (his busy 0 -> 1), normally T0+1
    SCRIPT_START_FROM_T0 = 1, -- scan + move + the executor's hit roll all land on this frame
    TURN_ORDER_ROLL = 10,     -- gate set to 10 on P: next turn-order roll at P+10
    FX_1 = 66, FX_2_IMPACT = 70, DAMAGE_ROLL_AND_HP = 71, -- no damage frame at all on a miss
    FX_4_DONE = 107,
    NEXT_ACTOR = 109,         -- hit or miss
    BUSY_CLEAR = 154,
  },
  SPECIAL = {                 -- S = first call of the tick machine (0x800140c0)
    SCRIPT_START_FROM_T0 = 2, -- AI scan T0+1, his busy 0 -> 1 on T0+2 (after waiting for an idle party)
    HANDLER_INSTALLED_FROM_T0 = 12, -- +0x42 0->1; 2 on T0+13
    S_FROM_T0 = { 28, 32 },   -- cue wait of 15-19 ticks (async, 17 most common) after +0x42 = 2
    PARTICLE_ROLLS_FIRST = 32, PARTICLE_ROLL_STEP = 4, -- 24 ticks, 2 rand() each
    REACTION_WAVES = { 52, 90, 128 }, -- every living member busy 8 for 34 frames, each wave
    DAMAGE_ROLLS = 190, HP_COMMITTED = 191, PHASE_99 = 192, PHASE_100 = 193, CALLBACK_CLEARED = 194,
    BUSY_CLEAR = 204,         -- gate set to 30 on 205, next turn-order roll 235, next actor 236
    NEXT_ACTOR = 236,
  },
}

-- simulateMoveSelection(startSeed, numCandidates) -> move, target, seed, calls
--   startSeed: RNG state at the frame he becomes the current actor (T0)
--   numCandidates: living, front-row (+0x44 < 4), not-busy party members, in formation order
--   move: "Attack" or "Special"; target: 1-indexed candidate that accepted (the Special is AOE
--     and ignores it); seed: RNG state after the move roll; calls: rand() calls consumed here.
--   A basic Attack's executor then rolls ONE more hit roll on the same frame (not counted here),
--   and one calc_damage roll at P+71 if it hits.
function AinGide.simulateMoveSelection(startSeed, numCandidates)
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

  local quotient = (rand() * 100) // 32767
  local move = quotient < ATTACK_THRESHOLD and "Attack" or "Special"
  return move, target, seed, calls
end

-- simulateSpecial(startSeed, livingPartyCount) -> seed, calls
--   startSeed: the seed simulateMoveSelection returned for "Special"
function AinGide.simulateSpecial(startSeed, livingPartyCount)
  local seed = startSeed
  local calls = AinGide.SPECIAL_PARTICLE_ROLLS + livingPartyCount
  for _ = 1, calls do seed = RNGLib.nextRNG(seed) end
  return seed, calls
end

-- The Special's damage: calc_rune_element_attack_damage(attacker, slot, element = 1 = Fire), looped
-- over party slots 1..N with the loop counter in $s1 (vac.bin 0x800143b4), one roll per living
-- member. No AOE halving (unlike Dragon's Fire Breath). Live-validated 2026-10-07: 56 rounds x 6
-- members exact (scripts/TestAinGideRunes.lua, scripts/CheckAinGideRunes.py), with every member's
-- Rune.Id edited through persistent stats.
--   base = 410 - target MGC, variance, then halved if the target's rune category is 1 (Fire/Rage -
--   a real resist) or 7 (Soul Eater), or - the compiled $s1 bug - if the Rune.Id is not in the
--   explicit table (0, 8-0x1a, >0x1f) and the target is in party slot 1. Floor 1.
AinGide.SPECIAL_ELEMENT = 1
AinGide.MGC = 410

-- calculateSpecialDamage(targetMGC, targetRuneId, targetSlotIndex, rand) -> damage
function AinGide.calculateSpecialDamage(targetMGC, targetRuneId, targetSlotIndex, rand)
  local category = EnemyElementalAttack.RUNE_CATEGORY[targetRuneId]
  if category == nil and targetSlotIndex == AinGide.SPECIAL_ELEMENT then
    category = AinGide.SPECIAL_ELEMENT -- the bug: leftover loop-counter register substitutes for category
  end
  local halved = category == AinGide.SPECIAL_ELEMENT or category == 7
  return EnemyElementalAttack.calculateDamage(AinGide.MGC, targetMGC,
    halved and EnemyElementalAttack.Compat.RESIST or EnemyElementalAttack.Compat.NEUTRAL, rand)
end

return AinGide
