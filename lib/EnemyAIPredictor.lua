-- Computes PROBABILITY DISTRIBUTIONS over a monster's next move/target from its own
-- traced-and-validated AI formula (see docs/game_mechanics/Battle_Damage_Formula.md's "AI/enemy
-- move selection" section and docs/game_mechanics/Enemy_AI_Tracing_Methodology.md for how these
-- get found) - not a single simulated/sampled outcome. Pure read-only math: never touches
-- Address.RNG or any other live memory write.
--
-- Deliberately keyed by each monster's own AI function address (read live from
-- attack_data_table[Id]+0x30, the same call site battle_dispatch_current_actor_action uses) -
-- not by Id or name - so this only ever reports probabilities for a monster whose formula has
-- actually been traced, and silently omits anything else, rather than guessing at an untraced
-- monster's behavior. Add a new monster by tracing it per Enemy_AI_Tracing_Methodology.md, then
-- adding one entry to KNOWN_AI below.
--
-- CONFIDENCE LEVELS: only Zombie Dragon's formula has been live-validated (10/10 exact match
-- against captured battle data across 10 seeds - see Battle_Damage_Formula.md). Every other
-- entry below was found offline (charmap name-search across the disc's overlay files - see
-- Enemy_AI_Tracing_Methodology.md) and is only STRUCTURALLY confirmed: the decompiled code
-- matches a known-good shape exactly, but hasn't been checked against real captured seeds.
-- Treat these as "very likely correct" rather than "confirmed."

local Address = require "lib.Address"

local EnemyAIPredictor = {}

-- RNG2 is uniform over exactly 32768 values (0-32767), so these are exact rational
-- probabilities baked into the traced formula, not simulated/approximated:
--   - target-accept: `roll % 100 > 50` - remainders 51-99 (49 of the 100 possible remainders),
--     weighted by how many of the 32768 RNG2 values actually produce each remainder (32768 =
--     327*100 + 68, so remainders 0-67 occur 328 times each, 68-99 occur 327 times each;
--     51-67 - 17 remainders - fall in the 328-count band, 68-99 - 32 remainders - in the
--     327-count band): (17*328 + 32*327) / 32768.
--   - move-select `(roll*100)//32767 < N`: true for roll in [0, ceil(N*32767/100)-1] - see
--     each threshold below for its own exact count.
local TARGET_ACCEPT_PROB = (17 * 328 + 32 * 327) / 32768

-- (roll*100)//32767 < N  <=>  roll*100 < N*32767  <=>  roll < N*32767/100  <=>  roll <=
-- ceil(N*32767/100) - 1 (careful with the exact boundary - matches Zombie Dragon's own
-- confirmed N=0x47(71) -> 23265/32768 derivation).
local function moveThresholdProb(n)
  local maxRoll = math.ceil(n * 32767 / 100) - 1
  return (maxRoll + 1) / 32768
end

-- Generic "eventual" target-distribution helper: given an ORDERED list of eligible candidates
-- (already filtered/scanned in the real AI's own order) and a per-candidate accept probability,
-- returns { [actorIdx] = probability }, normalized so retry-until-someone-accepts doesn't leave
-- probability mass on "nobody" (see zombieDragonProbabilities's own fuller comment - this is
-- the exact closed-form sum of the infinite "keep retrying" geometric series, not an
-- approximation).
local function targetDistribution(eligible, acceptProb)
  local targetProbs = {}
  if #eligible > 0 then
    local pReject = 1 - acceptProb
    local normalize = 1 - pReject ^ #eligible
    for i, idx in ipairs(eligible) do
      targetProbs[idx] = (acceptProb * pReject ^ (i - 1)) / normalize
    end
  end
  return targetProbs
end

-- Zombie Dragon's traced+validated formula (see Battle_Damage_Formula.md) - the ONLY
-- live-validated entry in this file (10/10 exact match). `ctx.frontRow` is the eligible
-- front-row/alive/not-busy candidate list in formation order.
local function zombieDragonProbabilities(ctx)
  local targetProbs = targetDistribution(ctx.frontRow, TARGET_ACCEPT_PROB)
  local moveProbs
  if ctx.roundCounter == 1 then
    moveProbs = { Attack = 0, ["Fire Breath"] = 1 }
  else
    local attackProb = moveThresholdProb(0x47)
    moveProbs = { Attack = attackProb, ["Fire Breath"] = 1 - attackProb }
  end
  return targetProbs, moveProbs
end

-- Factory for the "standard" shape shared by several bosses (structurally confirmed, not
-- live-validated): front-row-only target scan, then a single move-probability split with no
-- round-counter override. `specialName` is just a label (the actual special move isn't
-- individually identified/named for these).
local function makeFrontRowSplitTemplate(attackThresholdN, specialName)
  local attackProb = moveThresholdProb(attackThresholdN)
  return function(ctx)
    local targetProbs = targetDistribution(ctx.frontRow, TARGET_ACCEPT_PROB)
    local moveProbs = { Attack = attackProb, [specialName] = 1 - attackProb }
    return targetProbs, moveProbs
  end
end

-- Factory for bosses with a front-row-only scan but NO special move at all (Varkas, the
-- "Pirates" trio) - always plain Attack once a target's locked in.
local function makeFrontRowAttackOnlyTemplate()
  return function(ctx)
    return targetDistribution(ctx.frontRow, TARGET_ACCEPT_PROB), { Attack = 1 }
  end
end

-- Neclord: front-row-only scan, but ALWAYS uses its one special move once a target's locked
-- in (no move-probability gate at all).
local function neclordProbabilities(ctx)
  return targetDistribution(ctx.frontRow, TARGET_ACCEPT_PROB), { ["Special"] = 1 }
end

-- Sydonia: scans ALL 6 party members (not just front row), then the move is fully DETERMINED
-- by the chosen target's own row (front row -> always special, back row -> always plain
-- Attack) - no real RNG in the move choice itself. See
-- sydonia_ai_select_target_and_move's own Ghidra plate comment for the full derivation
-- (including a confirmed-unreachable counterattack sub-mechanism, not modeled here since it
-- never fires).
local function sydoniaProbabilities(ctx)
  local targetProbs = targetDistribution(ctx.all, TARGET_ACCEPT_PROB)
  local attackProb, specialProb = 0, 0
  for idx, prob in pairs(targetProbs) do
    if ctx.formationPos[idx] and ctx.formationPos[idx] <= 3 then
      specialProb = specialProb + prob
    else
      attackProb = attackProb + prob
    end
  end
  return targetProbs, { Attack = attackProb, Special = specialProb }
end

-- Assassin: front-row-only scan; move escalates by round count - always uses its special move
-- once past round 2, otherwise a normal probability split.
local function assassinProbabilities(ctx)
  local targetProbs = targetDistribution(ctx.frontRow, TARGET_ACCEPT_PROB)
  local moveProbs
  if ctx.roundCounter > 2 then
    moveProbs = { Attack = 0, Special = 1 }
  else
    local attackProb = moveThresholdProb(0x33)
    moveProbs = { Attack = attackProb, Special = 1 - attackProb }
  end
  return targetProbs, moveProbs
end

-- AI function address (attack_data_table[Id]+0x30, in the small overlay at 0x80010000, NOT
-- main.exe - see Enemy_AI_Tracing_Methodology.md) -> probabilities function(ctx) -> targetProbs,
-- moveProbs. `ctx` = { frontRow, all, formationPos, roundCounter } - see predictAll() below.
--
-- Only Zombie Dragon is live-validated. Everything else here is structurally confirmed only
-- (clean decompile matching a known-good shape) - see this file's own header.
-- Queen Ant and Crystal Core are traced (see their own Ghidra plate comments, va7.bin/vf2.bin)
-- but deliberately NOT included here - both have self/globally-triggered mechanics that don't
-- fit this module's "pick a party-member target" output shape.
local KNOWN_AI = {
  [0x80012968] = zombieDragonProbabilities,                    -- Zombie Dragon
  [0x80013d18] = neclordProbabilities,                         -- Neclord (ve1.bin)
  [0x8001675c] = neclordProbabilities,                          -- Neclord (ve3.bin, 2nd appearance)
  [0x800103b0] = makeFrontRowAttackOnlyTemplate(),              -- Varkas
  [0x8001234c] = sydoniaProbabilities,                          -- Sydonia
  [0x80010004] = makeFrontRowAttackOnlyTemplate(),              -- Pirates (Anji/Kanak/Leonardo)
  [0x80010ea4] = makeFrontRowSplitTemplate(0x47, "Special"),    -- Golem
  [0x8001186c] = makeFrontRowSplitTemplate(0x33, "Special"),    -- Gigantes
  [0x800178e4] = makeFrontRowSplitTemplate(0x33, "Special"),    -- Shell Venus
  [0x80018788] = makeFrontRowSplitTemplate(0x33, "Special"),    -- Sonya Shulen
  [0x80013b1c] = makeFrontRowSplitTemplate(0x33, "Special"),    -- Ain Gide
  [0x80012594] = neclordProbabilities,                          -- Dragon (final boss dragon,
                                                                 -- same "always special" shape
                                                                 -- as Neclord - found live from
                                                                 -- TurnOrderRNGCall.State, not
                                                                 -- the name-search)
  [0x8001789c] = assassinProbabilities,                         -- Assassin
}

-- Returns a list of { EnemyActorIdx, TargetProbs, MoveProbs } for every LIVING enemy whose AI
-- formula is recognized (see KNOWN_AI) - probability distributions, not a single simulated
-- result. Enemies whose AI isn't recognized are simply omitted from the list (not an error -
-- a caller iterating "every enemy" should expect some may be silently skipped). Returns
-- (nil, reason) only if not currently in a valid battle at all.
function EnemyAIPredictor:predictAll()
  local baseRaw = memory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(baseRaw) then return nil, "not in battle" end
  local base = Address.sanitize(baseRaw)

  local partyCount = memory.read_u32_le(base + 0x1c)
  local total = memory.read_u32_le(base + 0x24)
  local roundCounter = memory.read_u32_le(base + 0x4)

  -- Target eligibility doesn't depend on which enemy is asking - compute both candidate lists
  -- (front-row-only, and all 6) once, in formation order, matching the real AI's own scan
  -- order. Also keep each eligible member's own formation position (Sydonia's move-selection
  -- needs the CHOSEN target's row, not just who's eligible to be scanned).
  local frontRow, all, formationPos = {}, {}, {}
  for idx = 1, partyCount do
    local combatant0idx = base + 0xb94 + (idx - 1) * 0x54
    local ed0idx = base + 0xdc + (idx - 1) * 0x8c
    local rec = base + 0xb40 + idx * 0x54
    local pos = memory.read_u8(combatant0idx + 0x44)
    local validByte = memory.read_u8(combatant0idx + 0x45)
    local busy = memory.read_u8(ed0idx + 5)
    local hp = memory.read_u16_le(rec + 0x12)
    if validByte == 0 and busy == 0 and hp > 0 then
      table.insert(all, idx)
      formationPos[idx] = pos
      if pos < 4 then
        table.insert(frontRow, idx)
      end
    end
  end
  local ctx = { frontRow = frontRow, all = all, formationPos = formationPos, roundCounter = roundCounter }

  local attackDataTableRaw = memory.read_u32_le(base + 0x1344)
  if not Address.isValidPointer(attackDataTableRaw) then
    return nil, "attack_data_table pointer invalid"
  end
  local attackDataTable = Address.sanitize(attackDataTableRaw)

  local results = {}
  for idx = partyCount + 1, total do
    local rec = base + 0xb40 + idx * 0x54
    if memory.read_u16_le(rec + 0x12) > 0 then -- HPCurrent > 0, i.e. alive
      local ed = base + 0x50 + idx * 0x8c
      local id = memory.read_u8(ed + 0x0)
      local monsterRecordRaw = memory.read_u32_le(attackDataTable + id * 4)
      if Address.isValidPointer(monsterRecordRaw) then
        local monsterRecord = Address.sanitize(monsterRecordRaw)
        local aiFuncAddr = memory.read_u32_le(monsterRecord + 0x30)
        local probFunc = KNOWN_AI[aiFuncAddr]
        if probFunc then
          local targetProbs, moveProbs = probFunc(ctx)
          table.insert(results, {
            EnemyActorIdx = idx,
            TargetProbs = targetProbs,
            MoveProbs = moveProbs,
          })
        end
      end
    end
  end

  return results
end

return EnemyAIPredictor
