-- Zombie Dragon (vb5g.bin, AI at 0x80012968 in the small overlay `enemy_ai_overlay.bin` -
-- NOT main.exe). Seed-exact simulated here, following the same rand()-call-counting
-- convention as lib/Magic.lua's simulate<Spell> functions and lib/Enemies/Dragon.lua. See
-- docs/game_mechanics/Battle_Damage_Formula.md's "Zombie Dragon" section and
-- zombie_dragon_ai_select_target_and_move's own derivation for the full write-up.
--
-- Move selection: live-validated 10/10 (both move and target) against
-- scripts/CaptureEnemyMoveResults.lua's ZombieDragonT2.State capture. Same target-scan-with-
-- retry shape as Dragon (lib/Enemies/Dragon.lua) - walk the eligible front-row candidates
-- (alive + front-row + not busy, already filtered down to `numCandidates`, in formation order)
-- rolling `rand() % 100 > 50` per candidate (first acceptor wins, ~49% per candidate); if NONE
-- accept, the whole scan retries fresh with new rolls (the real game retries on the NEXT tick
-- rather than immediately, but nothing else consumes RNG in between, so it's RNG-equivalent to
-- an immediate retry here). Once a target locks: if `roundCounter == 1`, Fire Breath is
-- guaranteed with NO further roll; otherwise one more rand(), `(roll*100)//32767 < 0x47` (~71%)
-- picks plain Attack, the remaining ~29% picks Fire Breath (target ignored - it's an AOE).

local RNGLib = require "lib.RNG"

local ZombieDragon = {}

local ATTACK_THRESHOLD = 0x47

-- simulateMoveSelection(startSeed, numCandidates, roundCounter) -> move, target, seed, calls
--   move: "Attack" or "FireBreath"
--   target: 1-indexed slot within the eligible-candidate list that accepted (nil for
--     FireBreath, and also nil on round 1 since target-selection still runs first regardless
--     of move but Fire Breath itself ignores it)
--   seed: the RNG state after this resolves
--   calls: total rand() calls consumed by this step alone
function ZombieDragon.simulateMoveSelection(startSeed, numCandidates, roundCounter)
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

  local move
  if roundCounter == 1 then
    move = "FireBreath"
  else
    local moveRoll = rand()
    local quotient = (moveRoll * 100) // 32767
    move = quotient < ATTACK_THRESHOLD and "Attack" or "FireBreath"
  end
  if move == "FireBreath" then target = nil end

  return move, target, seed, calls
end

return ZombieDragon
