-- A third battle damage formula, distinct from both calc_damage (physical, ATK-DEF, RNG
-- variance, no elemental scaling) and apply_elemental_multiplier (magic, base_power+MGC/2,
-- fully deterministic, elemental scaling) - this one combines pieces of both: RNG variance
-- like calc_damage, but with the MGC stat substituted in for both sides, and elemental
-- scaling folded on top like apply_elemental_multiplier. Used by enemy "elemental attack"
-- moves - confirmed via exact live RNG matching against Zombie Dragon's fire breath (which
-- hits every living party member once, in sequence - see
-- battle_execute_enemy_attack's Ghidra plate comment and
-- docs/game_mechanics/Battle_Damage_Formula.md's "Enemy elemental attacks" section for the
-- full mechanism and derivation).
--
-- NOTE: the damage-application opcode itself (inside the attacking monster's own animation
-- script) has not been pinpointed in Ghidra - only this formula has been confirmed, via
-- exact RNG-value matching against a real cast, not the code that implements it.
--
-- 2026-09-07: the shared, non-elemental RNG-variance step (calc_damage's own formula) moved out
-- to lib/DamageVariance.lua - purely physical callers (no elemental scaling at all) should
-- require that module directly instead of this one. This module now only owns what's genuinely
-- elemental-specific: Compat, RUNE_CATEGORY, applyElementalScaling, and calculateDamage (which
-- layers those on top of DamageVariance.calcVariance).

local DamageVariance = require "lib.DamageVariance"

local Compat = {
  NEUTRAL = 0,
  WEAK = 1,
  RESIST = 2,
  IMMUNE = 3,
}

-- Rune.Id -> elemental resistance category, per calc_rune_element_attack_damage's own compiled
-- switch (main.exe 0x800f8174, dispatched via a real jump table at 0x800c1414, but the category
-- VALUES themselves are immediate constants baked into each jump target's code, not a second
-- data table - this Lua table is a reverse-engineered summary of those scattered immediates,
-- not a transcription of an in-memory array). Damage is halved if this category equals the
-- attack's own `element` argument, or if it's `7` (Soul Eater - an unconditional universal
-- resist, independent of `element`). A Rune.Id with no entry here (`0`, `8`-`0x1a`, or `>0x1f`)
-- falls through the real switch WITHOUT the category register ever being written - the compiled
-- "slot == element" bug documented on calc_rune_element_attack_damage and on
-- lib/Enemies/Dragon.lua's calculateFireBreathDamage - callers should pass `nil` for these and
-- decide separately whether that bug applies.
local RUNE_CATEGORY = {
  [1] = 7,             -- Soul Eater (universal)
  [2] = 1, [0x1b] = 1, -- Fire / Rage
  [3] = 2, [0x1c] = 2, -- Water / Flowing
  [6] = 3, [0x1e] = 3, -- Earth / Mother Earth
  [5] = 4, [0x1f] = 4, -- Lightning / Thunder
  [4] = 5, [0x1d] = 5, -- Wind / Cyclone
  [7] = 6,             -- Resurrection (alone)
}

-- applyElementalScaling(damage, compat) -> scaled damage
-- Same weak/resist/immune/neutral scaling apply_elemental_multiplier uses.
local function applyElementalScaling(damage, compat)
  if compat == Compat.WEAK then
    return damage * 2
  elseif compat == Compat.RESIST then
    return DamageVariance.cDiv(damage, 2)
  elseif compat == Compat.IMMUNE then
    return 0
  end
  return damage
end

-- calculateDamage(attackerMgc, targetMgc, targetCompat, rand) -> damage (floored at 1)
-- rand() must be a closure over an evolving RNG seed (matching lib/Magic.lua's convention),
-- called exactly once per invocation. targetCompat is one of the Compat.* constants above
-- (attack_data_table[target.Id]'s compatibility byte for this attack's element).
local function calculateDamage(attackerMgc, targetMgc, targetCompat, rand)
  local base = attackerMgc - targetMgc
  local damage = DamageVariance.calcVariance(base, rand)
  -- floor applies to the pre-scaling value, matching calc_damage's own structure - an
  -- IMMUNE target still ends up at a clean 0 after scaling, not floored back up to 1
  if damage < 1 then damage = 1 end
  damage = applyElementalScaling(damage, targetCompat)
  return damage
end

return {
  Compat = Compat,
  RUNE_CATEGORY = RUNE_CATEGORY,
  applyElementalScaling = applyElementalScaling,
  calculateDamage = calculateDamage,
}
