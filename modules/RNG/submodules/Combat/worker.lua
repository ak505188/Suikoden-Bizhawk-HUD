local Address = require "lib.Address"
local RNGLib = require "lib.RNG"
local Gamestate = require "lib.Enums.Gamestate"
local Drawer = require "controllers.drawer"
local EnemyAIPredictor = require "lib.EnemyAIPredictor"

-- Offsets are all relative to the live battle-state struct pointed to by
-- Address.BATTLE_STATE_PTR (DAT_8017be3c in Ghidra). See:
--   docs/game_mechanics/Turn_Order.md
--   docs/game_mechanics/Battle_Damage_Formula.md
-- for how each of these was reverse-engineered and how confident we are in it.
local BattleOffsets = {
  PARTY_COUNT = 0x1c,        -- CONFIRMED
  ENEMY_COUNT = 0x20,        -- CONFIRMED
  TOTAL_COMBATANTS = 0x24,   -- CONFIRMED (party+enemy, turn-order loop bound)
  CURRENT_ACTOR = 0x8,       -- CONFIRMED (whose turn it is right now)
  PENDING_INDEX = 0x3420,    -- CONFIRMED (turn-order roll's winning index, copied into CURRENT_ACTOR
                             -- on the very next state-machine tick - see battle_advance_turn,
                             -- 0x800f3e98 - so Actor and Pending will almost always read equal;
                             -- catching them differ means you caught the single tick between roll
                             -- and copy)
  ROLL_GATE_COUNTDOWN = 0x1264, -- CONFIRMED: decremented once per tick by battle_advance_turn
                                 -- (0x800f3e98); only when it hits 0 does the engine re-roll the
                                 -- next actor via battle_select_enemy_target and write a new
                                 -- PENDING_INDEX. Gets reset to 30 specifically when a roll finds
                                 -- no eligible combatant (round complete, waiting to start the
                                 -- next one) - not otherwise traced (e.g. what resets it after a
                                 -- normal successful roll+copy).
  COMBATANT_ARRAY = 0xb40,  -- stride 0x54, index 1..TOTAL_COMBATANTS
  COMBATANT_STRIDE = 0x54,
  ENEMY_DATA_ARRAY = 0x50,  -- stride 0x8c, index 1..TOTAL_COMBATANTS
  ENEMY_DATA_STRIDE = 0x8c,
}

-- NOTE (live-observed 2026-09): an enemy's combatant_rec fields can read as
-- all-zero/junk during command selection and even during another
-- combatant's action animation - they only become accurate once that
-- enemy's own turn actually starts. Party members don't show this lag.
-- Likely the game only populates an enemy's live combatant record
-- on-demand right before it's needed, rather than up-front at battle
-- start like it does for the party. Not a bug in these offsets - just
-- don't trust an enemy row here until you've seen it act at least once.

-- Offsets relative to a single combatant record (COMBATANT_ARRAY + idx*COMBATANT_STRIDE)
local CombatantFields = {
  -- RE-ENABLED 2026-09 (user request): now read in readBattleState and shown in the table,
  -- to visually confirm ATK/DEF's own accuracy lag (see the NOTE above CombatantFields) - user
  -- recalled ATK/DEF specifically read wrong until a combatant's own turn actually starts.
  AGL = 0x2a,          -- CONFIRMED: the turn-order speed stat (weight = AGL*10 - 5 + rand()%10); == persistent SPD exactly
  SKL = 0x26,          -- CONFIRMED (matches persistent SKL exactly): used for hit chance (opposed, attacker vs target) and crit chance ((SKL+LUK)/8)
  LUK = 0x2e,          -- CONFIRMED (matches persistent LUK exactly): used with SKL for crit chance
  MGC = 0x2c,          -- CONFIRMED via live gameplay math (Charm Arrow, attacker MGC=190, weak
                       -- target: (500+floor(190/2))*2=1190 matched observed damage exactly) -
                       -- see apply_elemental_multiplier's base_total = base_power + floor(MGC/2)
  ATK = 0x30,          -- CORRECTED 2026-09 (user clarification): this is ATK, not PWR - PWR is
                       -- the base persistent stat, ATK = PWR + the equipped weapon's attack
                       -- bonus, which is why it doesn't match persistent base PWR exactly.
                       -- Used in calc_damage's base-value step (attacker.ATK - target.DEF).
  DEF = 0x32,          -- DEF-like defense stat used in calc_damage. NOTE: does not always match persistent base DEF either - likely includes equipment bonus
  ACTION_TAG = 0x46,   -- 0 = hasn't acted/no action queued, 1 = executing/executed an attack.
                       -- Displayed as "F" (Finished) in the Combat viewer.
  ACTION_TYPE = 0x47,  -- CONFIRMED 2026-09 (user-verified live in-game, matches a real jump
                       -- table at 0x800c13ec): 0=Attack, 1=Defend, 2=Rune, 3=Item, 4=Unite.
                       -- Previously mislabeled "IsDefending"/boolean - calc_damage's Defend
                       -- check does compare == 1 exactly, so that earlier reading wasn't wrong,
                       -- just incomplete (didn't realize 2/3/4 were other real commands).
  ABILITY_SLOT = 0x48, -- CONFIRMED: the selected Rune/Item/Unite menu slot index (meaning
                       -- depends on ACTION_TYPE) - resolved into an actual spell/item/unite id
                       -- by battle_select_special_ability (Rune, 0x800f5500),
                       -- battle_try_special_attack (Item, 0x800f5050), or
                       -- battle_select_unite_attack (Unite, 0x800f5790) respectively. Unused
                       -- for Attack/Defend.
  TARGET = 0x49,       -- CONFIRMED: the selected target's combatant index. Same field read by
                       -- battle_execute_player_attack (Attack) and all three ability
                       -- resolvers above (Rune/Item/Unite) - one shared target slot
                       -- regardless of ACTION_TYPE.
  HP_MAX = 0x10,       -- CONFIRMED live 2026-09 (user cross-check): was guessed reversed at first
  HP_CURRENT = 0x12,   -- CONFIRMED live 2026-09 (user cross-check): was guessed reversed at first
}

-- Offsets relative to a single enemy-data record (ENEMY_DATA_ARRAY + idx*ENEMY_DATA_STRIDE)
local EnemyDataFields = {
  ID = 0x0,       -- CONFIRMED "Id", not "Species": indexes attack_data_table for elemental
                  -- compatibility, but for party members it matches each character's unique
                  -- roster Id from lib/Characters/Addresses.lua exactly (e.g. Hero=8, Viktor=35) -
                  -- it's a per-character/per-monster identity, not a shared type/category value.
  BUSY = 0x5,     -- CORRECTED 2026-09 (user's live observation - this is NOT a dead/alive
                  -- flag, that was a misreading): a busy/reaction-state byte. User-observed
                  -- values: 0 = idle (not moving) OR dead (both read the same - can't tell
                  -- apart from this field alone), 1 = busy performing an action (attacking,
                  -- using/receiving a medicine item), 8 = being hit/targeted by an attack
                  -- (stays 8 even on a miss), 9 = seen when hit by a Unite attack specifically
                  -- - exact trigger for 8 vs 9 not confirmed. Code-side: battle_select_enemy_target
                  -- skips candidates where this is nonzero (don't pick someone mid-reaction as
                  -- the next actor) and battle_execute_player_attack blocks attacking a target
                  -- where this is nonzero (can't attack someone already mid-reaction) - both
                  -- consistent with a busy/state flag, not a death flag. The actual write sites
                  -- are believed to live inside the attack-animation bytecode interpreter
                  -- (play_attack_animation's opcode dispatch via PTR_LAB_8016babc, 0x800e3820) -
                  -- not yet traced to specific opcodes. Since 0 does not reliably mean "alive",
                  -- do NOT use this field alone to filter out dead combatants - see HPCurrent.
}

-- ACTION_TYPE(+0x47) decode, for display only - see CombatantFields.ACTION_TYPE above.
-- "Mag" (not "Run") for Rune - user-flagged 2026-09: "Run" reads too easily as the Flee/Run
-- command, which this is not.
local ActionTypeNames = { [0] = "Atk", [1] = "Def", [2] = "Mag", [3] = "Itm", [4] = "Unt" }
local ACTION_TYPE_MAX = 4 -- highest valid ActionType value (Unite)

-- CONFIRMED 2026-09 (user): ACTION_TYPE/ABILITY_SLOT/TARGET (+0x47/+0x48/+0x49) all read
-- 255 (0xFF) when a combatant's action is uninitialized/cleared - not a real ActionType==255
-- enum value, just a "nothing queued yet" fill pattern. Distinct from ACTION_TAG(+0x46)'s own
-- 0/1 "resolved" flag.
local UNSET_VALUE = 255
ActionTypeNames[UNSET_VALUE] = "---"

-- Which CombatantFields offset backs each writable key exposed via Worker:writeCombatantField.
local WritableFieldOffsets = {
  ActionType = CombatantFields.ACTION_TYPE,
  AbilitySlot = CombatantFields.ABILITY_SLOT,
  Target = CombatantFields.TARGET,
}

-- CONFIRMED 2026-09: Suikoden 1's automatic magic Unite spells (Scorched Earth, Storm
-- Fang, Water Dragon, Thor, Blazing Camp - see Suikosource's Unite Magic page) trigger
-- when two living party members BOTH have ActionType==2 (Rune) and AbilitySlot==4 (their
-- own Level-4 spell) queued in the same round - see battle_check_magic_unite, 0x800f5398,
-- and docs/game_mechanics/Battle_Damage_Formula.md's "Magic Unite spells" section. This
-- doesn't decode WHICH combo (that needs each caster's resolved element, not read here),
-- just flags that the condition for one is currently met.
local MAGIC_UNITE_ACTION_TYPE = 2
local MAGIC_UNITE_ABILITY_SLOT = 4

local function findPendingMagicUnite(state)
  local candidates = {}
  for idx = 1, state.PartyCount do
    local c = state.Combatants[idx]
    -- NOTE: deliberately checking HPCurrent > 0 here, not the "BSY"/Busy field - that
    -- field reads 0 for BOTH idle and dead combatants (user-confirmed 2026-09, see
    -- EnemyDataFields.BUSY above), so it can't be used to filter out the dead.
    if c and c.HPCurrent > 0 and c.ActionTag == 0
        and c.ActionType == MAGIC_UNITE_ACTION_TYPE
        and c.AbilitySlot == MAGIC_UNITE_ABILITY_SLOT then
      table.insert(candidates, idx)
    end
  end
  return candidates
end

local Worker = {
  ShowHPExperimental = true,
  InBattle = false,
  State = nil,
  ActionTypeNames = ActionTypeNames,
  ActionTypeMax = ACTION_TYPE_MAX,
  UnsetValue = UNSET_VALUE,
}

local function isInBattle()
  return memory.read_u8(Address.GAMESTATE) == Gamestate.BATTLE
end

function Worker:readBattleState()
  local base_raw = memory.read_u32_le(Address.BATTLE_STATE_PTR)
  if not Address.isValidPointer(base_raw) then return nil end
  local base = Address.sanitize(base_raw)

  local state = {
    Base = base,
    PartyCount = memory.read_u32_le(base + BattleOffsets.PARTY_COUNT),
    EnemyCount = memory.read_u32_le(base + BattleOffsets.ENEMY_COUNT),
    TotalCombatants = memory.read_u32_le(base + BattleOffsets.TOTAL_COMBATANTS),
    CurrentActor = memory.read_u32_le(base + BattleOffsets.CURRENT_ACTOR),
    PendingIndex = memory.read_u32_le(base + BattleOffsets.PENDING_INDEX),
    RollGateCountdown = memory.read_u32_le(base + BattleOffsets.ROLL_GATE_COUNTDOWN),
    Combatants = {},
  }

  local total = state.TotalCombatants
  if total < 0 or total > 16 then total = 0 end -- sanity guard against a garbage read

  for idx = 1, total do
    local rec = base + BattleOffsets.COMBATANT_ARRAY + idx * BattleOffsets.COMBATANT_STRIDE
    local ed = base + BattleOffsets.ENEMY_DATA_ARRAY + idx * BattleOffsets.ENEMY_DATA_STRIDE
    state.Combatants[idx] = {
      ActionTag = memory.read_u8(rec + CombatantFields.ACTION_TAG),
      ActionType = memory.read_u8(rec + CombatantFields.ACTION_TYPE),
      AbilitySlot = memory.read_u8(rec + CombatantFields.ABILITY_SLOT),
      Target = memory.read_u8(rec + CombatantFields.TARGET),
      HPCurrent = memory.read_u16_le(rec + CombatantFields.HP_CURRENT),
      HPMax = memory.read_u16_le(rec + CombatantFields.HP_MAX),
      Id = memory.read_u8(ed + EnemyDataFields.ID),
      Busy = memory.read_u8(ed + EnemyDataFields.BUSY),
      AGL = memory.read_u16_le(rec + CombatantFields.AGL),
      SKL = memory.read_u16_le(rec + CombatantFields.SKL),
      LUK = memory.read_u16_le(rec + CombatantFields.LUK),
      MGC = memory.read_u16_le(rec + CombatantFields.MGC),
      ATK = memory.read_u16_le(rec + CombatantFields.ATK),
      DEF = memory.read_u16_le(rec + CombatantFields.DEF),
    }
  end

  return state
end

-- idx is a raw 1-indexed actor number, same convention as readBattleState's Combatants table.
function Worker:getCombatantRecordAddress(idx)
  if not self.State then return nil end
  return self.State.Base + BattleOffsets.COMBATANT_ARRAY + idx * BattleOffsets.COMBATANT_STRIDE
end

-- Directly overwrites a combatant's queued action (ActionType/AbilitySlot/Target) in live
-- battle memory - the same fields the table above reads, at CombatantFields.ACTION_TYPE/
-- ABILITY_SLOT/TARGET. This lets a player's already-selected command be changed before it
-- resolves; it does not validate that `value` is a legal AbilitySlot/Target for the resulting
-- ActionType (see docs/game_mechanics/Battle_Damage_Formula.md's "Action selection" section -
-- an out-of-range slot/target is whatever the game's own resolver does with it, untested here).
function Worker:writeCombatantField(idx, key, value)
  local offset = WritableFieldOffsets[key]
  if not offset then return end
  local rec = self:getCombatantRecordAddress(idx)
  if not rec then return end
  memory.write_u8(rec + offset, value)
  -- Patch the already-read State too, so the menu reflects the write this same frame instead
  -- of lagging one frame behind the next readBattleState().
  if self.State and self.State.Combatants[idx] then
    self.State.Combatants[idx][key] = value
  end
end

function Worker:run()
  self.InBattle = isInBattle()
  if self.InBattle then
    self.State = self:readBattleState()
  else
    self.State = nil
  end
end

function Worker:draw()
  if not self.InBattle then
    Drawer:draw({ "Combat: not in battle" }, Drawer.anchors.TOP_LEFT, nil, true)
    return
  end

  local state = self.State
  if not state then
    Drawer:draw({ "Combat: battle struct ptr invalid" }, Drawer.anchors.TOP_LEFT, nil, true)
    return
  end

  local rng = memory.read_u32_le(Address.RNG)
  local rng2 = RNGLib.getRNG2(rng)

  local header_lines = {
    string.format("Base:0x%08x", state.Base),
    string.format("Actor:%d  Pending:%d  RollGateCD:%d",
      state.CurrentActor, state.PendingIndex, state.RollGateCountdown),
    string.format("RNG:0x%08x  RNG2:%d", rng, rng2),
  }
  Drawer:draw(header_lines, Drawer.anchors.TOP_LEFT, nil, true)

  local table_header = " #  ID F B ACTION"
  Drawer:draw({ table_header }, Drawer.anchors.TOP_LEFT, nil, true)

  local rows = {}
  for idx, c in ipairs(state.Combatants) do
    local marker = ""
    if idx == state.CurrentActor then marker = ">" end
    local actionStr
    if c.ActionType == UNSET_VALUE then
      actionStr = "---"
    else
      local actName = ActionTypeNames[c.ActionType] or tostring(c.ActionType)
      -- ACTION combines ACT/SLT/TGT: slot only shown for Rune/Item/Unite (2/3/4), where it's
      -- meaningful - see CombatantFields.ABILITY_SLOT.
      local slotStr = ""
      if c.ActionType >= 2 and c.ActionType <= 4 then
        slotStr = c.AbilitySlot == UNSET_VALUE and "--" or tostring(c.AbilitySlot)
      end
      local targetStr = c.Target == UNSET_VALUE and "--" or tostring(c.Target)
      actionStr = string.format("%s%s>%s", actName, slotStr, targetStr)
    end
    table.insert(rows, string.format("%1s%1x %3d %1d %1d %s",
      marker, idx, c.Id, c.ActionTag, c.Busy, actionStr))
  end
  Drawer:draw(rows, Drawer.anchors.TOP_LEFT)

  -- RE-ENABLED 2026-09 (user request): watch ATK/DEF specifically for the pre-turn accuracy
  -- lag the user recalled (SKL/AGL/MGC/LUK are already confirmed accurate at all times, shown
  -- alongside for comparison).
  Drawer:draw({ " #  SKL AGL MGC LUK  ATK   DEF" }, Drawer.anchors.TOP_LEFT, nil, true)
  local stat_rows = {}
  for idx, c in ipairs(state.Combatants) do
    table.insert(stat_rows, string.format("%1x %4d %4d %4d %4d %5d %5d",
      idx, c.SKL, c.AGL, c.MGC, c.LUK, c.ATK, c.DEF))
  end
  Drawer:draw(stat_rows, Drawer.anchors.TOP_LEFT)

  local uniteCandidates = findPendingMagicUnite(state)
  if #uniteCandidates >= 2 then
    Drawer:draw({ string.format("Magic Unite pending: slots %s (Rune+Lv4 both queued)",
      table.concat(uniteCandidates, ",")) }, Drawer.anchors.TOP_LEFT, nil, true)
  end

  if self.ShowHPExperimental then
    Drawer:draw({ "Enemy HP" }, Drawer.anchors.TOP_LEFT, nil, true)
    local hp_rows = {}
    for idx, c in ipairs(state.Combatants) do
      if idx > state.PartyCount then
        table.insert(hp_rows, string.format("%1d %d/%d", idx, c.HPCurrent, c.HPMax))
      end
    end
    Drawer:draw(hp_rows, Drawer.anchors.TOP_LEFT)
  end

  -- ADDED 2026-09-06, CHANGED TO PROBABILITIES 2026-09-06 (user request: odds for every enemy,
  -- not a single simulated result for whoever's currently acting): for every LIVING enemy
  -- whose AI formula has been traced (see lib/EnemyAIPredictor.lua and
  -- Enemy_AI_Tracing_Methodology.md - only Zombie Dragon is live-validated, the rest are
  -- structurally confirmed only), shows the exact move and target probability distribution,
  -- computed from the formula's own known RNG2 odds - not from rolling/simulating anything, so
  -- this is stable frame-to-frame (unlike a sampled outcome would be) and meaningful even
  -- before it's actually that enemy's turn.
  local aiPredictions = EnemyAIPredictor:predictAll()
  if aiPredictions and #aiPredictions > 0 then
    Drawer:draw({ "Enemy AI odds" }, Drawer.anchors.TOP_LEFT, nil, true)
    local ai_rows = {}
    for _, p in ipairs(aiPredictions) do
      -- Move names vary per monster (Zombie Dragon: Attack/Fire Breath; most others: Attack/
      -- Special - see EnemyAIPredictor.lua's KNOWN_AI) - iterate whatever keys are actually
      -- present rather than a hardcoded pair.
      local moveNames = {}
      for moveName in pairs(p.MoveProbs) do table.insert(moveNames, moveName) end
      table.sort(moveNames)
      local moveParts = {}
      for _, moveName in ipairs(moveNames) do
        table.insert(moveParts, string.format("%s:%d%%", moveName, math.floor(p.MoveProbs[moveName] * 100 + 0.5)))
      end
      local targetParts = {}
      for targetIdx, prob in pairs(p.TargetProbs) do
        table.insert(targetParts, { targetIdx, prob })
      end
      table.sort(targetParts, function(a, b) return a[1] < b[1] end)
      local targetStrs = {}
      for _, pair in ipairs(targetParts) do
        table.insert(targetStrs, string.format("%d:%d%%", pair[1], math.floor(pair[2] * 100 + 0.5)))
      end
      table.insert(ai_rows, string.format("%1d: %s | tgt %s",
        p.EnemyActorIdx, table.concat(moveParts, " "),
        #targetStrs > 0 and table.concat(targetStrs, " ") or "none eligible"))
    end
    Drawer:draw(ai_rows, Drawer.anchors.TOP_LEFT)
  end
end

function Worker:onChange() end

return Worker
