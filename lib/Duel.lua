local RNGLib = require "lib.RNG"

-- Duel (1v1 "ikki" mode) simulator. Static RE 2026-10-01 from the three duel overlays in
-- data/12_ikki/ (shu_kwa.bin = McDohl vs Kwanda, shu_teo.bin = McDohl vs Teo, pan_teo.bin =
-- Pahn vs Teo), all loaded at 0x80080000. The code is byte-identical at the same addresses in
-- all three files; only the data (enemy stats, dialogue) differs. See
-- docs/game_mechanics/Duels.md for the derivation.
--
-- Exactly two rand() call sites exist in the overlay (both via the engine callback table slot
-- +0x90 = main.exe rand @ 0x80147e38):
--   1. duel_pick_enemy_move (0x80087898), once at the start of every round, BEFORE the
--      enemy's line is shown and before the player picks a command.
--   2. duel_apply_hit (0x80084634), once per hit landed (on either side), at the frame the
--      animation script flags the hit.
-- Defend vs Defend lands no hits, so that round costs exactly 1 rand() (the move roll).

local MOVE = { ATTACK = 0, DEFEND = 1, DESPERATE = 2 }
local MOVE_NAMES = { [0] = "Attack", [1] = "Defend", [2] = "Desperate Attack" }

-- Hit flag bits (side+0x18 / duel+0x6bc), set by the outcome animation scripts' opcode 14.
local HIT = { NORMAL = 1, HALF = 2, DOUBLE = 4, COUNTER = 8 }

-- Outcome index = playerMove*3 + enemyMove + 1 (table at 0x8008a498 is just 1..9).
-- Each entry lists the hits in the order they land (side 0 = player, side 1 = enemy). Taken
-- from the per-outcome scripts at 0x8008989c (player) / 0x800898c4 (enemy) - the scripts
-- hand off through signal/waitsig pairs, so in every two-hit outcome the order is fixed.
local OUTCOME_HITS = {
  [1] = { { side = 1, flag = HIT.NORMAL }, { side = 0, flag = HIT.NORMAL } }, -- Atk  vs Atk
  [2] = { { side = 1, flag = HIT.HALF } },                                    -- Atk  vs Def
  [3] = { { side = 1, flag = HIT.NORMAL }, { side = 0, flag = HIT.DOUBLE } }, -- Atk  vs Desp
  [4] = { { side = 0, flag = HIT.HALF } },                                    -- Def  vs Atk
  [5] = {},                                                                   -- Def  vs Def
  [6] = { { side = 1, flag = HIT.COUNTER } },                                 -- Def  vs Desp
  [7] = { { side = 0, flag = HIT.NORMAL }, { side = 1, flag = HIT.DOUBLE } }, -- Desp vs Atk
  [8] = { { side = 0, flag = HIT.COUNTER } },                                 -- Desp vs Def
  [9] = { { side = 1, flag = HIT.DOUBLE }, { side = 0, flag = HIT.DOUBLE } }, -- Desp vs Desp
}

-- Per-duel data. Enemy HP/STR/DEF are the overlay's hardcoded record (8-short stat array,
-- [6]=STR, [7]=DEF). The player's side is filled at duel start from the character's real
-- stats via battle_compute_ally_derived_stats (main.exe 0x800d4ec0) - i.e. STR/DEF here are
-- the same final ATK/DEF a normal battle uses (lib/BattleSnapshot.lua's computeAllyATKDEF),
-- and HP/HPMax are the character's current values carried in.
--
-- dialogue[row+1][move+1]: row = the PREVIOUS round's outcome index (0 on round 1), move =
-- the enemy's move this round. No extra rand() - the line is fully determined by the move
-- roll plus what happened last round.
local DUELS = {
  KWANDA = {
    file = "shu_kwa.bin",
    structPtr = 0x800a1d6c, -- overlay global holding the duel struct pointer (moves per file)
    player = "McDohl",
    enemy = { name = "Kwanda", hp = 280, hpMax = 280, str = 150, def = 75 },
    dialogue = {
      { "Taste the sharpness of my blade!", "Can you break my invulnerable defenses?", "Victory is near! I strike with all my might!" },
      { "Well done. But can you take this?", "Pretty good. How about another one?", "The next one won't be so easy." },
      { "Heh, now it's my turn.", "Damn! My turn!", "I'll get you!" },
      { "Ha ha! You'll have to do better than that!", "Now it's your turn. Come on!", "Here we go again!" },
      { "At a loss, are you? But I'll show no mercy!", "Don't bore me. Show me what you can do.", "Take that!" },
      { "What's the matter? If you don't attack, I will!", "Cautious, aren't you. Just like a leader.", "We're getting nowhere. Here I come!" },
      { "Damn! I underestimated you.", "Carefully...", "Impossible! You can't avoid my blows!" },
      { "Whoa! Pretty good, Teo's little boy. Now it's my turn!", "Arghhh! I underestimated you.", "Well done. You're a worthy opponent. Now it's my turn!" },
      { "That's nothing!", "Forget it. You're methods are obvious.", "I'll show you how it's done." },
      { "You're better than I thought. But how about this?", "What now?", "Interesting. How about another round?" },
    },
  },
  TEO_MCDOHL = {
    file = "shu_teo.bin",
    structPtr = 0x800a1dd0,
    player = "McDohl",
    enemy = { name = "Teo", hp = 180, hpMax = 360, str = 240, def = 105 },
    dialogue = {
      { "Here I come, my son.", "Show me what you've learned.", "My sword is the Emperor's sword. I'll show no mercy!" },
      { "Well done!", "Good, try it again!", "Can you avoid my sword?" },
      { "That was nothing. Now it's my turn.", "I'll see you coming next time!", "My deadly sword..." },
      { "Do you see how much better I am?", "Is that all you've got?", "Hmmm. Here I come again!" },
      { "Is defending yourself all you can do? You'll never win that way.", "Come on! Show me what a man you've become.", "The next one will be more painful." },
      { "We're getting nowhere. Here I come!", "Leader of the Liberation Army! No wonder you're careful.", "If you don't attack, I will!" },
      { "Did you see that coming?", "Well done! I must be more careful too.", "Are you trying to surpass me?" },
      { "That was pretty good. Now it's my turn.", "I'm losing my cool. I must be more cautious!", "Now that I've seen what you've got, I'll show you what I can do." },
      { "You're soft...soft! This is how you attack!", "I underestimated you! What's wrong? Another round?", "That's...no good." },
      { "The numbness in my hands, it's real!", "I mustn't underestimate you.", "I'm delighted, my son. You're quite a warrior. But here's another!" },
    },
  },
  TEO_PAHN = {
    file = "pan_teo.bin",
    structPtr = 0x800a2340,
    player = "Pahn",
    enemy = { name = "Teo", hp = 370, hpMax = 370, str = 290, def = 150 },
    dialogue = {
      { "My sword's not rusty yet.", "Strike me, Pahn!", "Finish me with a single blow!" },
      { "Pretty good, Pahn.", "All right, do it again!", "Can you dodge my blade, Pahn?" },
      { "Is that all you've got? Now it's my turn!", "I'll see that coming next time!", "My killer blade..." },
      { "Do you see how we're mismatched?", "Do you give up?", "Hmmm. Here I come again!" },
      { "All you can do is defend yourself, Pahn? No mercy!", "Come on, Pahn. See if you can kill me.", "The next one will be more painful." },
      { "We're getting nowhere. Here I come!", "You're a smart one, Pahn.", "If you don't attack, I will!" },
      { "Did you see me coming?", "Good work, Pahn. I'll have to be more careful.", "Impossible! Take that!" },
      { "That was a good one, Pahn. Now it's my turn.", "I'm losing my cool. Better be careful.", "Now that I've seen what you've got, I'll show you what I can do." },
      { "Get serious, Pahn. This is how it's done.", "What's the matter, Pahn? How about another round?", "That's...no good." },
      { "The numbness in my hands, it's real.", "You're better than I thought.", "Excellent, Pahn. You're a real fighter. Here's another!" },
    },
  },
}

-- C truncating division (both operands are non-negative everywhere it's used here, but keep
-- the semantics explicit).
local function cDiv(num, den)
  local q = math.abs(num) // math.abs(den)
  if (num < 0) ~= (den < 0) then q = -q end
  return q
end

-- duel_pick_enemy_move (0x80087898): ((rand()*3) / 0x7fff) % 3.
-- r in [0, 0x2aaa] -> Attack, [0x2aab, 0x5554] -> Defend, [0x5555, 0x7ffe] -> Desperate, and
-- r == 0x7fff wraps (3 % 3) back to Attack.
local function enemyMoveFromRand(r)
  return cDiv(r * 3, 0x7fff) % 3
end

-- duel_apply_hit (0x80084634) for the side taking the hit. One rand() call.
--   base = max(attackerSTR - defenderDEF, 1)
--   dmg  = base + ((base / 100) * rand()) % 10      -- +0..9, and 0 bonus while base < 100
--   HALF:           dmg / 2
--   DOUBLE/COUNTER: dmg * 2, raised to defenderCurHP / 4 if that's larger
-- No floor at 1 after halving (base 1 halves to 0).
local function hitDamage(attackerSTR, defenderDEF, defenderHP, flag, r)
  local base = attackerSTR - defenderDEF
  if base < 1 then base = 1 end
  local dmg = base + (cDiv(base, 100) * r) % 10
  if flag == HIT.HALF then
    dmg = cDiv(dmg, 2)
  elseif flag == HIT.DOUBLE or flag == HIT.COUNTER then
    dmg = dmg * 2
    local floorDmg = cDiv(defenderHP, 4)
    if dmg < floorDmg then dmg = floorDmg end
  end
  return dmg
end

-- State: { seed = <raw 32-bit RNG>, lastOutcome = 0..9,
--          sides = { [0] = {hp,hpMax,str,def}, [1] = {hp,hpMax,str,def} } }
local function newState(duelKey, seed, player)
  local duel = DUELS[duelKey]
  assert(duel, "unknown duel " .. tostring(duelKey))
  local e = duel.enemy
  return {
    duel = duel,
    seed = seed,
    calls = 0,
    lastOutcome = 0,
    round = 0,
    sides = {
      [0] = { hp = player.hp, hpMax = player.hpMax, str = player.str, def = player.def },
      [1] = { hp = e.hp, hpMax = e.hpMax, str = e.str, def = e.def },
    },
  }
end

local function cloneState(s)
  local c = {}
  for k, v in pairs(s) do c[k] = v end
  c.sides = {
    [0] = { hp = s.sides[0].hp, hpMax = s.sides[0].hpMax, str = s.sides[0].str, def = s.sides[0].def },
    [1] = { hp = s.sides[1].hp, hpMax = s.sides[1].hpMax, str = s.sides[1].str, def = s.sides[1].def },
  }
  return c
end

local function rand(s)
  s.seed = RNGLib.nextRNG(s.seed)
  s.calls = s.calls + 1
  return RNGLib.getRNG2(s.seed)
end

-- Round start: rolls the enemy's move and picks its line. Mutates state (consumes 1 rand()).
-- Returns enemyMove, line.
local function startRound(s)
  local move = enemyMoveFromRand(rand(s))
  s.round = s.round + 1
  s.enemyMove = move
  return move, s.duel.dialogue[s.lastOutcome + 1][move + 1]
end

-- Round resolution for the player's chosen move (after startRound). Mutates state.
-- Returns { outcome, hits = { {side, flag, damage}... }, result = nil|"win"|"lose" }.
-- The death check runs after the whole round (both hits always land and both always roll);
-- the player's HP is checked first, so a double KO is a loss.
local function resolveRound(s, playerMove)
  local outcome = playerMove * 3 + s.enemyMove + 1
  local hits = {}
  for _, h in ipairs(OUTCOME_HITS[outcome]) do
    local def = s.sides[h.side]
    local atk = s.sides[1 - h.side]
    local dmg = hitDamage(atk.str, def.def, def.hp, h.flag, rand(s))
    def.hp = def.hp - dmg
    if def.hp > def.hpMax then def.hp = def.hpMax end
    hits[#hits + 1] = { side = h.side, flag = h.flag, damage = dmg }
  end
  s.lastOutcome = outcome
  local result
  if s.sides[0].hp < 1 then
    result = "lose"
  elseif s.sides[1].hp < 1 then
    result = "win"
  end
  s.result = result
  return { outcome = outcome, hits = hits, result = result }
end

-- Convenience: play one full round from a state without mutating it.
-- Returns the new state plus a summary.
local function playRound(s, playerMove)
  local n = cloneState(s)
  local enemyMove, line = startRound(n)
  local r = resolveRound(n, playerMove)
  r.enemyMove, r.line = enemyMove, line
  return n, r
end

-- What the enemy will do / say next round from this state, without consuming RNG.
local function peekRound(s)
  local n = cloneState(s)
  local move, line = startRound(n)
  return move, line
end

-- Counter-pick (what beats each enemy move): Attack -> Desperate, Defend -> Attack,
-- Desperate -> Defend.
local COUNTER = { [0] = MOVE.DESPERATE, [1] = MOVE.ATTACK, [2] = MOVE.DEFEND }

-- Plays the whole duel always choosing the counter to the rolled move (the "read the line"
-- strategy). Returns the final state and the per-round log. maxRounds guards infinite loops.
local function simulateCounterPlay(s, maxRounds)
  maxRounds = maxRounds or 100
  local log = {}
  local cur = s
  while not cur.result and #log < maxRounds do
    local move = peekRound(cur)
    local r
    cur, r = playRound(cur, COUNTER[move])
    r.playerMove = COUNTER[move]
    log[#log + 1] = r
  end
  return cur, log
end

return {
  MOVE = MOVE,
  MOVE_NAMES = MOVE_NAMES,
  HIT = HIT,
  OUTCOME_HITS = OUTCOME_HITS,
  COUNTER = COUNTER,
  DUELS = DUELS,
  enemyMoveFromRand = enemyMoveFromRand,
  hitDamage = hitDamage,
  newState = newState,
  cloneState = cloneState,
  startRound = startRound,
  resolveRound = resolveRound,
  playRound = playRound,
  peekRound = peekRound,
  simulateCounterPlay = simulateCounterPlay,
}
