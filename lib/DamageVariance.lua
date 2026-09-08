-- The shared RNG-variance primitive `calc_damage` (main.exe 0x800f7e90, physical ATK-DEF) uses
-- internally for its own single rand() call - extracted here because it's ALSO the first step of
-- calc_rune_element_attack_damage's elemental formula (see lib/EnemyElementalAttack.lua), which
-- layers elemental scaling on top of the exact same variance step. Genuinely physical callers
-- (no elemental scaling at all - Neclord's Bats, Queen Ant's commanded-ant damage, Soldier Ant's
-- Attack/DoubleStrike) should require THIS module directly, not lib.EnemyElementalAttack - that
-- module's name and its `Compat`/`RUNE_CATEGORY`/`applyElementalScaling` machinery are genuinely
-- elemental-specific and irrelevant to a plain physical hit.
--
-- 2026-09-07: extracted out of lib/EnemyElementalAttack.lua (which used to export calcVariance
-- directly) after the user asked "Why is Soldier Ant using EnemyElementalAttack?" - a fair
-- question, since Soldier Ant's attacks are purely physical. Pure move/rename, no formula change.

-- C truncates toward zero; Lua's `//` floors toward -infinity - replicate C's truncation exactly
-- (same fix used throughout lib/Magic.lua and lib/EnemyElementalAttack.lua for calc_damage-style
-- formulas).
local function cDiv(num, den)
  local q = math.abs(num) // math.abs(den)
  if (num < 0) ~= (den < 0) then q = -q end
  return q
end

-- calcVariance(base, rand) -> damage
-- Exact port of calc_damage's own RNG-variance step (same shape, one rand() call). This is the
-- ENTIRE formula for a plain physical attack (floor at 1 is the caller's own job, matching every
-- existing caller's convention) - elemental callers layer scaling on top of this same result.
local function calcVariance(base, rand)
  if base < 10 then
    return (base + 1) - (rand() % 4)
  end
  return base + cDiv((base // 2) - (rand() % base), 5)
end

return {
  cDiv = cDiv,
  calcVariance = calcVariance,
}
