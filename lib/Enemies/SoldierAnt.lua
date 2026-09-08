-- Soldier Ant (va7.bin - Mt. Seifu's scripted Queen Ant fight AND Mt. Seifu's own random-encounter
-- roster; monster record at 0x8006500c: lvl4 HP28 PWR48 SKL18 DEF10 SPD22 MGC0 LUK6). This is the
-- ant's OWN independent per-turn AI (soldier_ant_ai_select_target_and_move, 0x800106b0) - separate
-- from (and, per Battle_Damage_Formula.md's "Queen Ant's full moveset" section, the ONLY mechanism
-- that actually produces ant attacks in the Queen Ant fight, since Soldier Ant's SPD=22 always
-- beats Queen Ant's SPD=20 in turn order, making her "command ants" branch an empirically-dead
-- no-op). Seed-exact simulated here, following the same rand()-call-counting convention as
-- lib/Magic.lua's simulate<Spell> functions and the sibling lib/Enemies/*.lua modules.

local RNGLib = require "lib.RNG"
local DamageVariance = require "lib.DamageVariance"

local SoldierAnt = {}

local MOVE_THRESHOLD = 0x4d -- ~77% Attack / ~23% DoubleStrike

-- simulateMoveSelection(startSeed, numCandidates) -> move, target, seed, calls
--   move: "Attack" or "DoubleStrike"
--   target: 1-indexed slot within the eligible-candidate list that accepted
--   seed: the RNG state after this resolves
--   calls: total rand() calls consumed by this step alone
--
-- Byte-for-byte the same target-scan-with-retry template as Dragon/ZombieDragon/Neclord (front-row
-- scan, roll%100>50 accept per candidate, retry the whole scan fresh on total reject), then ONE
-- move-choice roll: `((roll*100)/32767)%100 < 0x4d` -> Attack (the generic
-- apply_uncovered_attack_damage/battle_execute_player_attack fallback - NOT ant-specific, no
-- elemental scaling); else -> DoubleStrike (soldier_ant_special_double_strike, 0x80010524).
function SoldierAnt.simulateMoveSelection(startSeed, numCandidates)
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
  local quotient = (moveRoll * 100) // 32767 % 100
  local move = quotient < MOVE_THRESHOLD and "Attack" or "DoubleStrike"

  return move, target, seed, calls
end

-- calculateAttackDamage(attackerATK, targetDEF, rand) -> damage
-- The ~77% branch: NOT a Soldier-Ant-specific formula - this function returns -1, and main.exe's
-- own battle_dispatch_current_actor_action falls back to the generic single-target physical
-- resolver (apply_uncovered_attack_damage, main.exe 0x800f5960 - confirmed live 2026-09-07 while
-- investigating Queen Ant's "command ants" mechanic, see Battle_Damage_Formula.md). Ordinary
-- calc_damage (ATK-DEF, one rand() call, no elemental scaling at all - hence lib.DamageVariance,
-- not lib.EnemyElementalAttack, which is genuinely elemental-specific).
function SoldierAnt.calculateAttackDamage(attackerATK, targetDEF, rand)
  local base = attackerATK - targetDEF
  local damage = DamageVariance.calcVariance(base, rand)
  if damage < 1 then damage = 1 end
  return damage
end

-- calculateDoubleStrikeDamage(attackerATK, targetDEF, rand) -> damage
-- The ~23% branch (soldier_ant_special_double_strike, 0x80010524): ONE calc_damage roll (NOT a
-- genuine double-roll - confirmed via raw disassembly, distinct in shape from the Queen-commanded
-- path's ant_commanded_attack_damage, which really does roll calc_damage twice), then the result
-- is DOUBLED (`damage << 1`) before applying.
function SoldierAnt.calculateDoubleStrikeDamage(attackerATK, targetDEF, rand)
  local base = attackerATK - targetDEF
  local damage = DamageVariance.calcVariance(base, rand)
  if damage < 1 then damage = 1 end
  return damage * 2
end

return SoldierAnt
